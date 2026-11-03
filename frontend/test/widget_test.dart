import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';
import 'package:frontend/models/calendar_event.dart';
import 'package:frontend/services/calendar_api.dart';

Map<String, dynamic> _event(
  String title,
  String category,
  String? start, [
  String? end,
  Map<String, dynamic> extra = const {},
]) => {
  'id': '$start-$title',
  'title': title,
  'category': category,
  'start_date': start,
  'end_date': end ?? start,
  'date_text': start ?? 'TBD',
  'terms': ['Fall Semester 2026'],
  'academic_year': '2026-2027',
  ...extra,
};

final _sampleJson = {
  'events': [
    _event('Classes begin', 'classes', '2026-08-24'),
    _event('Final date to drop', 'deadline', '2026-11-04'),
    _event('Thanksgiving Holiday', 'holiday', '2026-11-25', '2026-11-29', {
      'classes_end_at': '12:30',
    }),
    _event('Last day of classes', 'classes', '2026-12-05'),
    _event('Final examinations', 'exam', '2026-12-07', '2026-12-13'),
    _event('Spring Break', 'holiday', '2027-03-29', '2027-04-04'),
  ],
  'unscheduled': [_event('Commencement exercises', 'commencement', null)],
  'source':
      'https://www.lsu.edu/registrar/academics/academic-calendars/index.php',
  'fetched_at': '2026-11-03T12:00:00Z',
  'stale': false,
};

class _FakeRepository implements CalendarRepository {
  _FakeRepository(this.result);

  Future<CalendarData> Function() result;
  int calls = 0;

  @override
  Future<CalendarData> fetchCalendar() {
    calls++;
    return result();
  }
}

Future<_FakeRepository> _pumpApp(
  WidgetTester tester, {
  Future<CalendarData> Function()? result,
}) async {
  final repository = _FakeRepository(
    result ?? () async => CalendarData.fromJson(_sampleJson),
  );
  await tester.pumpWidget(
    LsuCalendarApp(
      repository: repository,
      clock: () => DateTime(2026, 11, 3, 9, 30),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1080,
      2400,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 2.5;
  });

  test('parses events, including multi-day and unscheduled ones', () {
    final data = CalendarData.fromJson(_sampleJson);
    final thanksgiving = data.events[2];

    expect(thanksgiving.category, EventCategory.holiday);
    expect(thanksgiving.classesEndAt, '12:30');
    expect(thanksgiving.occursOn(DateTime(2026, 11, 27)), isTrue);
    expect(thanksgiving.occursOn(DateTime(2026, 11, 30)), isFalse);
    expect(data.unscheduled.single.isScheduled, isFalse);
  });

  testWidgets('shows the current month and today\'s events', (tester) async {
    await _pumpApp(tester);

    expect(find.text('November 2026'), findsOneWidget);
    expect(find.textContaining('Tuesday, November 3, 2026'), findsOneWidget);
    expect(find.text('No LSU calendar events on this day.'), findsOneWidget);
  });

  testWidgets('selecting a day lists its events', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    expect(find.text('Thanksgiving Holiday'), findsOneWidget);
  });

  testWidgets('tapping an event opens its details', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thanksgiving Holiday'));
    await tester.pumpAndSettle();

    expect(find.text('Classes end at 12:30 PM'), findsOneWidget);
    expect(find.text('5 days'), findsOneWidget);
  });

  testWidgets('agenda hides past events and lists undated ones', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    expect(find.text('Classes begin'), findsNothing);
    expect(find.text('Final date to drop'), findsOneWidget);

    await tester.tap(find.text('Show past'));
    await tester.pumpAndSettle();
    expect(find.text('Classes begin'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Commencement exercises'), 200);
    expect(find.text('DATES TO BE ANNOUNCED'), findsOneWidget);
  });

  testWidgets('holidays tab counts down to the next break', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Holidays'));
    await tester.pumpAndSettle();

    expect(find.text('NEXT BREAK'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(find.text('Spring Break'), findsOneWidget);
    expect(find.text('In 5 months'), findsOneWidget);
  });

  testWidgets('category filter hides events', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Holidays only'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // Close the sheet.
    await tester.pumpAndSettle();

    expect(find.text('Final date to drop'), findsNothing);
    expect(find.text('Thanksgiving Holiday'), findsOneWidget);
  });

  testWidgets('shows an error with a working retry button', (tester) async {
    var fail = true;
    final repository = await _pumpApp(
      tester,
      result: () async {
        if (fail) throw CalendarApiException('Server is down.');
        return CalendarData.fromJson(_sampleJson);
      },
    );

    expect(find.text("Couldn't load the calendar"), findsOneWidget);
    expect(find.text('Server is down.'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('November 2026'), findsOneWidget);
  });

  testWidgets('warns when the data is stale', (tester) async {
    await _pumpApp(
      tester,
      result: () async =>
          CalendarData.fromJson({..._sampleJson, 'stale': true}),
    );

    expect(find.textContaining('may be out of date'), findsOneWidget);
  });
}
