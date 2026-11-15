import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/calendar_event.dart';
import 'package:frontend/models/moodle_event.dart';

void main() {
  test('timed deadlines land on the local day and keep their time', () {
    final event = MoodleEvent.fromJson({
      'id': 'a1',
      'title': 'Assignment 4 is due',
      'start': '2026-11-21T05:59:00Z',
      'end': '2026-11-21T05:59:00Z',
      'all_day': false,
      'course': '2026 Fall CSC 4501',
    }).toCalendarEvent();

    // Compute the expectation in whatever zone the test machine is in.
    final local = DateTime.parse('2026-11-21T05:59:00Z').toLocal();
    expect(event.startDate, DateTime(local.year, local.month, local.day));
    expect(event.endDate, event.startDate);
    expect(
      event.startTime,
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}',
    );
    // A deadline is a moment, not a span.
    expect(event.endTime, isNull);
    expect(event.category, EventCategory.moodle);
    expect(event.terms, ['2026 Fall CSC 4501']);
    expect(event.id, 'moodle-a1');
  });

  test('sessions keep their end time', () {
    final event = MoodleEvent.fromJson({
      'id': 'a2',
      'title': 'Attendance',
      'start': '2026-11-17T15:00:00Z',
      'end': '2026-11-17T16:20:00Z',
    }).toCalendarEvent();

    final end = DateTime.parse('2026-11-17T16:20:00Z').toLocal();
    expect(
      event.endTime,
      '${end.hour.toString().padLeft(2, '0')}:'
      '${end.minute.toString().padLeft(2, '0')}',
    );
    expect(event.terms, isEmpty);
  });

  test('all-day events keep their calendar day and have no time', () {
    final event = MoodleEvent.fromJson({
      'id': 'a3',
      'title': 'Reading day',
      'start': '2026-12-03T00:00:00Z',
      'end': null,
      'all_day': true,
    }).toCalendarEvent();

    expect(event.startDate, DateTime(2026, 12, 3));
    expect(event.endDate, DateTime(2026, 12, 3));
    expect(event.startTime, isNull);
  });

  test('parses the events response', () {
    final data = MoodleEventsData.fromJson({
      'events': [
        {'id': 'a1', 'title': 'Quiz', 'start': '2026-11-20T15:00:00Z'},
      ],
      'fetched_at': '2026-11-15T23:28:15Z',
    });
    expect(data.events.single.title, 'Quiz');
  });
}
