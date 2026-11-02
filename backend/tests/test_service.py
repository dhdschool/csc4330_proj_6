import asyncio
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest

from lsu_calendar import CalendarUnavailable, LsuCalendarService

FIXTURES = Path(__file__).parent / "fixtures"
INDEX = (
    '<a href="/registrar/2020-2021/2020-2021-academic-calendar.php">old</a>'
    '<a href="/registrar/2026-2027/2026-2027-academic-calendar.php">a</a>'
    '<a href="/registrar/2027-2028/2027-2028-academic-calendar.php">b</a>'
)


class FakeLsu:
    def __init__(self):
        self.requests = []
        self.failing = set()  # URL fragments that respond with a 500
        self.now = datetime(2026, 11, 1, tzinfo=timezone.utc)

    def handle(self, request):
        path = request.url.path
        self.requests.append(path)
        if any(fragment in path for fragment in self.failing):
            return httpx.Response(500)
        if path.endswith("index.php"):
            return httpx.Response(200, text=INDEX)
        name = path.rsplit("/", 1)[-1].replace(".php", ".html")
        return httpx.Response(200, text=(FIXTURES / name).read_text(encoding="utf8"))

    def service(self):
        return LsuCalendarService(httpx.MockTransport(self.handle), now=lambda: self.now)


@pytest.fixture
def lsu():
    return FakeLsu()


def get(service):
    return asyncio.run(service.get_snapshot())


def events_in(snapshot, term):
    return [e for e in snapshot.events if term in e.terms]


def test_loads_current_and_future_years_only(lsu):
    snapshot = get(lsu.service())
    assert snapshot.stale is False
    assert events_in(snapshot, "Fall Semester 2026") and events_in(snapshot, "Fall Semester 2027")
    assert not [path for path in lsu.requests if "2020-2021" in path]


def test_uses_cache_until_it_expires(lsu):
    service = lsu.service()
    get(service)
    count = len(lsu.requests)

    get(service)
    assert len(lsu.requests) == count

    lsu.now += timedelta(hours=25)
    get(service)
    assert len(lsu.requests) == 2 * count


def test_serves_old_data_when_lsu_is_down(lsu):
    service = lsu.service()
    first = get(service)

    lsu.failing = {"/registrar"}
    lsu.now += timedelta(hours=25)
    snapshot = get(service)
    assert snapshot.stale is True
    assert snapshot.events == first.events

    # A failed refresh waits before trying again instead of slowing every request.
    count = len(lsu.requests)
    get(service)
    assert len(lsu.requests) == count


def test_one_bad_page_keeps_that_years_old_data(lsu):
    service = lsu.service()
    get(service)

    lsu.failing = {"2027-2028"}
    lsu.now += timedelta(hours=25)
    snapshot = get(service)
    assert snapshot.stale is True
    assert events_in(snapshot, "Fall Semester 2026") and events_in(snapshot, "Fall Semester 2027")


def test_recovers_after_an_outage(lsu):
    service = lsu.service()
    get(service)
    lsu.failing = {"/registrar"}
    lsu.now += timedelta(hours=25)
    get(service)

    lsu.failing = set()
    lsu.now += timedelta(minutes=16)
    assert get(service).stale is False


def test_no_data_at_all_is_unavailable(lsu):
    lsu.failing = {"/registrar"}
    service = lsu.service()
    with pytest.raises(CalendarUnavailable):
        get(service)

    # With nothing to serve, the next request tries again right away.
    lsu.failing = set()
    assert get(service).events
