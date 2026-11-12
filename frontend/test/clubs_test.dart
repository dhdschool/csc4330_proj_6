import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';
import 'package:frontend/models/calendar_event.dart';
import 'package:frontend/models/club_event.dart';
import 'package:frontend/services/calendar_api.dart';
import 'package:frontend/services/followed_clubs.dart';
import 'package:frontend/widgets/campus_map.dart';

Map<String, dynamic> _clubEvent(
  String id,
  String title,
  String type,
  String startUtc, {
  String? club,
  String? location,
  String? venue,
  String? place,
  double? latitude,
  double? longitude,
}) => {
  'id': id,
  'title': title,
  'start': startUtc,
  'end': null,
  'all_day': false,
  'event_type': type,
  'club': club,
  'club_acronym': club,
  'location': location,
  'venue': venue,
  'place': place,
  'latitude': latitude,
  'longitude': longitude,
  'tags': <String>[],
};

final _clubJson = {
  'events': [
    // Noon UTC avoids a local-timezone date shift in the test's day grouping.
    _clubEvent(
      '1',
      'Chess Club Meeting',
      'Meeting',
      '2026-11-10T18:00:00Z',
      club: 'Chess Club',
      location: '167 Coates Hall, Campus Life , 358J LSU Student Union',
      venue: '167 Coates Hall',
      place: 'Coates Hall',
      latitude: 30.4132,
      longitude: -91.1791,
    ),
    _clubEvent(
      '2',
      'Food Drive',
      'Service',
      '2026-11-12T17:00:00Z',
      club: 'Volunteer LSU',
    ),
    _clubEvent(
      '3',
      'Past Social',
      'Social',
      '2026-10-01T17:00:00Z',
      club: 'Old Club',
    ),
  ],
  'source': 'https://tigerlink.lsu.edu/events',
  'fetched_at': '2026-11-06T12:00:00Z',
  'stale': false,
};

final _calendarJson = {
  'events': [
    {
      'id': 'a',
      'title': 'Classes begin',
      'category': 'classes',
      'start_date': '2026-08-24',
      'end_date': '2026-08-24',
      'date_text': '2026-08-24',
      'terms': ['Fall Semester 2026'],
      'academic_year': '2026-2027',
    },
  ],
  'unscheduled': <Map<String, dynamic>>[],
  'source': 'https://www.lsu.edu/registrar',
  'fetched_at': '2026-11-06T12:00:00Z',
  'stale': false,
};

class _FakeApi implements CalendarRepository, ClubRepository {
  _FakeApi({this.clubResult});

  Future<ClubEventsData> Function()? clubResult;
  int clubCalls = 0;

  @override
  Future<CalendarData> fetchCalendar() async =>
      CalendarData.fromJson(_calendarJson);

  @override
  Future<ClubEventsData> fetchClubEvents() {
    clubCalls++;
    return (clubResult ?? () async => ClubEventsData.fromJson(_clubJson))();
  }
}

