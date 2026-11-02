from datetime import date
from pathlib import Path

import pytest

from lsu_calendar import (
    CalendarParseError,
    find_academic_years,
    merge_events,
    parse_calendar_page,
)

FIXTURES = Path(__file__).parent / "fixtures"


def load(academic_year):
    html = (FIXTURES / f"{academic_year}-academic-calendar.html").read_text(encoding="utf8")
    return merge_events(parse_calendar_page(html, academic_year))


def find(events, title, term=None):
    matches = [
        e for e in events
        if e.title.startswith(title) and (term is None or term in e.terms)
    ]
    assert matches, f"no event starting with {title!r}"
    return matches


@pytest.fixture(scope="module")
def year_2026():
    return load("2026-2027")[0]


def test_terms_get_the_right_years(year_2026):
    assert find(year_2026, "Classes Begin", "Fall Semester 2026")[0].start_date == date(2026, 8, 24)
    assert find(year_2026, "Classes Begin", "Spring Semester 2027")[0].start_date == date(2027, 1, 11)
    assert find(year_2026, "Classes Begin", "First Summer 2027")[0].start_date == date(2027, 5, 24)
    assert find(year_2026, "Classes Begin", "Second Summer 2027")[0].start_date == date(2027, 7, 6)


def test_wintersession_crosses_new_year(year_2026):
    assert find(year_2026, "Classes Begin", "Wintersession 2026")[0].start_date == date(2026, 12, 14)
    assert find(year_2026, "Last Day of Classes", "Wintersession 2026")[0].start_date == date(2027, 1, 5)


def test_winter_holiday_runs_until_classes_resume(year_2026):
    holiday = find(year_2026, "Winter Holiday")[0]
    assert (holiday.start_date, holiday.end_date) == (date(2026, 12, 24), date(2027, 1, 3))
    assert holiday.category == "holiday"


def test_each_paragraph_in_a_cell_is_its_own_event(year_2026):
    on_sep_2 = [e for e in year_2026 if e.start_date == date(2026, 9, 2)]
    assert len(on_sep_2) == 2
    assert {e.category for e in on_sep_2} == {"deadline"}


def test_missing_space_after_quote_is_fixed(year_2026):
    assert find(year_2026, 'Final date for dropping courses without', "First Summer 2027")[0].title == (
        'Final date for dropping courses without receiving a grade of a "W" and making section changes'
    )


def test_date_pairs_become_separate_days(year_2026):
    finals = find(year_2026, "Final classes and Final examinations", "First Summer 2027")
    assert [(e.start_date, e.end_date) for e in finals] == [
        (date(2027, 6, 26), date(2027, 6, 26)),
        (date(2027, 6, 28), date(2027, 6, 28)),
    ]


def test_partial_day_holidays(year_2026):
    thanksgiving = find(year_2026, "Thanksgiving Holiday")[0]
    assert thanksgiving.title == "Thanksgiving Holiday"
    assert thanksgiving.classes_end_at == "12:30"
    assert (thanksgiving.start_date, thanksgiving.end_date) == (date(2026, 11, 25), date(2026, 11, 27))

    mardi_gras = find(year_2026, "Mardi Gras Holiday")[0]
    assert mardi_gras.title == "Mardi Gras Holiday"
    assert mardi_gras.classes_resume_at == "12:30"
    assert mardi_gras.description == "Classes resume at 12:30pm on February 10"


def test_policy_text_stays_with_its_event(year_2026):
    assert not [e for e in year_2026 if e.title.startswith("Graded coursework")]
    begins = [e for e in find(year_2026, "Concentrated Study") if "begins" in e.title]
    assert len(begins) == 2
    for event in begins:
        assert event.category == "study_period"
        assert event.description.startswith("Graded coursework")


def test_summer_break_footnote_is_an_event(year_2026):
    summer_break = find(year_2026, "Summer Break")[0]
    assert (summer_break.start_date, summer_break.end_date) == (date(2027, 6, 29), date(2027, 7, 5))
    assert summer_break.category == "holiday"
    assert "no long session classes" in summer_break.description


def test_events_listed_in_two_terms_are_combined(year_2026):
    commencement = [e for e in year_2026 if e.start_date == date(2027, 8, 13)]
    assert len(commencement) == 1
    assert commencement[0].terms == ["First Summer 2027", "Second Summer 2027"]


def test_tentative_marker_becomes_a_flag(year_2026):
    scheduling = find(year_2026, "Course scheduling for summer")[0]
    assert scheduling.tentative is True
    assert "entative" not in scheduling.title
    assert find(year_2026, "Labor Day")[0].tentative is False


def test_tbd_events_are_unscheduled_per_term():
    events, unscheduled = load("2027-2028")
    assert [e.terms for e in unscheduled] == [["Fall Semester 2027"], ["Spring Semester 2028"]]
    assert all(e.start_date is None and e.date_text == "TBD" for e in unscheduled)
    assert all(e.start_date for e in events)


def test_range_across_months():
    events, _ = load("2027-2028")
    mardi_gras = find(events, "Mardi Gras Holiday")[0]
    assert (mardi_gras.start_date, mardi_gras.end_date) == (date(2028, 2, 28), date(2028, 3, 1))


def test_summer_listed_before_fall_uses_the_start_year():
    events, _ = load("2025-2026")
    assert find(events, "Classes Begin", "First Summer 2025")[0].start_date == date(2025, 5, 27)
    assert find(events, "Classes Begin", "First Summer 2026")[0].start_date == date(2026, 5, 26)


@pytest.mark.parametrize("academic_year", ["2025-2026", "2026-2027", "2027-2028"])
def test_real_pages_parse_completely(academic_year, caplog):
    events, unscheduled = load(academic_year)
    assert not [e.title for e in events + unscheduled if e.category == "other"]
    assert all(e.start_date <= e.end_date for e in events)
    assert len({e.id for e in events + unscheduled}) == len(events) + len(unscheduled)
    assert not caplog.records  # nothing was skipped


TABLE = (
    "<h2>Fall Semester 2026</h2><table><tr><td><p>{date}</p></td>"
    "<td><p>Classes Begin</p></td></tr></table>"
)


@pytest.mark.parametrize("bad_date", ["February 30", "Sometime in spring"])
def test_unusable_dates_are_kept_and_logged(bad_date, caplog):
    events, unscheduled = merge_events(parse_calendar_page(TABLE.format(date=bad_date), "2026-2027"))
    assert events == []
    assert unscheduled[0].date_text == bad_date
    assert bad_date in caplog.text


def test_tentative_marker_in_the_date_cell():
    html = TABLE.format(date="August 24 *Tentative*")
    event = parse_calendar_page(html, "2026-2027")[0]
    assert event.tentative is True
    assert event.start_date == date(2026, 8, 24)


def test_page_without_a_calendar_is_an_error():
    with pytest.raises(CalendarParseError):
        parse_calendar_page("<html><body><p>Page moved</p></body></html>", "2026-2027")


def test_find_academic_years_skips_finished_years():
    html = (FIXTURES / "index.html").read_text(encoding="utf8")
    assert find_academic_years(html, date(2026, 11, 1)) == [
        "2025-2026",
        "2026-2027",
        "2027-2028",
        "2028-2029",
    ]
