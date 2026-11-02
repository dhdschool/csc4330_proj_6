"""Fetches and normalizes the LSU Registrar's academic calendar.

LSU publishes these dates only as HTML tables, without years on the dates, so
this module scrapes the pages and turns each row into dated events.
"""

import asyncio
import calendar
import logging
import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Literal

import httpx
from bs4 import BeautifulSoup, Tag
from pydantic import BaseModel

logger = logging.getLogger(__name__)

BASE_URL = "https://www.lsu.edu/registrar/academics/academic-calendars"
INDEX_URL = f"{BASE_URL}/index.php"
USER_AGENT = "LSU-UniCalendar/0.1 (CSC 4330 class project)"
REFRESH_INTERVAL = timedelta(hours=24)
RETRY_INTERVAL = timedelta(minutes=15)

Category = Literal[
    "holiday",
    "classes",
    "exam",
    "deadline",
    "grades",
    "registration",
    "study_period",
    "orientation",
    "commencement",
    "other",
]


class CalendarEvent(BaseModel):
    id: str
    title: str
    description: str | None = None
    category: Category
    # Both dates are null only for events in the "unscheduled" list.
    start_date: date | None = None
    end_date: date | None = None
    date_text: str
    terms: list[str]
    academic_year: str
    tentative: bool = False
    # 24-hour local times for holidays that only cover part of a day.
    classes_end_at: str | None = None
    classes_resume_at: str | None = None


class CalendarParseError(Exception):
    """The page no longer looks like an academic calendar."""


class CalendarUnavailable(Exception):
    """LSU could not be reached and there is no earlier data to serve."""


_MONTHS = {name: number for number, name in enumerate(calendar.month_name) if name}
_MONTH_NAMES = "|".join(_MONTHS)
_RANGE_DATE = re.compile(
    rf"^({_MONTH_NAMES}) (\d{{1,2}})(?: - (?:({_MONTH_NAMES}) )?(\d{{1,2}}))?$"
)
_PAIR_DATE = re.compile(rf"^({_MONTH_NAMES}) (\d{{1,2}}) & (\d{{1,2}})$")
_TERM = re.compile(
    r"^(Fall Semester|Wintersession|Spring Semester|First Summer|Second Summer)\b.*?(\d{4})?$"
)
_TENTATIVE = re.compile(r"\s*\*+\s*tentative\s*\*+", re.IGNORECASE)
_HOLIDAY_BEGINS = re.compile(r"^(.*Holiday) begins(?: at (\S+) on .*)?$")
_CLASSES_RESUME = re.compile(r"Classes resume at (\S+)")
_NO_CLASSES = re.compile(r" - no classes held$")
_SUMMER_BREAK = re.compile(r"^(.+?) will serve as the Summer Break")
_CLASS_COUNT = re.compile(r"^\d+ .*Classes")
_YEAR_LINK = re.compile(r"(\d{4})-(\d{4})-academic-calendar\.php")


def _clean(text: str) -> str:
    # The source sometimes runs a closing quote into the next word: "W"and
    return re.sub(r'"(?=[a-z])', '" ', " ".join(text.split()))


def _categorize(title: str) -> Category:
    text = title.lower()
    # Order matters: "Final date to request rescheduling a final examination"
    # is a deadline and "Final grades due" is not an exam.
    if text.startswith("final date"):
        return "deadline"
    if "grades due" in text:
        return "grades"
    if text.startswith(("final exam", "final classes")):
        return "exam"
    if any(
        word in text
        for word in ("holiday", "spring break", "summer break", "memorial day", "juneteenth")
    ):
        return "holiday"
    if text.startswith(("classes begin", "classes resume", "last day of classes")):
        return "classes"
    if text.startswith("concentrated study"):
        return "study_period"
    if text.startswith("course scheduling"):
        return "registration"
    if "orientation" in text or "welcome week" in text:
        return "orientation"
    if text.startswith("commencement"):
        return "commencement"
    return "other"


def _to_24_hour(time_text: str | None) -> str | None:
    if not time_text:
        return None
    return datetime.strptime(time_text.lower(), "%I:%M%p").strftime("%H:%M")


def _parse_date_text(
    text: str, year_for_month: Callable[[int], int]
) -> list[tuple[date, date]] | None:
    """Returns (start, end) spans, or None if the text isn't a usable date.

    "June 26 & 28" means two separate days, so it returns two spans.
    """
    text = re.sub(r"\s*[-–—]\s*", " - ", text)

    def make(month_name: str, day: str) -> date:
        month = _MONTHS[month_name]
        return date(year_for_month(month), month, int(day))

    try:
        if match := _PAIR_DATE.match(text):
            month, first, second = match.groups()
            return [(make(month, day), make(month, day)) for day in (first, second)]
        if match := _RANGE_DATE.match(text):
            month, day, end_month, end_day = match.groups()
            start = make(month, day)
            end = make(end_month or month, end_day) if end_day else start
            return [(start, end)]
    except ValueError:  # e.g. "February 30"
        return None
    return None


