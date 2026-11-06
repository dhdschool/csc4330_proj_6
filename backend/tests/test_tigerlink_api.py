from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from main import app, get_tigerlink_service
from tigerlink import ClubEventSnapshot, TigerLinkUnavailable, parse_feed

FIXTURE = Path(__file__).parent / "fixtures" / "tigerlink_sample.ics"
URL = "/api/tigerlink/events"


class FakeService:
    def __init__(self, error=None):
        self.error = error
        events = parse_feed(FIXTURE.read_text(encoding="utf8"))
        self.snapshot = ClubEventSnapshot(
            events, datetime(2026, 11, 6, tzinfo=timezone.utc), stale=False
        )

    async def get_snapshot(self):
        if self.error:
            raise self.error
        return self.snapshot


@pytest.fixture
def client():
    app.dependency_overrides[get_tigerlink_service] = lambda: FakeService()
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_returns_all_events(client):
    body = client.get(URL).json()
    assert len(body["events"]) == 6
    assert body["stale"] is False
    assert "tigerlink.lsu.edu" in body["source"]


def test_filters_by_club_acronym_or_name(client):
    assert all(
        e["club_acronym"] == "VLSU" for e in client.get(URL, params={"club": "vlsu"}).json()["events"]
    )
    assert client.get(URL, params={"club": "Volunteer LSU"}).json()["events"]


def test_filters_by_event_type(client):
    body = client.get(URL, params={"event_type": "service"}).json()
    assert body["events"]
    assert {e["event_type"] for e in body["events"]} == {"Service"}


def test_search_matches_the_title(client):
    body = client.get(URL, params={"search": "service project"}).json()
    assert [e["title"] for e in body["events"]] == ["RA Service Project"]


def test_date_window_filters_events(client):
    # The sample runs Aug 8-11, 2026; a window before it should be empty.
    assert client.get(URL, params={"end": "2026-08-07"}).json()["events"] == []
    assert client.get(URL, params={"start": "2026-08-10"}).json()["events"]


def test_limit_caps_the_result(client):
    body = client.get(URL, params={"limit": 2}).json()
    assert len(body["events"]) == 2


def test_invalid_limit_is_rejected(client):
    assert client.get(URL, params={"limit": 0}).status_code == 422


def test_unavailable_returns_503(client):
    app.dependency_overrides[get_tigerlink_service] = lambda: FakeService(
        TigerLinkUnavailable("TigerLink is down")
    )
    response = client.get(URL)
    assert response.status_code == 503
    assert response.json()["detail"] == "TigerLink is down"
