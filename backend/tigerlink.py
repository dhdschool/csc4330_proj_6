"""Fetches LSU club events from the TigerLink (CampusGroups) iCal feed.

TigerLink publishes every organization's public events as one iCalendar feed,
refreshed hourly. This module parses that feed into structured events, with the
same caching approach as the academic calendar.
"""

import asyncio
import hashlib
import logging
import quopri
import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

import httpx
from pydantic import BaseModel

from campus_places import locate, venue_of

logger = logging.getLogger(__name__)

FEED_URL = "https://tigerlink.lsu.edu/ical/lsu/ical_lsu.ics"
SOURCE_URL = "https://tigerlink.lsu.edu/events"
USER_AGENT = "LSU-UniCalendar/0.1 (CSC 4330 class project)"
# The feed advertises X-PUBLISHED-TTL: PT1H, so there's no point refreshing faster.
REFRESH_INTERVAL = timedelta(hours=1)
RETRY_INTERVAL = timedelta(minutes=15)

# CampusGroups uses this placeholder when a location is only shown to signed-in
# users, so it isn't a real location to display.
_HIDDEN_LOCATION = "sign in to download the location"
_EVENT_ID = re.compile(r"[?&]id=(\d+)")


class ClubEvent(BaseModel):
    id: str
    title: str
    description: str | None = None
    # Timezone-aware; the feed publishes everything in UTC.
    start: datetime
    end: datetime | None = None
    all_day: bool = False
    # The raw TigerLink location text.
    location: str | None = None
    # The location without the default Student Union address CampusGroups
    # appends, e.g. "167 Coates Hall". Use this for display.
    venue: str | None = None
    # The campus building the venue was matched to, with its coordinates.
    # All three are null when the event can't be placed on the map.
    place: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    url: str | None = None
    club: str | None = None
    club_acronym: str | None = None
    event_type: str | None = None
    tags: list[str] = []


class TigerLinkParseError(Exception):
    """The feed could not be parsed as iCalendar."""


class TigerLinkUnavailable(Exception):
    """TigerLink could not be reached and there is no earlier data to serve."""


def _unfold(text: str) -> list[str]:
    """Splits iCalendar content into logical lines, undoing RFC 5545 folding."""
    lines: list[str] = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]  # continuation of the previous line
        else:
            lines.append(raw)
    return lines


def _unescape(value: str) -> str:
    out = []
    i = 0
    while i < len(value):
        char = value[i]
        if char == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out.append({"n": "\n", "N": "\n"}.get(nxt, nxt))
            i += 2
        else:
            out.append(char)
            i += 1
    return "".join(out)


@dataclass
class _Property:
    name: str
    params: dict[str, str]
    value: str


def _split_unquoted(text: str, separator: str) -> list[str]:
    """Splits on a separator, ignoring it inside double quotes.

    RFC 5545 lets quoted parameter values contain ":" and ";", as in
    ORGANIZER;CN="LSU: Robotics":mailto:...
    """
    parts: list[str] = []
    start = 0
    quoted = False
    for i, char in enumerate(text):
        if char == '"':
            quoted = not quoted
        elif char == separator and not quoted:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return parts


def _value_marker(line: str) -> int:
    """The index of the ":" that starts the value, or -1 if there is none."""
    quoted = False
    for i, char in enumerate(line):
        if char == '"':
            quoted = not quoted
        elif char == ":" and not quoted:
            return i
    return -1


def _parse_line(line: str) -> _Property | None:
    marker = _value_marker(line)
    if marker == -1:
        return None
    name_and_params, value = line[:marker], line[marker + 1 :]
    name, *param_parts = _split_unquoted(name_and_params, ";")
    params = {}
    for part in param_parts:
        key, _, val = part.partition("=")
        params[key.upper()] = val.strip('"')

    if params.get("ENCODING", "").upper() == "QUOTED-PRINTABLE":
        value = quopri.decodestring(value.encode("ascii", "replace")).decode(
            "utf-8", "replace"
        )
    else:
        value = _unescape(value)
    return _Property(name.upper(), params, value)


def _parse_datetime(prop: _Property) -> tuple[datetime, bool]:
    """Returns (timezone-aware datetime, all_day)."""
    value = prop.value.strip()
    if prop.params.get("VALUE", "").upper() == "DATE" or len(value) == 8:
        return datetime.strptime(value[:8], "%Y%m%d").replace(tzinfo=timezone.utc), True
    naive = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    # A trailing Z means UTC; the TigerLink feed always uses it.
    return naive.replace(tzinfo=timezone.utc), False


def _clean_location(value: str) -> str | None:
    location = value.strip()
    if not location or location.lower() == _HIDDEN_LOCATION:
        return None
    return location


