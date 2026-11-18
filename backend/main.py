import asyncio
import os
import threading
from datetime import date, datetime
from typing import Annotated

import requests
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from lsu_calendar import (
    CalendarEvent,
    CalendarUnavailable,
    Category,
    INDEX_URL,
    LsuCalendarService,
)
from tigerlink import (
    ClubEvent,
    SOURCE_URL as TIGERLINK_SOURCE_URL,
    TigerLinkService,
    TigerLinkUnavailable,
)

import moodle
from moodle_calendar import (
    MoodleCalendarService,
    MoodleEvent,
    MoodleNotAuthorized,
    MoodleUnavailable,
)
from moodle_sessions import SessionStore

app = FastAPI(title="LSU UniCalendar")
# Lets the Flutter web build call the API. POST + Content-Type are needed for the
# JSON body sent to /api/moodle/login, and Authorization carries the Moodle
# session ID (the browser preflights both with OPTIONS). Any origin is fine:
# Moodle data needs a session ID that only the signed-in app has.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Authorization"],
)

_service = LsuCalendarService()
_tigerlink = TigerLinkService()

_moodle_calendar = MoodleCalendarService()
_moodle_sessions = SessionStore()


class MoodleAuth:
    """The Moodle calls the login routes make. Tests swap in a fake."""

    def start_login(self) -> tuple[str, str]:
        return moodle.LoginRequest().start()

    def is_authorized(self, token: str) -> bool:
        return moodle.is_authorized(token)

    def login_in_browser(self, login_url: str, token: str) -> str:
        return asyncio.run(moodle.LoginRequest().auth_login(login_url, token))


_moodle_auth = MoodleAuth()


def get_calendar_service() -> LsuCalendarService:
    return _service


def get_moodle_calendar_service() -> MoodleCalendarService:
    return _moodle_calendar


def get_session_store() -> SessionStore:
    return _moodle_sessions


def get_moodle_auth() -> MoodleAuth:
    return _moodle_auth


def get_session_id(
    authorization: Annotated[str | None, Header()] = None,
) -> str | None:
    """The app's Moodle session ID, from `Authorization: Bearer <id>`."""
    scheme, _, value = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not value.strip():
        return None
    return value.strip()


SessionId = Annotated[str | None, Depends(get_session_id)]
Sessions = Annotated[SessionStore, Depends(get_session_store)]
Auth = Annotated[MoodleAuth, Depends(get_moodle_auth)]
MoodleCalendar = Annotated[MoodleCalendarService, Depends(get_moodle_calendar_service)]

# What a Moodle request can fail with: unreachable, or pages that changed.
_MOODLE_ERRORS = (requests.RequestException, ValueError, KeyError)
_MOODLE_DOWN = "Couldn't reach Moodle. Try again in a few minutes."


def get_tigerlink_service() -> TigerLinkService:
    return _tigerlink


class CalendarResponse(BaseModel):
    events: list[CalendarEvent]
    # Events LSU hasn't dated yet (usually "TBD"); start_date and end_date are null.
    unscheduled: list[CalendarEvent]
    source: str
    fetched_at: datetime
    # True when the last refresh from LSU failed, so data may be old or incomplete.
    stale: bool

class LoginResponse(BaseModel):
    success: bool
    # The ID the app sends back as `Authorization: Bearer <session>`.
    session: str | None = None


class MoodleLoginBody(BaseModel):
    # The Moodle session cookie from the app's login webview.
    token: str = ""
    # Web only: the backend opens its own browser window for the login.
    backend_login: bool = False


class IsAuthorizedResponse(BaseModel):
    authorized: bool
    login_url: str | None = None


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


# The Moodle routes are sync on purpose: the Moodle client uses requests, so
# FastAPI runs them in worker threads instead of blocking the event loop.
@app.get("/api/moodle/authorized")
def moodle_is_authorized(
    session_id: SessionId, sessions: Sessions, auth: Auth
) -> IsAuthorizedResponse:
    """Whether this app's session is signed in, else a fresh Moodle login link."""
    try:
        token = sessions.token_for(session_id)
        if token and auth.is_authorized(token):
            return IsAuthorizedResponse(authorized=True)
        login_url, _ = auth.start_login()
    except _MOODLE_ERRORS as error:
        raise HTTPException(status_code=503, detail=_MOODLE_DOWN) from error
    return IsAuthorizedResponse(authorized=False, login_url=login_url)


# Opening a browser on the server only makes sense when the "server" is the
# user's own computer, so it's limited to local requests, one at a time. Set
# MOODLE_BROWSER_LOGIN=0 on a deployed server, where a reverse proxy can make
# outside requests look local.
_LOOPBACK = {"127.0.0.1", "::1", "localhost"}
_browser_login_lock = threading.Lock()


def _login_in_server_browser(request: Request, auth: MoodleAuth) -> str:
    client = request.client.host if request.client else None
    if os.environ.get("MOODLE_BROWSER_LOGIN", "1") == "0" or client not in _LOOPBACK:
        raise HTTPException(
            status_code=403,
            detail="Signing in through the server is only available when the "
            "backend runs on your own computer.",
        )
    if not _browser_login_lock.acquire(blocking=False):
        raise HTTPException(
            status_code=409, detail="A Moodle sign-in window is already open."
        )
    try:
        login_url, token = auth.start_login()
        return auth.login_in_browser(login_url, token)
    finally:
        _browser_login_lock.release()


