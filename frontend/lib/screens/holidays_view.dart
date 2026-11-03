import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../theme.dart';
import '../utils/date_format.dart';
import '../widgets/event_details_sheet.dart';
import '../widgets/event_tile.dart';

/// Upcoming holidays and breaks, with the next one featured at the top.
class HolidaysView extends StatelessWidget {
  const HolidaysView({
    super.key,
    required this.holidays,
    required this.today,
    required this.onRefresh,
  });

  final List<CalendarEvent> holidays;
  final DateTime today;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final upcoming = [
      for (final holiday in holidays)
        if (!holiday.endDate!.isBefore(today)) holiday,
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (upcoming.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No upcoming holidays have been published yet.',
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                _NextHolidayCard(holiday: upcoming.first, today: today),
                for (final holiday in upcoming.skip(1))
                  EventTile(
                    event: holiday,
                    trailing: _Countdown(
                      text: formatCountdown(
                        holiday.startDate!,
                        holiday.endDate!,
                        today,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NextHolidayCard extends StatelessWidget {
  const _NextHolidayCard({required this.holiday, required this.today});

  final CalendarEvent holiday;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = holiday.startDate!;
    final end = holiday.endDate!;
    final daysAway = daysBetween(today, start);
    final happening = daysAway <= 0;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                        color: Colors.white70,
                      ),
                    ),
                    if (holiday.classesEndAt != null)
                      Text(
                        'Classes end at ${formatTime(holiday.classesEndAt!)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
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
                        color: Colors.white70,
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

class _Countdown extends StatelessWidget {
  const _Countdown({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: EventCategory.holiday.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
    );
  }
}
