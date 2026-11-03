import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/utils/date_format.dart';

void main() {
  test('formatDateRange collapses repeated parts', () {
    expect(
      formatDateRange(DateTime(2026, 11, 25), DateTime(2026, 11, 25)),
      'Wed, Nov 25, 2026',
    );
    expect(
      formatDateRange(DateTime(2026, 11, 25), DateTime(2026, 11, 29)),
      'Nov 25 – 29, 2026',
    );
    expect(
      formatDateRange(DateTime(2027, 3, 29), DateTime(2027, 4, 4)),
      'Mar 29 – Apr 4, 2027',
    );
    expect(
      formatDateRange(DateTime(2026, 12, 19), DateTime(2027, 1, 18)),
      'Dec 19, 2026 – Jan 18, 2027',
    );
  });

  test('formatTime converts to 12-hour', () {
    expect(formatTime('00:15'), '12:15 AM');
    expect(formatTime('12:30'), '12:30 PM');
    expect(formatTime('16:30'), '4:30 PM');
  });

  test('daysBetween ignores DST changes', () {
    // US clocks fall back on November 1, 2026.
    expect(daysBetween(DateTime(2026, 10, 31), DateTime(2026, 11, 2)), 2);
    expect(daysBetween(DateTime(2027, 3, 13), DateTime(2027, 3, 15)), 2);
  });

  test('formatCountdown', () {
    final today = DateTime(2026, 11, 3);
    expect(formatCountdown(today, today, today), 'Happening now');
    expect(
      formatCountdown(DateTime(2026, 11, 4), DateTime(2026, 11, 4), today),
      'Tomorrow',
    );
    expect(
      formatCountdown(DateTime(2026, 11, 13), DateTime(2026, 11, 13), today),
      'In 10 days',
    );
    expect(
      formatCountdown(DateTime(2026, 11, 25), DateTime(2026, 11, 29), today),
      'In 3 weeks',
    );
  });
}