@app.post("/api/moodle/login")
def moodle_login(
    body: MoodleLoginBody,
    request: Request,
    session_id: SessionId,
    sessions: Sessions,
    auth: Auth,
    calendar: MoodleCalendar,
) -> LoginResponse:
    """Signs in with a Moodle session and returns this app's session ID."""
    try:
        token = (
            _login_in_server_browser(request, auth) if body.backend_login else body.token
        )
        authorized = bool(token) and auth.is_authorized(token)
    except _MOODLE_ERRORS as error:
        raise HTTPException(status_code=503, detail=_MOODLE_DOWN) from error
    if not authorized:
        return LoginResponse(success=False)

    old_token = sessions.token_for(session_id)
    if old_token is not None:
        # Signing in again (maybe as someone else) on the same app.
        sessions.update(session_id, token)
        calendar.forget(old_token)
    else:
        session_id = sessions.create(token)
    return LoginResponse(success=True, session=session_id)


@app.post("/api/moodle/logout")
def moodle_logout(
    session_id: SessionId, sessions: Sessions, calendar: MoodleCalendar
) -> LoginResponse:
    """Forgets this app's Moodle session. Other users aren't affected."""
    calendar.forget(sessions.token_for(session_id))
    sessions.delete(session_id)
    return LoginResponse(success=True)


class MoodleEventsResponse(BaseModel):
    events: list[MoodleEvent]
    fetched_at: datetime


@app.get("/api/moodle/events")
def get_moodle_events(
    session_id: SessionId, sessions: Sessions, service: MoodleCalendar
) -> MoodleEventsResponse:
    """The signed-in user's Moodle deadlines and class sessions."""
    token = sessions.token_for(session_id)
    if token is None:
        raise HTTPException(status_code=401, detail="Log in to Moodle first.")
    try:
        events, fetched_at = service.get_events(token)
    except MoodleNotAuthorized as error:
        # The Moodle session expired; make the app sign in again.
        sessions.delete(session_id)
        service.forget(token)
        raise HTTPException(status_code=401, detail=str(error)) from error
    except MoodleUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    return MoodleEventsResponse(events=events, fetched_at=fetched_at)


@app.get("/api/lsu/calendar/events")
async def get_calendar_events(
    service: Annotated[LsuCalendarService, Depends(get_calendar_service)],
    start: Annotated[date | None, Query(description="Only events ending on or after this date")] = None,
    end: Annotated[date | None, Query(description="Only events starting on or before this date")] = None,
    category: Annotated[list[Category] | None, Query(description="Repeat to allow several")] = None,
    term: Annotated[str | None, Query(description='For example "Spring Semester 2027"')] = None,
) -> CalendarResponse:
    try:
        snapshot = await service.get_snapshot()
    except CalendarUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from error

    def matches(event: CalendarEvent) -> bool:
        if category and event.category not in category:
            return False
        return not term or term.casefold() in (name.casefold() for name in event.terms)

    events = [
        event
        for event in snapshot.events
        if matches(event)
        and (start is None or event.end_date >= start)
        and (end is None or event.start_date <= end)
    ]
    return CalendarResponse(
        events=events,
        unscheduled=[event for event in snapshot.unscheduled if matches(event)],
        source=INDEX_URL,
        fetched_at=snapshot.fetched_at,
        stale=snapshot.stale,
    )


class ClubEventsResponse(BaseModel):
    events: list[ClubEvent]
    source: str
    fetched_at: datetime
    # True when the last refresh from TigerLink failed, so data may be old.
    stale: bool


@app.get("/api/tigerlink/events")
async def get_club_events(
    service: Annotated[TigerLinkService, Depends(get_tigerlink_service)],
    start: Annotated[date | None, Query(description="Only events ending on or after this date")] = None,
    end: Annotated[date | None, Query(description="Only events starting on or before this date")] = None,
    club: Annotated[str | None, Query(description="Club acronym or name, case-insensitive")] = None,
    event_type: Annotated[str | None, Query(description='For example "Service"')] = None,
    search: Annotated[str | None, Query(description="Matches the title, case-insensitive")] = None,
    limit: Annotated[int, Query(ge=1, le=2000, description="Most events to return")] = 500,
) -> ClubEventsResponse:
    try:
        snapshot = await service.get_snapshot()
    except TigerLinkUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from error

    def matches(event: ClubEvent) -> bool:
        if start is not None and (event.end or event.start).date() < start:
            return False
        if end is not None and event.start.date() > end:
            return False
        if event_type and (event.event_type or "").casefold() != event_type.casefold():
            return False
        if search and search.casefold() not in event.title.casefold():
            return False
        if club:
            folded = club.casefold()
            if folded not in (event.club_acronym or "").casefold() and folded not in (
                event.club or ""
            ).casefold():
                return False
        return True

    events = [event for event in snapshot.events if matches(event)]
    return ClubEventsResponse(
        events=events[:limit],
        source=TIGERLINK_SOURCE_URL,
        fetched_at=snapshot.fetched_at,
        stale=snapshot.stale,
    )