@dataclass
class _Term:
    name: str
    year_for_month: Callable[[int], int]


def _resolve_term(heading: str, start_year: int, end_year: int, seen_fall: bool) -> _Term | None:
    match = _TERM.match(heading)
    if not match:
        return None
    season, stated = match.groups()
    if season == "Fall Semester":
        year = int(stated or start_year)
    elif season == "Spring Semester":
        year = int(stated or end_year)
    elif season == "Wintersession":
        # Wintersession is named for the year it starts in and runs into January.
        year = int(stated or start_year)
        return _Term(f"{season} {year}", lambda month: year if month >= 8 else year + 1)
    else:
        # Summer has no year in its heading. Some pages also list the previous
        # summer above the fall table, and that one belongs to the start year.
        year = int(stated or (end_year if seen_fall else start_year))
    return _Term(f"{season} {year}", lambda month: year)


def _split_paragraphs(cell: Tag) -> list[str]:
    """Returns one string per event, keeping policy text with its event."""
    texts = [_clean(p.get_text(" ", strip=True)) for p in cell.find_all("p")]
    texts = [text for text in texts if text] or [_clean(cell.get_text(" ", strip=True))]
    merged: list[str] = []
    for text in texts:
        if text.startswith("Graded coursework") and merged:
            merged[-1] = f"{merged[-1].rstrip('.')}. {text}"
        else:
            merged.append(text)
    return merged


