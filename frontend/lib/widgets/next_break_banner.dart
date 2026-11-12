import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../theme.dart';
import '../utils/date_format.dart';
import 'event_details_sheet.dart';

/// The next (or current) holiday, with a countdown in days.
class NextBreakBanner extends StatelessWidget {
  const NextBreakBanner({
    super.key,
    required this.holiday,
    required this.today,
  });

  final CalendarEvent holiday;
  final DateTime today;

  /// The first holiday that hasn't ended yet, or null if none is published.
  /// Expects [events] sorted by start date, as the backend returns them.
  static CalendarEvent? findNext(List<CalendarEvent> events, DateTime today) {
    for (final event in events) {
      if (event.category == EventCategory.holiday &&
          !event.endDate!.isBefore(today)) {
        return event;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = holiday.startDate!;
    final end = holiday.endDate!;
    final daysAway = daysBetween(today, start);
    final happening = daysAway <= 0;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      color: lsuPurple,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showEventDetails(context, holiday),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      happening ? 'ENJOY THE BREAK' : 'NEXT BREAK',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: lsuGold,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      holiday.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDateRange(start, end),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: lightGold,
                      ),
                    ),
                    if (holiday.classesEndAt != null)
                      Text(
                        'Classes end at ${formatTime(holiday.classesEndAt!)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: lightGold,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  Text(
                    happening ? 'NOW' : '$daysAway',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: lsuGold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!happening)
                    Text(
                      daysAway == 1 ? 'day to go' : 'days to go',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: lightGold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
