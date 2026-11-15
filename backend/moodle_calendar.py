"""Turns a user's Moodle calendar export (iCalendar) into structured events.

Moodle's "Export calendar" page hands out a URL with a per-user auth token,
which serves an .ics file without needing a browser session. We fetch that
URL with the logged-in session once, then reuse it until the session changes.
"""

import hashlib
import logging
import threading
import time
from datetime import datetime, timezone

import requests
from pydantic import BaseModel

import moodle
from tigerlink import _parse_datetime, _parse_line, _unfold

logger = logging.getLogger(__name__)

# Moodle is slow, and deadlines don't change minute to minute.
CACHE_SECONDS = 10 * 60


class MoodleEvent(BaseModel):
    id: str
    title: str
    description: str | None = None
    # Timezone-aware; Moodle exports times in UTC.
    start: datetime
    end: datetime | None = None
    all_day: bool = False
    # Moodle puts the course name in CATEGORIES, e.g. "CSC4330_Fall2026".
    course: str | None = None
    location: str | None = None


class MoodleNotAuthorized(Exception):
    """The Moodle session is missing or expired; the user must log in again."""


class MoodleUnavailable(Exception):
    """Moodle could not be reached or returned something unexpected."""


def parse_moodle_ics(text: str) -> list[MoodleEvent]:
    """Parses a Moodle .ics export. Events without a start or title are skipped."""
    events: list[MoodleEvent] = []
    props = None
    for line in _unfold(text):
        if line == "BEGIN:VEVENT":
            props = []
        elif line == "END:VEVENT":
            if props is not None and (event := _build_event(props)):
                events.append(event)
            props = None
        elif props is not None and (prop := _parse_line(line)):
            props.append(prop)
    events.sort(key=lambda e: e.start)
    return events


def _build_event(props) -> MoodleEvent | None:
    fields: dict[str, object] = {}
    uid = None
    for prop in props:
        if prop.name == "SUMMARY":
            fields["title"] = prop.value.strip()
        elif prop.name == "DESCRIPTION":
            fields["description"] = prop.value.strip() or None
        elif prop.name == "LOCATION":
            fields["location"] = prop.value.strip() or None
        elif prop.name == "CATEGORIES":
            fields["course"] = prop.value.strip() or None
        elif prop.name == "UID":
            uid = prop.value.strip()
        elif prop.name == "DTSTART":
            fields["start"], fields["all_day"] = _parse_datetime(prop)
        elif prop.name == "DTEND":
            fields["end"], _ = _parse_datetime(prop)

    if not fields.get("title") or "start" not in fields:
        return None
    seed = uid or f"{fields['title']}{fields['start']}"
    fields["id"] = hashlib.sha1(seed.encode("utf-8")).hexdigest()[:16]
    return MoodleEvent(**fields)


class MoodleCalendarService:
    """Fetches and caches the logged-in user's Moodle events."""

    def __init__(self):
        self._lock = threading.Lock()
        self._export_url: str | None = None
        self._url_token: str | None = None  # session the URL was made with
        self._events: list[MoodleEvent] | None = None
        self._fetched_at: datetime | None = None
        self._fetched_monotonic = 0.0

    def get_events(self) -> tuple[list[MoodleEvent], datetime]:
        with self._lock:
            fresh = time.monotonic() - self._fetched_monotonic < CACHE_SECONDS
            if (
                self._events is not None
                and fresh
                and self._url_token == moodle.moodle4_token
            ):
                return self._events, self._fetched_at

            url = self._get_export_url()
            try:
                resp = requests.get(url, timeout=30)
            except requests.RequestException as error:
                raise MoodleUnavailable(f"Couldn't download the Moodle calendar: {error}")
            if resp.status_code != 200 or "BEGIN:VCALENDAR" not in resp.text:
                # The auth token may have been reset; make a new URL next time.
                self._export_url = None
                raise MoodleUnavailable(
                    f"Moodle calendar export returned status {resp.status_code}"
                )

            self._events = parse_moodle_ics(resp.text)
            self._fetched_at = datetime.now(timezone.utc)
            self._fetched_monotonic = time.monotonic()
            return self._events, self._fetched_at

    def _get_export_url(self) -> str:
        token = moodle.moodle4_token
        if self._export_url and self._url_token == token:
            return self._export_url

        if not token or not moodle.LoginRequest().is_authorized():
            raise MoodleNotAuthorized("Log in to Moodle first.")

        try:
            page = moodle.AuthRequest("/calendar/export.php").get()
            sesskey = moodle.get_config(page.text)["sesskey"]
            url = moodle.GetScheduleUrl().get_calendar_url(sesskey)
        except (requests.RequestException, ValueError, KeyError, AttributeError) as error:
            logger.warning("Couldn't get the Moodle export URL: %s", error)
            raise MoodleUnavailable("Couldn't get the calendar export link from Moodle.")
        if not url:
            raise MoodleUnavailable("Moodle didn't return a calendar export link.")

        self._export_url = url
        self._url_token = token
        return url
