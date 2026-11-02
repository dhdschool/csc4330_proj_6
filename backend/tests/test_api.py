from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from lsu_calendar import (
    CalendarSnapshot,
    CalendarUnavailable,
    merge_events,
    parse_calendar_page,
)
from main import app, get_calendar_service

FIXTURE = Path(__file__).parent / "fixtures" / "2027-2028-academic-calendar.html"
URL = "/api/lsu/calendar/events"


class FakeService:
    def __init__(self, error=None):
        self.error = error
        events, unscheduled = merge_events(
            parse_calendar_page(FIXTURE.read_text(encoding="utf8"), "2027-2028")
        )
        self.snapshot = CalendarSnapshot(
            events, unscheduled, datetime(2026, 11, 1, tzinfo=timezone.utc), False
        )

    async def get_snapshot(self):
        if self.error:
            raise self.error
        return self.snapshot


@pytest.fixture
def client():
    app.dependency_overrides[get_calendar_service] = lambda: FakeService()
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_returns_events_and_unscheduled(client):
    body = client.get(URL).json()
    assert len(body["events"]) > 50
    assert len(body["unscheduled"]) == 2
    assert body["stale"] is False
    assert body["events"] == sorted(body["events"], key=lambda e: e["start_date"])


def test_filters_by_category(client):
    body = client.get(URL, params={"category": ["holiday", "commencement"]}).json()
    assert {e["category"] for e in body["events"]} == {"holiday", "commencement"}
    assert body["unscheduled"] == []


def test_date_filter_includes_events_that_overlap(client):
    # Spring Break runs March 20-24, 2028, so a window touching its last day counts.
    body = client.get(URL, params={"start": "2028-03-24", "end": "2028-03-24"}).json()
    assert [e["title"] for e in body["events"]] == ["Spring Break"]


def test_filters_by_term_ignoring_case(client):
    body = client.get(URL, params={"term": "second summer 2028"}).json()
    assert body["events"]
    assert all("Second Summer 2028" in e["terms"] for e in body["events"])


def test_rejects_invalid_filters(client):
    assert client.get(URL, params={"start": "soon"}).status_code == 422
    assert client.get(URL, params={"category": "parties"}).status_code == 422


def test_unavailable_returns_503(client):
    app.dependency_overrides[get_calendar_service] = lambda: FakeService(
        CalendarUnavailable("LSU is down")
    )
    response = client.get(URL)
    assert response.status_code == 503
    assert response.json()["detail"] == "LSU is down"
