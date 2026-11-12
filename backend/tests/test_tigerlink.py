from datetime import datetime, timezone
from pathlib import Path

import pytest

from tigerlink import ClubEvent, TigerLinkParseError, parse_feed

FIXTURE = Path(__file__).parent / "fixtures" / "tigerlink_sample.ics"


@pytest.fixture(scope="module")
def events():
    return parse_feed(FIXTURE.read_text(encoding="utf8"))


def test_parses_every_event(events):
    assert len(events) == 6
    assert all(isinstance(e, ClubEvent) for e in events)


def test_events_are_sorted_by_start(events):
    assert events == sorted(events, key=lambda e: (e.start, e.title))


def test_first_event_fields(events):
    first = events[0]
    assert first.title == "RA Service Project"
    assert first.start == datetime(2026, 8, 8, 15, 0, tzinfo=timezone.utc)
    assert first.end == datetime(2026, 8, 8, 21, 0, tzinfo=timezone.utc)
    assert first.club == "Volunteer LSU"
    assert first.club_acronym == "VLSU"
    assert first.event_type == "Service"
    assert first.tags == ["Service/Volunteering"]
    assert first.url == "https://tigerlink.lsu.edu/rsvp?id=2277313"


def test_id_comes_from_the_event_url(events):
    # The URL carries ?id=2277313, which is stabler than the CampusGroups UID.
    assert events[0].id == "2277313"


def test_hidden_location_becomes_null(events):
    # CampusGroups returns a "Sign in to download the location" placeholder.
    assert all(e.location is None or "sign in" not in e.location.lower() for e in events)


def test_all_events_are_timezone_aware(events):
    assert all(e.start.tzinfo is not None for e in events)


def test_start_times_are_timed_not_all_day(events):
    assert not any(e.all_day for e in events)


def test_quoted_printable_summary_is_decoded():
    ics = (
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\n"
        "SUMMARY;ENCODING=QUOTED-PRINTABLE:Caf=C3=A9 & Cr=C3=AApes\n"
        "DTSTART:20261106T180000Z\n"
        "URL:https://tigerlink.lsu.edu/rsvp?id=42\n"
        "END:VEVENT\nEND:VCALENDAR\n"
    )
    event = parse_feed(ics)[0]
    assert event.title == "Café & Crêpes"


def test_escaped_text_in_description_is_unescaped():
    ics = (
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\n"
        "SUMMARY:Meeting\n"
        "DESCRIPTION:Line one\\nLine two\\; and a comma\\, too\n"
        "DTSTART:20261106T180000Z\nURL:https://x/rsvp?id=9\n"
        "END:VEVENT\nEND:VCALENDAR\n"
    )
    event = parse_feed(ics)[0]
    assert event.description == "Line one\nLine two; and a comma, too"


def test_folded_lines_are_joined():
    ics = (
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\n"
        "SUMMARY:A very long\n  title that was folded\n"
        "DTSTART:20261106T180000Z\nURL:https://x/rsvp?id=9\n"
        "END:VEVENT\nEND:VCALENDAR\n"
    )
    assert parse_feed(ics)[0].title == "A very long title that was folded"


def test_all_day_event_without_a_time():
    ics = (
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\n"
        "SUMMARY:Spirit Week\nDTSTART;VALUE=DATE:20261109\n"
        "URL:https://x/rsvp?id=9\nEND:VEVENT\nEND:VCALENDAR\n"
    )
    event = parse_feed(ics)[0]
    assert event.all_day is True
    assert event.start == datetime(2026, 11, 9, 0, 0, tzinfo=timezone.utc)


@pytest.mark.parametrize("club", ["LSU: Robotics Club", "Chess; Go & Shogi Club"])
def test_quoted_organizer_name_can_contain_colons_and_semicolons(club):
    ics = (
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\n"
        f'SUMMARY:Build Night\nORGANIZER;CN="{club}":mailto:noreply@tigerlink.lsu.edu\n'
        "DTSTART:20261106T180000Z\nURL:https://x/rsvp?id=9\n"
        "END:VEVENT\nEND:VCALENDAR\n"
    )
    assert parse_feed(ics)[0].club == club


def test_event_without_a_start_is_skipped():
    ics = (
        "BEGIN:VCALENDAR\n"
        "BEGIN:VEVENT\nSUMMARY:No date\nURL:https://x/rsvp?id=1\nEND:VEVENT\n"
        "BEGIN:VEVENT\nSUMMARY:Good\nDTSTART:20261106T180000Z\nURL:https://x/rsvp?id=2\nEND:VEVENT\n"
        "END:VCALENDAR\n"
    )
    events = parse_feed(ics)
    assert [e.title for e in events] == ["Good"]


def test_non_calendar_text_raises():
    with pytest.raises(TigerLinkParseError):
        parse_feed("<html>Access Denied</html>")


def test_campus_location_gets_venue_and_coordinates(events):
    event = next(e for e in events if e.location and "Coates" in e.location)
    assert event.venue == "167 Coates Hall"
    assert event.place == "Coates Hall"
    assert event.latitude == pytest.approx(30.4132, abs=1e-3)
    assert event.longitude == pytest.approx(-91.1791, abs=1e-3)


def test_hidden_location_has_no_coordinates(events):
    hidden = [e for e in events if e.location is None]
    assert hidden
    assert all(e.venue is None and e.latitude is None for e in hidden)
