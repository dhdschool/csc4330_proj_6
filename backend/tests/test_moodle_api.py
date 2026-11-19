"""The Moodle login routes keep each user's session separate."""

import threading
from datetime import datetime, timezone

import pytest
import requests
from fastapi.testclient import TestClient

import main
from main import app, get_moodle_auth, get_moodle_calendar_service, get_session_store
from moodle_calendar import MoodleEvent, MoodleNotAuthorized
from moodle_sessions import SessionStore

FETCHED = datetime(2026, 11, 15, tzinfo=timezone.utc)


class FakeAuth:
    """Moodle, where the tokens in `valid` are signed in."""

    def __init__(self, valid=("alice-cookie", "bob-cookie"), error=None):
        self.valid = set(valid)
        self.error = error
        self.browser_logins = 0

    def start_login(self):
        if self.error:
            raise self.error
        return "https://login.lsu.edu/start", "anonymous-cookie"

    def is_authorized(self, token):
        if self.error:
            raise self.error
        return token in self.valid

    def login_in_browser(self, login_url, token):
        self.browser_logins += 1
        return "alice-cookie"


class FakeCalendar:
    """Each Moodle token sees only its own events."""

    def __init__(self):
        self.forgotten = []
        self.expired = set()

    def get_events(self, token):
        if token in self.expired:
            raise MoodleNotAuthorized("Log in to Moodle first.")
        owner = token.removesuffix("-cookie")
        event = MoodleEvent(id=owner, title=f"{owner}'s assignment", start=FETCHED)
        return [event], FETCHED

    def forget(self, token):
        self.forgotten.append(token)


@pytest.fixture
def backend():
    auth, calendar, sessions = FakeAuth(), FakeCalendar(), SessionStore(path=None)
    app.dependency_overrides[get_moodle_auth] = lambda: auth
    app.dependency_overrides[get_moodle_calendar_service] = lambda: calendar
    app.dependency_overrides[get_session_store] = lambda: sessions
    yield auth, calendar, sessions
    app.dependency_overrides.clear()


def sign_in(token):
    """A new app install signing in with a Moodle cookie; returns its client."""
    client = TestClient(app)
    response = client.post("/api/moodle/login", json={"token": token})
    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    client.headers["Authorization"] = f"Bearer {body['session']}"
    return client


def test_each_user_sees_only_their_own_events(backend):
    alice, bob = sign_in("alice-cookie"), sign_in("bob-cookie")

    assert alice.get("/api/moodle/events").json()["events"][0]["title"] == "alice's assignment"
    assert bob.get("/api/moodle/events").json()["events"][0]["title"] == "bob's assignment"
    assert alice.headers["Authorization"] != bob.headers["Authorization"]


def test_events_need_a_session(backend):
    sign_in("alice-cookie")  # someone else is signed in

    assert TestClient(app).get("/api/moodle/events").status_code == 401
    forged = TestClient(app, headers={"Authorization": "Bearer made-up"})
    assert forged.get("/api/moodle/events").status_code == 401


def test_an_invalid_moodle_cookie_gets_no_session(backend):
    response = TestClient(app).post("/api/moodle/login", json={"token": "expired-cookie"})
    assert response.json() == {"success": False, "session": None}


def test_authorized_reports_the_callers_own_session(backend):
    alice = sign_in("alice-cookie")
    assert alice.get("/api/moodle/authorized").json() == {
        "authorized": True,
        "login_url": None,
    }
    # A different app, not signed in, gets a login link instead.
    assert TestClient(app).get("/api/moodle/authorized").json() == {
        "authorized": False,
        "login_url": "https://login.lsu.edu/start",
    }


def test_logout_only_ends_the_callers_session(backend):
    _, calendar, _ = backend
    alice, bob = sign_in("alice-cookie"), sign_in("bob-cookie")

    assert alice.post("/api/moodle/logout").json()["success"] is True

    assert alice.get("/api/moodle/events").status_code == 401
    assert bob.get("/api/moodle/events").status_code == 200
    assert "alice-cookie" in calendar.forgotten


def test_signing_in_again_keeps_the_same_session(backend):
    _, calendar, _ = backend
    client = sign_in("alice-cookie")
    first = client.headers["Authorization"]

    body = client.post("/api/moodle/login", json={"token": "bob-cookie"}).json()

    assert f"Bearer {body['session']}" == first
    assert client.get("/api/moodle/events").json()["events"][0]["id"] == "bob"
    assert "alice-cookie" in calendar.forgotten


def test_an_expired_moodle_session_signs_the_app_out(backend):
    _, calendar, _ = backend
    client = sign_in("alice-cookie")
    calendar.expired.add("alice-cookie")

    assert client.get("/api/moodle/events").status_code == 401
    # The dead session is gone, so the app is sent back to sign in.
    calendar.expired.clear()
    assert client.get("/api/moodle/events").status_code == 401


@pytest.mark.parametrize(
    "error", [requests.ConnectionError("down"), requests.Timeout("slow"), ValueError("changed")]
)
def test_moodle_failures_are_503_not_500(backend, error):
    backend[0].error = error
    client = TestClient(app)
    assert client.get("/api/moodle/authorized").status_code == 503
    assert client.post("/api/moodle/login", json={"token": "x"}).status_code == 503


def test_browser_login_is_refused_from_other_computers(backend):
    auth = backend[0]
    # TestClient's requests come from "testclient", not a loopback address.
    response = TestClient(app).post("/api/moodle/login", json={"backend_login": True})
    assert response.status_code == 403
    assert auth.browser_logins == 0


def test_browser_login_works_locally(backend, monkeypatch):
    monkeypatch.setattr(main, "_LOOPBACK", {"testclient"})
    response = TestClient(app).post("/api/moodle/login", json={"backend_login": True})
    assert response.json()["success"] is True
    assert backend[0].browser_logins == 1


def test_browser_login_can_be_switched_off(backend, monkeypatch):
    monkeypatch.setattr(main, "_LOOPBACK", {"testclient"})
    monkeypatch.setenv("MOODLE_BROWSER_LOGIN", "0")
    response = TestClient(app).post("/api/moodle/login", json={"backend_login": True})
    assert response.status_code == 403


def test_only_one_browser_login_at_a_time(backend, monkeypatch):
    monkeypatch.setattr(main, "_LOOPBACK", {"testclient"})
    lock: threading.Lock = main._browser_login_lock
    assert lock.acquire(blocking=False)  # a login window is already open
    try:
        response = TestClient(app).post("/api/moodle/login", json={"backend_login": True})
        assert response.status_code == 409
    finally:
        lock.release()
