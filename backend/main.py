from datetime import date, datetime
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

app = FastAPI(title="LSU UniCalendar")
# Lets the Flutter web build call the API. Everything here is public and read-only.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET"])

_service = LsuCalendarService()
_tigerlink = TigerLinkService()


def get_calendar_service() -> LsuCalendarService:
    return _service


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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


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
