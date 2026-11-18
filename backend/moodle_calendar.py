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


class _UserCache:
    """One user's export link and most recent events."""

    def __init__(self) -> None:
        # Per user, so one person's slow Moodle doesn't hold up everyone else.
        self.lock = threading.Lock()
        self.export_url: str | None = None
        self.events: list[MoodleEvent] | None = None
        self.fetched_at: datetime | None = None
        self.fetched_monotonic = 0.0


class MoodleCalendarService:
    """Fetches and caches each user's Moodle events, keyed by their session."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._caches: dict[str, _UserCache] = {}

    def get_events(self, token: str) -> tuple[list[MoodleEvent], datetime]:
        """The events for the user signed in with this Moodle session token."""
        if not token:
            raise MoodleNotAuthorized("Log in to Moodle first.")
        with self._lock:
            cache = self._caches.setdefault(token, _UserCache())

        with cache.lock:
            fresh = time.monotonic() - cache.fetched_monotonic < CACHE_SECONDS
            if cache.events is not None and fresh:
                return cache.events, cache.fetched_at

            url = self._get_export_url(token, cache)
            try:
                resp = requests.get(url, timeout=30)
            except requests.RequestException as error:
                raise MoodleUnavailable(f"Couldn't download the Moodle calendar: {error}")
            if resp.status_code != 200 or "BEGIN:VCALENDAR" not in resp.text:
                # The auth token may have been reset; make a new URL next time.
                cache.export_url = None
                raise MoodleUnavailable(
                    f"Moodle calendar export returned status {resp.status_code}"
                )

            cache.events = parse_moodle_ics(resp.text)
            cache.fetched_at = datetime.now(timezone.utc)
            cache.fetched_monotonic = time.monotonic()
            return cache.events, cache.fetched_at

    def forget(self, token: str | None) -> None:
        """Drops a user's cached events, e.g. when they sign out."""
        if token:
            with self._lock:
                self._caches.pop(token, None)

    def _get_export_url(self, token: str, cache: _UserCache) -> str:
        if cache.export_url:
            return cache.export_url

        try:
            if not moodle.is_authorized(token):
                raise MoodleNotAuthorized("Log in to Moodle first.")
            page = moodle.AuthRequest("/calendar/export.php", token).get()
            sesskey = moodle.get_config(page.text)["sesskey"]
            url = moodle.GetScheduleUrl(token).get_calendar_url(sesskey)
        except (requests.RequestException, ValueError, KeyError) as error:
            logger.warning("Couldn't get the Moodle export URL: %s", error)
            raise MoodleUnavailable("Couldn't get the calendar export link from Moodle.")

        cache.export_url = url
        return url