def _stable_id(url: str | None, uid: str | None, title: str) -> str:
    if url and (match := _EVENT_ID.search(url)):
        return match.group(1)
    seed = uid or f"{url or ''}{title}"
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:16]


def _build_event(props: list[_Property]) -> ClubEvent | None:
    fields: dict[str, object] = {"tags": []}
    start = end = None
    all_day = False
    uid = None

    for prop in props:
        if prop.name == "SUMMARY":
            fields["title"] = prop.value.strip()
        elif prop.name == "DESCRIPTION":
            fields["description"] = prop.value.strip() or None
        elif prop.name == "LOCATION":
            fields["location"] = _clean_location(prop.value)
        elif prop.name == "URL":
            fields["url"] = prop.value.strip() or None
        elif prop.name == "UID":
            uid = prop.value.strip()
        elif prop.name == "ORGANIZER":
            fields["club"] = prop.params.get("CN", "").strip() or None
        elif prop.name == "DTSTART":
            start, all_day = _parse_datetime(prop)
        elif prop.name == "DTEND":
            end, _ = _parse_datetime(prop)
        elif prop.name == "CATEGORIES":
            kind = prop.params.get("X-CG-CATEGORY", "")
            if kind == "club_acronym":
                fields["club_acronym"] = prop.value.strip() or None
            elif kind == "event_type":
                fields["event_type"] = prop.value.strip() or None
            elif kind == "event_tags" and prop.value.strip():
                fields["tags"].append(prop.value.strip())  # type: ignore[attr-defined]

    title = fields.get("title")
    if not title or start is None:
        return None  # not a usable event

    venue = venue_of(fields.get("location"))  # type: ignore[arg-type]
    fields["venue"] = venue
    if place := locate(venue):
        fields["place"] = place.name
        fields["latitude"] = place.latitude
        fields["longitude"] = place.longitude
    return ClubEvent(
        id=_stable_id(fields.get("url"), uid, str(title)),  # type: ignore[arg-type]
        start=start,
        end=end,
        all_day=all_day,
        **fields,  # type: ignore[arg-type]
    )


def parse_feed(ics_text: str) -> list[ClubEvent]:
    """Parses an iCalendar feed into club events, skipping unusable entries.

    Raises TigerLinkParseError if the text isn't an iCalendar document.
    """
    lines = _unfold(ics_text)
    if not any(line.startswith("BEGIN:VCALENDAR") for line in lines):
        raise TigerLinkParseError("Response is not an iCalendar feed")

    events: list[ClubEvent] = []
    current: list[_Property] | None = None
    for line in lines:
        if line.startswith("BEGIN:VEVENT"):
            current = []
        elif line.startswith("END:VEVENT"):
            if current is not None:
                try:
                    event = _build_event(current)
                except (ValueError, KeyError) as error:
                    logger.warning("Skipping malformed TigerLink event: %s", error)
                    event = None
                if event is not None:
                    events.append(event)
            current = None
        elif current is not None:
            if prop := _parse_line(line):
                current.append(prop)

    events.sort(key=lambda e: (e.start, e.title))
    return events


@dataclass(frozen=True)
class ClubEventSnapshot:
    events: list[ClubEvent]
    fetched_at: datetime
    # True when the last refresh failed, so the data may be out of date.
    stale: bool


class TigerLinkService:
    """Serves club events from memory, refreshing from TigerLink hourly."""

    def __init__(
        self,
        transport: httpx.AsyncBaseTransport | None = None,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self._transport = transport
        self._now = now
        self._lock = asyncio.Lock()
        self._snapshot: ClubEventSnapshot | None = None
        self._next_refresh: datetime | None = None

    async def get_snapshot(self) -> ClubEventSnapshot:
        async with self._lock:
            if self._snapshot is None or self._now() >= self._next_refresh:
                await self._refresh()
            if self._snapshot is None:
                raise TigerLinkUnavailable("Could not load TigerLink events")
            return self._snapshot

    async def _refresh(self) -> None:
        failed = False
        try:
            async with httpx.AsyncClient(
                transport=self._transport,
                headers={"User-Agent": USER_AGENT},
                follow_redirects=True,
                timeout=30,
            ) as client:
                response = await client.get(FEED_URL)
                response.raise_for_status()
            events = parse_feed(response.text)
            self._snapshot = ClubEventSnapshot(events, self._now(), stale=False)
        except (httpx.HTTPError, TigerLinkParseError) as error:
            logger.error("Could not refresh TigerLink feed: %s", error)
            failed = True
            if self._snapshot is not None:
                self._snapshot = ClubEventSnapshot(
                    self._snapshot.events, self._snapshot.fetched_at, stale=True
                )

        self._next_refresh = self._now() + (RETRY_INTERVAL if failed else REFRESH_INTERVAL)
