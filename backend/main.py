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

app = FastAPI(title="LSU UniCalendar")
# Lets the Flutter web build call the API. Everything here is public and read-only.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET"])

_service = LsuCalendarService()


def get_calendar_service() -> LsuCalendarService:
    return _service


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
