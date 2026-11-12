import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/club_event.dart';

void main() {
  for (final suffix in ['Z', '+00:00']) {
    test('all-day dates preserve their calendar components ($suffix)', () {
      final event = ClubEvent.fromJson({
        'id': 'all-day',
        'title': 'All-day event',
        'start': '2026-11-12T00:00:00$suffix',
        'end': '2026-11-13T00:00:00$suffix',
        'all_day': true,
      });
      expect(event.start, DateTime(2026, 11, 12));
      expect(event.end, DateTime(2026, 11, 13));
      expect(event.lastDay, DateTime(2026, 11, 12));
      expect(event.isCurrentOrUpcoming(DateTime(2026, 11, 12)), isTrue);
      expect(event.isCurrentOrUpcoming(DateTime(2026, 11, 13)), isFalse);
    });
  }

  test('an all-day event without an end covers its start date', () {
    final event = ClubEvent.fromJson({
      'id': 'no-end',
      'title': 'All-day event',
      'start': '2026-11-12T00:00:00Z',
      'all_day': true,
    });
    expect(event.end, isNull);
    expect(event.lastDay, DateTime(2026, 11, 12));
    expect(event.isCurrentOrUpcoming(DateTime(2026, 11, 12)), isTrue);
    expect(event.isCurrentOrUpcoming(DateTime(2026, 11, 13)), isFalse);
  });

  for (final dates in [
    ('2026-03-07', '2026-03-10', DateTime(2026, 3, 9)),
    ('2026-10-31', '2026-11-03', DateTime(2026, 11, 2)),
  ]) {
    test('all-day ranges retain their final day across DST (${dates.$1})', () {
      final event = ClubEvent.fromJson({
        'id': 'dst',
        'title': 'Retreat',
        'start': '${dates.$1}T00:00:00Z',
        'end': '${dates.$2}T00:00:00Z',
        'all_day': true,
      });
      expect(event.lastDay, dates.$3);
      expect(event.isCurrentOrUpcoming(dates.$3), isTrue);
      expect(event.isCurrentOrUpcoming(DateTime.parse(dates.$2)), isFalse);
    });
  }

  test('timed events still convert UTC instants to device local time', () {
    for (final allDayFields in [
      <String, dynamic>{},
      {'all_day': false},
    ]) {
      final event = ClubEvent.fromJson({
        'id': 'timed',
        'title': 'Late meeting',
        'start': '2026-11-12T02:00:00Z',
        'end': '2026-11-12T04:00:00Z',
        ...allDayFields,
      });
      expect(event.allDay, isFalse);
      expect(event.start, DateTime.utc(2026, 11, 12, 2).toLocal());
      expect(event.end, DateTime.utc(2026, 11, 12, 4).toLocal());
    }
  });
}