Future<_FakeApi> _pump(
  WidgetTester tester, {
  _FakeApi? api,
  FollowStore? follows,
}) async {
  final fake = api ?? _FakeApi();
  await tester.pumpWidget(
    LsuCalendarApp(
      repository: fake,
      clubRepository: fake,
      followStore: follows ?? MemoryFollowStore(),
      clock: () => DateTime(2026, 11, 6, 9),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _openClubs(WidgetTester tester) async {
  await tester.tap(find.text('Clubs'));
  await tester.pumpAndSettle();
}

/// Switches the Clubs view to "All" mode (the Browse-all segment).
Future<void> _browseAll(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.public));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    CampusMap.showTiles = false; // tests can't load network tiles
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1080,
      2400,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 2.5;
  });

  test('parses club events from JSON', () {
    final data = ClubEventsData.fromJson(_clubJson);
    expect(data.events, hasLength(3));
    expect(data.eventTypes, ['Meeting', 'Service', 'Social']);
    expect(data.clubs, ['Chess Club', 'Old Club', 'Volunteer LSU']);
    expect(data.events.first.club, 'Chess Club');
    expect(data.events.first.hasCoordinates, isTrue);
    expect(data.events.first.latitude, 30.4132);
    expect(data.events[1].hasCoordinates, isFalse);
  });

  testWidgets('clubs load lazily and prompt to follow when none are followed', (
    tester,
  ) async {
    final api = await _pump(tester);
    expect(api.clubCalls, 0); // not fetched at startup

    await _openClubs(tester);
    expect(api.clubCalls, 1);

    // Following is the default view, and nothing is followed yet.
    expect(find.text("You're not following any clubs yet"), findsOneWidget);
    expect(find.text('Chess Club Meeting'), findsNothing);
  });

  testWidgets('browsing all shows every upcoming event and hides past ones', (
    tester,
  ) async {
    await _pump(tester);
    await _openClubs(tester);
    await _browseAll(tester);

    expect(find.text('Chess Club Meeting'), findsOneWidget);
    expect(find.text('Food Drive'), findsOneWidget);
    expect(find.text('Past Social'), findsNothing);
  });

  testWidgets('following a club filters the Following view to its events', (
    tester,
  ) async {
    await _pump(tester, follows: MemoryFollowStore(['Chess Club']));
    await _openClubs(tester);

    // Default Following view shows only the followed club's event.
    expect(find.text('Chess Club Meeting'), findsOneWidget);
    expect(find.text('Food Drive'), findsNothing);
    expect(find.text('Following (1)'), findsOneWidget);
  });

  testWidgets('tapping a tile star follows that club', (tester) async {
    final follows = MemoryFollowStore();
    await _pump(tester, follows: follows);
    await _openClubs(tester);
    await _browseAll(tester);

    await tester.tap(find.byTooltip('Follow Chess Club'));
    await tester.pumpAndSettle();

    expect(follows.clubs, {'Chess Club'});
    expect(find.text('Following (1)'), findsOneWidget);
  });

  testWidgets('the club picker lists clubs and follows on tap', (tester) async {
    final follows = MemoryFollowStore();
    await _pump(tester, follows: follows);
    await _openClubs(tester);

    await tester.tap(find.byTooltip('Follow clubs'));
    await tester.pumpAndSettle();

    expect(find.text('Search 3 clubs'), findsOneWidget);
    await tester.tap(find.text('Volunteer LSU'));
    await tester.pumpAndSettle();

    expect(follows.clubs, {'Volunteer LSU'});
  });

  testWidgets('search filters club events', (tester) async {
    await _pump(tester);
    await _openClubs(tester);
    await _browseAll(tester);

    await tester.enterText(find.byType(TextField), 'food');
    await tester.pumpAndSettle();

    expect(find.text('Food Drive'), findsOneWidget);
    expect(find.text('Chess Club Meeting'), findsNothing);
  });

  testWidgets('type filter chips narrow the list', (tester) async {
    await _pump(tester);
    await _openClubs(tester);
    await _browseAll(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Service'));
    await tester.pumpAndSettle();

    expect(find.text('Food Drive'), findsOneWidget);
    expect(find.text('Chess Club Meeting'), findsNothing);
  });

  testWidgets('tapping a club event opens its details', (tester) async {
    await _pump(tester);
    await _openClubs(tester);
    await _browseAll(tester);

    await tester.tap(find.text('Chess Club Meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Chess Club'), findsWidgets);
    expect(find.text('Meeting'), findsWidgets);
  });

  testWidgets('shows an error with retry when clubs fail to load', (
    tester,
  ) async {
    var fail = true;
    final api = _FakeApi(
      clubResult: () async {
        if (fail) throw CalendarApiException('TigerLink is down.');
        return ClubEventsData.fromJson(_clubJson);
      },
    );
    await _pump(tester, api: api, follows: MemoryFollowStore(['Chess Club']));
    await _openClubs(tester);

    expect(find.text('TigerLink is down.'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // Loads, and the followed club's event appears.
    expect(find.text('Chess Club Meeting'), findsOneWidget);
    expect(api.clubCalls, 2);
  });

  testWidgets('event details show the venue, a map and directions', (
    tester,
  ) async {
    await _pump(tester);
    await _openClubs(tester);
    await _browseAll(tester);

    await tester.tap(find.text('Chess Club Meeting'));
    await tester.pumpAndSettle();

    expect(find.text('167 Coates Hall'), findsOneWidget);
    expect(find.byType(EventMapPreview), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);
  });

  testWidgets('a hidden location says to check TigerLink', (tester) async {
    await _pump(tester);
    await _openClubs(tester);
    await _browseAll(tester);

    await tester.tap(find.text('Food Drive'));
    await tester.pumpAndSettle();

    expect(
      find.text('Location only shown on TigerLink after signing in'),
      findsOneWidget,
    );
    expect(find.byType(EventMapPreview), findsNothing);
    expect(find.text('Directions'), findsNothing);
  });

  testWidgets('map mode pins events and lists them per building', (
    tester,
  ) async {
    await _pump(tester);
    await _openClubs(tester);
    await _browseAll(tester);

    await tester.tap(find.byTooltip('Show map'));
    await tester.pumpAndSettle();

    expect(find.byType(ClubsMapView), findsOneWidget);
    // Chess Club is at Coates; Food Drive has no location, so no pin.
    expect(find.textContaining('1 on the map'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pin-Coates Hall')));
    await tester.pumpAndSettle();

    expect(find.text('Coates Hall'), findsOneWidget);
    expect(find.text('Chess Club Meeting'), findsOneWidget);

    // Back to the list.
    await tester.tap(find.text('Chess Club Meeting'));
    await tester.pumpAndSettle();
    expect(find.text('Directions'), findsOneWidget);
  });
}
