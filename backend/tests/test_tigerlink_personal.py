"""Personal TigerLink calendar links: only trusted hosts, never elsewhere."""

import asyncio
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from main import app, get_personal_feed_fetcher
from tigerlink import (
    TigerLinkParseError,
    UntrustedFeedUrl,
    fetch_personal_feed,
    is_trusted_feed_url,
    parse_feed,
)

FEED = (Path(__file__).parent / "fixtures" / "tigerlink_sample.ics").read_text(encoding="utf8")
LINK = "https://tigerlink.lsu.edu/ical/lsu/personal_abc123.ics"


@pytest.mark.parametrize(
    "url",
    [
        LINK,
        "https://static-prod-us-east-1.campusgroups.com/ical/lsu/x.ics",
        "https://TigerLink.LSU.edu/ical/x.ics",
    ],
)
def test_trusted_links(url):
    assert is_trusted_feed_url(url)


@pytest.mark.parametrize(
    "url",
    [
        "http://tigerlink.lsu.edu/ical/x.ics",  # not https
        "https://evil.example/tigerlink.lsu.edu",
        "https://tigerlink.lsu.edu.evil.example/x.ics",
        "https://notcampusgroups.com/x.ics",
        "https://user:pass@tigerlink.lsu.edu/x.ics",
        "https://tigerlink.lsu.edu:8443/x.ics",
        "https://localhost/x.ics",
        "https://169.254.169.254/latest/meta-data",
        "file:///etc/passwd",
        "",
        "not a url",
    ],
)
def test_untrusted_links(url):
    assert not is_trusted_feed_url(url)


def fetch(url, handler):
    return asyncio.run(fetch_personal_feed(url, transport=httpx.MockTransport(handler)))


def test_fetches_and_parses_a_personal_feed():
    seen = []

    def handler(request):
        seen.append(str(request.url))
        return httpx.Response(200, text=FEED)

    events = fetch(LINK, handler)
    assert len(events) == 6
    assert seen == [LINK]


def test_follows_redirects_to_campusgroups():
    target = "https://static-prod-us-east-1.campusgroups.com/ical/lsu/p.ics"

    def handler(request):
        if request.url.host == "tigerlink.lsu.edu":
            return httpx.Response(302, headers={"location": target})
        return httpx.Response(200, text=FEED)

    assert len(fetch(LINK, handler)) == 6


def test_refuses_to_follow_a_redirect_elsewhere():
    requested = []

    def handler(request):
        requested.append(request.url.host)
        return httpx.Response(302, headers={"location": "http://169.254.169.254/"})

    with pytest.raises(UntrustedFeedUrl):
        fetch(LINK, handler)
    assert requested == ["tigerlink.lsu.edu"]  # never contacted the other host


def test_refuses_an_untrusted_link_without_fetching():
    def handler(request):
        raise AssertionError("should not fetch")

    with pytest.raises(UntrustedFeedUrl):
        fetch("https://evil.example/feed.ics", handler)


def test_a_non_calendar_response_is_a_parse_error():
    with pytest.raises(TigerLinkParseError):
        fetch(LINK, lambda request: httpx.Response(200, text="<html>Sign in</html>"))


def test_redirect_loops_stop():
    with pytest.raises(TigerLinkParseError):
        fetch(LINK, lambda request: httpx.Response(302, headers={"location": LINK}))


@pytest.fixture
def client_with():
    def make(fake):
        app.dependency_overrides[get_personal_feed_fetcher] = lambda: fake
        return TestClient(app)

    yield make
    app.dependency_overrides.clear()


def test_endpoint_returns_events(client_with):
    async def fake(url):
        return parse_feed(FEED)

    response = client_with(fake).post("/api/tigerlink/personal", json={"feed_url": LINK})
    assert response.status_code == 200
    assert len(response.json()["events"]) == 6


@pytest.mark.parametrize(
    ("error", "status"),
    [
        (UntrustedFeedUrl("x"), 400),
        (TigerLinkParseError("x"), 422),
        (httpx.ConnectError("x"), 502),
    ],
)
def test_endpoint_errors(client_with, error, status):
    async def fake(url):
        raise error

    response = client_with(fake).post("/api/tigerlink/personal", json={"feed_url": LINK})
    assert response.status_code == status
    # The secret link is never echoed back.
    assert "personal_abc123" not in response.text
