import asyncio
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest

from tigerlink import TigerLinkService, TigerLinkUnavailable

FIXTURE = Path(__file__).parent / "fixtures" / "tigerlink_sample.ics"


class FakeTigerLink:
    def __init__(self):
        self.requests = 0
        self.status = 200
        self.body = FIXTURE.read_text(encoding="utf8")
        self.now = datetime(2026, 11, 6, tzinfo=timezone.utc)

    def handle(self, request):
        self.requests += 1
        return httpx.Response(self.status, text=self.body)

    def service(self):
        return TigerLinkService(httpx.MockTransport(self.handle), now=lambda: self.now)


@pytest.fixture
def feed():
    return FakeTigerLink()


def get(service):
    return asyncio.run(service.get_snapshot())


def test_loads_and_caches(feed):
    service = feed.service()
    snapshot = get(service)
    assert snapshot.stale is False
    assert len(snapshot.events) == 6

    get(service)
    assert feed.requests == 1  # served from cache

    feed.now += timedelta(hours=2)
    get(service)
    assert feed.requests == 2  # refreshed after the TTL


def test_serves_old_data_when_the_feed_fails(feed):
    service = feed.service()
    first = get(service)

    feed.status = 500
    feed.now += timedelta(hours=2)
    snapshot = get(service)
    assert snapshot.stale is True
    assert snapshot.events == first.events


def test_retries_sooner_after_a_failure(feed):
    service = feed.service()
    get(service)
    feed.status = 500
    feed.now += timedelta(hours=2)
    get(service)

    # A failure schedules a retry in 15 minutes, not a full hour later.
    feed.status = 200
    feed.now += timedelta(minutes=16)
    assert get(service).stale is False


def test_unavailable_when_there_is_nothing_to_serve(feed):
    feed.status = 500
    with pytest.raises(TigerLinkUnavailable):
        get(feed.service())
