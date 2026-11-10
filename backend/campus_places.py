"""Places TigerLink events on the LSU campus map.

TigerLink locations are free text, with no coordinates. Most also end with the
same default address ("Campus Life, 358J LSU Student Union, ...") whatever room
the event is in, so geocoding the whole string would put nearly every event at
the Student Union. Instead we keep the part before that default (the "venue")
and match it against a table of campus buildings.

Coordinates come from OpenStreetMap (looked up once, November 2026). Buildings
OpenStreetMap doesn't have are left out rather than guessed, so their events
get no pin.
"""

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Place:
    name: str
    latitude: float
    longitude: float


def _place(name: str, lat: float, lng: float) -> Place:
    return Place(name, lat, lng)


UNION = _place("LSU Student Union", 30.41277, -91.17707)
UNION_THEATER = _place("LSU Union Theater", 30.41290, -91.17783)
COATES = _place("Coates Hall", 30.41320, -91.17906)
JOURNALISM = _place("Journalism Building (Manship School)", 30.41355, -91.18276)
PFT = _place("Patrick F. Taylor Hall", 30.40769, -91.17996)
PARADE = _place("Parade Ground", 30.41339, -91.17739)
MIDDLETON = _place("Middleton Library", 30.41443, -91.18009)
HILL = _place("Hill Memorial Library", 30.41438, -91.18145)
HPL = _place("Huey P. Long Field House", 30.41427, -91.18353)
NICHOLSON = _place("Nicholson Hall", 30.41244, -91.17899)
HOWE_RUSSELL = _place("Howe-Russell Geoscience Complex", 30.41177, -91.17859)
CHOPPIN = _place("Choppin Hall", 30.41041, -91.17722)
PMAC = _place("Pete Maravich Assembly Center", 30.41448, -91.18449)
WILLIAMS = _place("Williams Hall", 30.41043, -91.17766)
DMC = _place("Digital Media Center", 30.40746, -91.17240)
MUSIC = _place("Music & Dramatic Arts Building", 30.41643, -91.17955)
FRENCH_HOUSE = _place("French House", 30.41102, -91.17557)
ISB = _place("OLOL Interdisciplinary Science Building", 30.40987, -91.17845)
GREEK_THEATRE = _place("Greek Theatre", 30.41610, -91.18038)
PEABODY = _place("Peabody Hall", 30.41500, -91.18070)
PRESCOTT = _place("Prescott Hall", 30.41353, -91.18078)
BEC = _place("Business Education Complex", 30.40729, -91.17857)
UREC = _place("UREC Student Recreation Center", 30.41082, -91.16931)
LAVILLE = _place("Laville Hall", 30.41092, -91.17431)
# The annex is beside the Life Sciences Building, which is what OSM has.
LIFE_SCIENCES = _place("Life Sciences Annex", 30.41102, -91.17719)
TOWER = _place("Memorial Tower", 30.41447, -91.17892)

# Checked in order, so more specific patterns come first: "Hill Memorial
# Library" before "library", "Union Theater" before "union".
_RULES: list[tuple[re.Pattern[str], Place]] = [
    (re.compile(pattern, re.IGNORECASE), place)
    for pattern, place in [
        (r"hill memorial", HILL),
        (r"union theat|plakidas", UNION_THEATER),
        (r"\bpft\b|patrick f\.? taylor|cambre atrium", PFT),
        (r"\bbec\b|business education|ourso", BEC),
        (r"\bolol\b|interdisciplinary science", ISB),
        (r"coates|\bcoat\b|hopkins black box", COATES),
        (r"manship|journalism", JOURNALISM),
        (r"huey p\.? long|\bhpl\b", HPL),
        (r"howe[- ]?russel", HOWE_RUSSELL),
        (r"choppin", CHOPPIN),
        (r"\bpmac\b|maravich assembly", PMAC),
        (r"nicholson", NICHOLSON),
        (r"prescott", PRESCOTT),
        (r"peabody", PEABODY),
        (r"williams hall|^williams\b", WILLIAMS),
        (r"digital media center", DMC),
        (r"school of music|music (?:&|and) dramatic", MUSIC),
        (r"french house", FRENCH_HOUSE),
        (r"greek theat", GREEK_THEATRE),
        (r"parade ground", PARADE),
        (r"\burec\b|recreation center", UREC),
        (r"laville", LAVILLE),
        (r"life sciences annex|annex auditorium", LIFE_SCIENCES),
        (r"memorial tower", TOWER),
        (r"middleton|\blsu (?:main )?library\b", MIDDLETON),
        # Free Speech Alley is the walkway outside the Union.
        (r"free speech", UNION),
        # Student Union rooms are named after Louisiana places and rivers.
        (
            r"student union|\bunion\b|tcho?u?pitoulas|caddo|ouachita|"
            r"capital chamber|\bcouncil\b|feliciana|castilian|vieux carre|"
            r"atchafalaya|red river|international room|live oak lounge|"
            r"catahoula|ballroom",
            UNION,
        ),
    ]
]

# The default address CampusGroups appends to campus locations.
_DEFAULT_ADDRESS = re.compile(
    r",?\s*(?:Campus Life\s*,\s*)?358J LSU Student Union\b.*$", re.IGNORECASE
)
_COUNTRY = re.compile(r",?\s*United States\s*$", re.IGNORECASE)
# Not places at all, so never mapped.
_NOT_A_PLACE = re.compile(r"^(tbd|tba|online( event)?|virtual|zoom|campus-?wide)$", re.I)
# Real places we have no verified coordinates for. Checked before the rules so
# that, say, "Carl Maddox Fieldhouse (behind PMAC)" isn't pinned on the PMAC.
_UNMAPPED = re.compile(r"maddox|women'?s center|global community center", re.I)


def venue_of(location: str | None) -> str | None:
    """The meaningful part of a TigerLink location, for display.

    Drops the default Student Union address CampusGroups appends, so
    "167 Coates Hall, Campus Life , 358J LSU Student Union, ..." becomes
    "167 Coates Hall". Real addresses are kept, minus the country.
    """
    if not location:
        return None
    venue = _DEFAULT_ADDRESS.sub("", location)
    venue = _COUNTRY.sub("", venue).strip(" ,")
    venue = re.sub(r"\s+", " ", venue)
    venue = re.sub(r"\s*,(?:\s*,)+", ",", venue)  # "Dr, , Baton Rouge"
    return venue or None


def locate(venue: str | None) -> Place | None:
    """The campus building a venue is in, or None if it can't be placed."""
    if not venue or _NOT_A_PLACE.match(venue.strip()) or _UNMAPPED.search(venue):
        return None
    for pattern, place in _RULES:
        if pattern.search(venue):
            return place
    return None