def _event_id(prefix: str, title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", f"{prefix}-{title}".lower()).strip("-")


def _build_events(
    text: str,
    date_text: str,
    term: _Term,
    academic_year: str,
) -> list[CalendarEvent]:
    tentative = bool(_TENTATIVE.search(text) or _TENTATIVE.search(date_text))
    date_text = _TENTATIVE.sub("", date_text)
    text = _NO_CLASSES.sub("", _TENTATIVE.sub("", text)).rstrip(".")

    title, _, description = text.partition(". ")
    classes_end_at = None
    if match := _HOLIDAY_BEGINS.match(title):
        title, classes_end_at = match.group(1), _to_24_hour(match.group(2))
        if classes_end_at:
            description = text
    category = _categorize(title)
    resume = _CLASSES_RESUME.search(description) if category == "holiday" else None

    fields = {
        "title": title,
        "description": description or None,
        "category": category,
        "date_text": date_text,
        "terms": [term.name],
        "academic_year": academic_year,
        "tentative": tentative,
        "classes_end_at": classes_end_at,
        "classes_resume_at": _to_24_hour(resume.group(1)) if resume else None,
    }

    spans = _parse_date_text(date_text, term.year_for_month)
    if spans is None:
        if date_text.upper() != "TBD":
            logger.warning("Unrecognized date %r for %r in %s", date_text, title, term.name)
        return [CalendarEvent(id=_event_id(f"tbd-{term.name}", title), **fields)]
    return [
        CalendarEvent(
            id=_event_id(start.isoformat(), title), start_date=start, end_date=end, **fields
        )
        for start, end in spans
    ]


def _extend_winter_holiday(events: list[CalendarEvent]) -> None:
    # The page only says "Winter Holiday begins" and, later, "Classes resume".
    resumes = next((e for e in events if e.title == "Classes resume" and e.start_date), None)
    for event in events:
        if event.title == "Winter Holiday" and event.start_date and resumes:
            event.end_date = resumes.start_date - timedelta(days=1)


def parse_calendar_page(html: str, academic_year: str) -> list[CalendarEvent]:
    """Parses one academic year's page into events.

    Raises CalendarParseError if the page has no recognizable calendar tables.
    """
    start_year, end_year = (int(part) for part in academic_year.split("-"))
    soup = BeautifulSoup(html, "html.parser")
    events: list[CalendarEvent] = []
    seen_fall = False

    for table in soup.find_all("table"):
        heading = table.find_previous(["h1", "h2", "h3", "h4", "h5", "h6"])
        heading_text = _clean(heading.get_text(" ", strip=True)) if heading else ""
        term = _resolve_term(heading_text, start_year, end_year, seen_fall)
        if term is None:
            logger.warning(
                "Skipping table under unknown heading %r in %s", heading_text, academic_year
            )
            continue
        seen_fall = seen_fall or heading_text.startswith("Fall")

        term_events: list[CalendarEvent] = []
        for row in table.find_all("tr"):
            cells = row.find_all(["td", "th"], recursive=False)
            if len(cells) == 2:
                date_text = _clean(cells[0].get_text(" ", strip=True))
                if date_text == "Date":
                    continue
                for text in _split_paragraphs(cells[1]):
                    term_events += _build_events(text, date_text, term, academic_year)
            elif len(cells) == 1:
                text = _clean(cells[0].get_text(" ", strip=True))
                if match := _SUMMER_BREAK.match(text):
                    summer_break = _build_events(
                        "Summer Break", match.group(1), term, academic_year
                    )
                    for event in summer_break:
                        event.description = text
                    term_events += summer_break
                elif not _CLASS_COUNT.match(text):
                    logger.warning("Ignoring footnote %r in %s", text, term.name)

        _extend_winter_holiday(term_events)
        events += term_events

    if not events:
        raise CalendarParseError(f"No calendar events found for {academic_year}")
    return events


def merge_events(events: list[CalendarEvent]) -> tuple[list[CalendarEvent], list[CalendarEvent]]:
    """Returns (scheduled, unscheduled), both sorted, with duplicates combined.

    Commencement is listed under both summer terms, for example, but is a
    single event on a calendar.
    """
    scheduled: dict[str, CalendarEvent] = {}
    unscheduled: dict[str, CalendarEvent] = {}
    for event in events:
        target = scheduled if event.start_date else unscheduled
        existing = target.get(event.id)
        if existing is None:
            target[event.id] = event.model_copy(deep=True)
        else:
            existing.terms += [term for term in event.terms if term not in existing.terms]
    return (
        sorted(scheduled.values(), key=lambda e: (e.start_date, e.title)),
        sorted(unscheduled.values(), key=lambda e: e.id),
    )


def find_academic_years(index_html: str, today: date) -> list[str]:
    """Lists the years linked from the index, skipping ones that already ended."""
    years = {
        (int(start), int(end))
        for start, end in _YEAR_LINK.findall(index_html)
        if int(end) >= today.year
    }
    return [f"{start}-{end}" for start, end in sorted(years)]


def _page_url(academic_year: str) -> str:
    return f"{BASE_URL}/{academic_year}/{academic_year}-academic-calendar.php"


@dataclass(frozen=True)
class CalendarSnapshot:
    events: list[CalendarEvent]
    unscheduled: list[CalendarEvent]
    fetched_at: datetime
    # True when the last refresh failed for part of the data, so some of it
    # may be out of date or missing.
    stale: bool


class LsuCalendarService:
    """Serves the calendar from memory, refreshing it from LSU once a day."""

    def __init__(
        self,
        transport: httpx.AsyncBaseTransport | None = None,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self._transport = transport
        self._now = now
        self._lock = asyncio.Lock()
        self._pages: dict[str, list[CalendarEvent]] = {}
        self._snapshot: CalendarSnapshot | None = None
        self._next_refresh: datetime | None = None

    async def get_snapshot(self) -> CalendarSnapshot:
        async with self._lock:
            if self._snapshot is None or self._now() >= self._next_refresh:
                await self._refresh()
            if self._snapshot is None:
                raise CalendarUnavailable("Could not load the LSU academic calendar")
            return self._snapshot

    async def _refresh(self) -> None:
        async with httpx.AsyncClient(
            transport=self._transport,
            headers={"User-Agent": USER_AGENT},
            follow_redirects=True,
            timeout=20,
        ) as client:
            try:
                response = await client.get(INDEX_URL)
                response.raise_for_status()
                years = find_academic_years(response.text, self._now().date())
                failed = not years
                if failed:
                    logger.error("No academic years found on %s", INDEX_URL)
            except httpx.HTTPError as error:
                logger.error("Could not fetch %s: %s", INDEX_URL, error)
                years, failed = [], True
            years = years or list(self._pages)

            results = await asyncio.gather(
                *(self._fetch_page(client, year) for year in years),
                return_exceptions=True,
            )

        pages: dict[str, list[CalendarEvent]] = {}
        for year, result in zip(years, results):
            if isinstance(result, Exception):
                logger.error("Could not refresh %s: %s", year, result)
                failed = True
                if year in self._pages:
                    pages[year] = self._pages[year]
            else:
                pages[year] = result

        now = self._now()
        if pages:
            self._pages = pages
            events, unscheduled = merge_events([e for page in pages.values() for e in page])
            self._snapshot = CalendarSnapshot(events, unscheduled, now, failed)
        self._next_refresh = now + (RETRY_INTERVAL if failed else REFRESH_INTERVAL)

    async def _fetch_page(
        self, client: httpx.AsyncClient, academic_year: str
    ) -> list[CalendarEvent]:
        response = await client.get(_page_url(academic_year))
        response.raise_for_status()
        return parse_calendar_page(response.text, academic_year)
