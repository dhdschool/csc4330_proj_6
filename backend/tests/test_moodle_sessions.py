import json
from datetime import date

import pytest

import moodle
import moodle_calendar
from moodle_calendar import MoodleCalendarService
from moodle_sessions import SessionStore


def test_sessions_get_unique_unguessable_ids():
    store = SessionStore(path=None)
    ids = {store.create("cookie") for _ in range(100)}
    assert len(ids) == 100
    assert all(len(session_id) >= 40 for session_id in ids)


def test_lookup_update_and_delete():
    store = SessionStore(path=None)
    session_id = store.create("alice-cookie")

    assert store.token_for(session_id) == "alice-cookie"
    assert store.token_for("other") is None
    assert store.token_for(None) is None

    store.update(session_id, "new-cookie")
    assert store.token_for(session_id) == "new-cookie"

    store.delete(session_id)
    assert store.token_for(session_id) is None
    store.delete(session_id)  # deleting twice is fine
    store.delete(None)


def test_sessions_survive_a_restart(tmp_path):
    path = tmp_path / "sessions.json"
    session_id = SessionStore(path).create("alice-cookie")

    assert SessionStore(path).token_for(session_id) == "alice-cookie"
    assert json.loads(path.read_text()) == {session_id: "alice-cookie"}


@pytest.mark.parametrize("content", ["", "not json", "[1, 2]", '{"id": 5}'])
def test_a_damaged_file_does_not_stop_startup(tmp_path, content):
    path = tmp_path / "sessions.json"
    path.write_text(content)
    store = SessionStore(path)
    assert store.token_for("id") is None
    # And it can still save new sessions.
    session_id = store.create("cookie")
    assert SessionStore(path).token_for(session_id) == "cookie"


class _Response:
    def __init__(self, text, status_code=200):
        self.text, self.status_code = text, status_code


def _ics(title):
    return (
        "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:1\r\n"
        f"SUMMARY:{title}\r\nDTSTART:20261120T120000Z\r\n"
        "END:VEVENT\r\nEND:VCALENDAR\r\n"
    )


def test_calendar_cache_is_kept_per_user(monkeypatch):
    service = MoodleCalendarService()
    downloads = []
    monkeypatch.setattr(service, "_get_export_url", lambda token, cache: f"https://x/{token}")

    def fake_get(url, timeout):
        downloads.append(url)
        return _Response(_ics(f"for {url.rsplit('/', 1)[1]}"))

    monkeypatch.setattr(moodle_calendar.requests, "get", fake_get)

    alice, _ = service.get_events("alice")
    bob, _ = service.get_events("bob")
    again, _ = service.get_events("alice")  # cached

    assert alice[0].title == "for alice"
    assert bob[0].title == "for bob"
    assert again[0].title == "for alice"
    assert downloads == ["https://x/alice", "https://x/bob"]

    service.forget("alice")
    service.get_events("alice")
    assert downloads[-1] == "https://x/alice"


def test_every_moodle_request_has_a_timeout(monkeypatch):
    seen = {}

    def fake(method):
        def call(url, **kwargs):
            seen[method] = kwargs.get("timeout")
            return _Response("")

        return call

    monkeypatch.setattr(moodle.requests, "get", fake("get"))
    monkeypatch.setattr(moodle.requests, "post", fake("post"))

    moodle.BaseRequest("/x").get()
    moodle.BaseRequest("/x").post()
    moodle.BaseRequest("/x", use_post_form=True).post()

    assert seen == {"get": moodle.TIMEOUT_SECONDS, "post": moodle.TIMEOUT_SECONDS}


def test_no_moodle_session_means_not_authorized():
    # Doesn't contact Moodle at all.
    assert moodle.is_authorized("") is False
    assert moodle.is_authorized(None) is False


@pytest.mark.parametrize(
    ("today", "expected"),
    [
        (date(2026, 1, 12), ("SPRING", 2026)),
        (date(2026, 5, 31), ("SPRING", 2026)),
        (date(2026, 8, 24), ("FALL", 2026)),
        (date(2026, 12, 15), ("FALL", 2026)),
    ],
)
def test_current_semester(today, expected):
    assert moodle.current_semester(today) == expected
