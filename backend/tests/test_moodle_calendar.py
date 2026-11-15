from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from main import app, get_moodle_calendar_service
from moodle_calendar import MoodleNotAuthorized, MoodleUnavailable, parse_moodle_ics

SAMPLE = (
    "BEGIN:VCALENDAR\r\n"
    "VERSION:2.0\r\n"
    "PRODID:-//Moodle Pty Ltd//NONSGML Moodle Version 2024100700//EN\r\n"
    "BEGIN:VEVENT\r\n"
    "UID:2002@moodle.lsu.edu\r\n"
    "SUMMARY:Assignment 4 is due\r\n"
    "DESCRIPTION:Submit the PDF\\, then the code.\\nLate work loses 10%.\r\n"
    "CLASS:PUBLIC\r\n"
    "DTSTART:20261121T055900Z\r\n"
    "DTEND:20261121T055900Z\r\n"
    "CATEGORIES:2026 Fall CSC 4501\r\n"
    "END:VEVENT\r\n"
    "BEGIN:VEVENT\r\n"
    "UID:2001@moodle.lsu.edu\r\n"
    "SUMMARY:Attendance (Group CSC 3730 001-LEC-FA\r\n"
    " )\r\n"
    "DTSTART:20261117T150000Z\r\n"
    "DTEND:20261117T162000Z\r\n"
    "CATEGORIES:2026 Fall CSC 3730\r\n"
    "END:VEVENT\r\n"
    "BEGIN:VEVENT\r\n"
    "UID:2003@moodle.lsu.edu\r\n"
    "SUMMARY:Reading day\r\n"
    "DTSTART;VALUE=DATE:20261203\r\n"
    "END:VEVENT\r\n"
    "BEGIN:VEVENT\r\n"
    "UID:2004@moodle.lsu.edu\r\n"
    "DTSTART:20261201T000000Z\r\n"
    "END:VEVENT\r\n"
    "END:VCALENDAR\r\n"
)


def test_parses_and_sorts_events():
    events = parse_moodle_ics(SAMPLE)

    # The untitled event is dropped; the rest are sorted by start.
    assert [e.title for e in events] == [
        "Attendance (Group CSC 3730 001-LEC-FA)",
        "Assignment 4 is due",
        "Reading day",
    ]
    attendance, assignment, reading = events
    assert attendance.start == datetime(2026, 11, 17, 15, 0, tzinfo=timezone.utc)
    assert attendance.end == datetime(2026, 11, 17, 16, 20, tzinfo=timezone.utc)
    assert attendance.course == "2026 Fall CSC 3730"
    assert assignment.description == "Submit the PDF, then the code.\nLate work loses 10%."
    assert not assignment.all_day
    assert reading.all_day and reading.end is None


def test_ids_are_stable():
    first = parse_moodle_ics(SAMPLE)
    second = parse_moodle_ics(SAMPLE)
    assert [e.id for e in first] == [e.id for e in second]
    assert len({e.id for e in first}) == len(first)


class FakeService:
    def __init__(self, error=None):
        self.error = error

    def get_events(self):
        if self.error:
            raise self.error
        return parse_moodle_ics(SAMPLE), datetime(2026, 11, 15, tzinfo=timezone.utc)


@pytest.fixture
def client_with():
    def make(service):
        app.dependency_overrides[get_moodle_calendar_service] = lambda: service
        return TestClient(app)

    yield make
    app.dependency_overrides.clear()


def test_endpoint_returns_events(client_with):
    response = client_with(FakeService()).get("/api/moodle/events")
    assert response.status_code == 200
    body = response.json()
    assert len(body["events"]) == 3
    assert body["events"][1]["start"] == "2026-11-21T05:59:00Z"
    assert body["events"][1]["course"] == "2026 Fall CSC 4501"


@pytest.mark.parametrize(
    ("error", "status"),
    [(MoodleNotAuthorized("log in"), 401), (MoodleUnavailable("down"), 503)],
)
def test_endpoint_errors(client_with, error, status):
    response = client_with(FakeService(error)).get("/api/moodle/events")
    assert response.status_code == status
