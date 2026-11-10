import pytest

from campus_places import COATES, PFT, PMAC, UNION, UNION_THEATER, locate, venue_of

SUFFIX = ", Campus Life , 358J LSU Student Union, Baton Rouge, Louisiana 70803, United States"


@pytest.mark.parametrize(
    ("location", "venue"),
    [
        ("167 Coates Hall" + SUFFIX, "167 Coates Hall"),
        ("Capital Chamber\u2014 329" + SUFFIX, "Capital Chamber\u2014 329"),
        ("Carl Maddox Fieldhouse, 358J LSU Student Union, Baton Rouge, LA 70803, United States",
         "Carl Maddox Fieldhouse"),
        ("Walk On's Burbank, 3838 Burbank Dr, , Baton Rouge 70808, United States",
         "Walk On's Burbank, 3838 Burbank Dr, Baton Rouge 70808"),
        (None, None),
        ("", None),
    ],
)
def test_venue_drops_default_address(location, venue):
    assert venue_of(location) == venue


@pytest.mark.parametrize(
    ("venue", "place"),
    [
        ("167 Coates Hall", COATES),
        ("Coates ; COAT 0220", COATES),
        ("PFT 1202", PFT),
        ("Patrick F. Taylor Hall, Rm 1200, Baton Rouge, LA 70806", PFT),
        ("Tchopitoulas Room", UNION),
        ("Student Union Caddo Room 305", UNION),
        ("Free Speech Alley (FSA)", UNION),
        # The more specific Union Theater wins over the Union.
        ("LSU Student Union Theater", UNION_THEATER),
        ("PMAC", PMAC),
    ],
)
def test_locate_matches_campus_buildings(venue, place):
    assert locate(venue) == place


@pytest.mark.parametrize(
    "venue",
    [
        "TBD",
        "Online Event",
        "Campus-wide",
        "BREC Baton Rouge Zoo, 3601 Thomas Road, Baton Rouge, LA 70807",
        # Behind the PMAC, but not the PMAC; better no pin than a wrong one.
        "Carl Maddox Fieldhouse (Indoor Track Facility behind PMAC)",
        None,
    ],
)
def test_locate_leaves_unknown_places_unmapped(venue):
    assert locate(venue) is None
