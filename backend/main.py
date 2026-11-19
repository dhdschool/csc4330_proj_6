from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Query
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

app = FastAPI(title="LSU UniCalendar")
# Lets the Flutter web build call the API. POST + Content-Type are needed for the
# JSON body sent to /api/moodle/login (the browser preflights it with OPTIONS).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)

_service = LsuCalendarService()
_tigerlink = TigerLinkService()

_login_endpoint = moodle.LoginRequest()
_moodle_calendar = MoodleCalendarService()

def get_calendar_service() -> LsuCalendarService:
    return _service


def get_moodle_calendar_service() -> MoodleCalendarService:
    return _moodle_calendar


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

class LoginRequest(BaseModel):
    token: str
    backend_login: bool

class IsAuthorizedResponse(BaseModel):
    authorized: bool
    login_url: str | None = None

@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

@app.get("/api/moodle/authorized")
def moodle_is_authorized() -> IsAuthorizedResponse:
    authorized = _login_endpoint.is_authorized()
    url: str | None = None
    if not authorized:
        url = _login_endpoint.get()
    
    return IsAuthorizedResponse(authorized=authorized, login_url = url)

@app.post("/api/moodle/login")
def moodle_login(request: LoginRequest) -> LoginResponse:
    moodle.moodle4_token = request.token
    
    if request.backend_login:
        _login_endpoint.get(backend_login=True)
        
    authorized = _login_endpoint.is_authorized()

    return LoginResponse(success=authorized)


@app.post("/api/moodle/logout")
def moodle_logout() -> LoginResponse:
    moodle.logout()
    return LoginResponse(success=True)


class MoodleEventsResponse(BaseModel):
    events: list[MoodleEvent]
    fetched_at: datetime


# Sync on purpose: the Moodle client uses requests, so FastAPI runs this in a
# worker thread instead of blocking the event loop.
@app.get("/api/moodle/events")
def get_moodle_events(
    service: Annotated[MoodleCalendarService, Depends(get_moodle_calendar_service)],
) -> MoodleEventsResponse:
    try:
        events, fetched_at = service.get_events()
    except MoodleNotAuthorized as error:
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

    def last_day(event: ClubEvent) -> date:
        if event.end is None:
            return event.start.date()
        if event.all_day:
            # iCalendar all-day DTEND is exclusive: the event ends the day before.
            return max(event.start.date(), (event.end - timedelta(days=1)).date())
        return event.end.date()

    def matches(event: ClubEvent) -> bool:
        if start is not None and last_day(event) < start:
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
