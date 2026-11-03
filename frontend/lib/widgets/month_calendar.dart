import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../utils/date_format.dart';

/// A Sunday-first month grid. Days with events show a dot per category, and
/// holidays are shaded gold so breaks stand out at a glance.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.eventsForDay,
    required this.onDaySelected,
    required this.onMonthChanged,
  });

  /// Any date in the month to show.
  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;
  final List<CalendarEvent> Function(DateTime day) eventsForDay;
  final ValueChanged<DateTime> onDaySelected;

  /// Called with the first day of the month to move to.
  final ValueChanged<DateTime> onMonthChanged;

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  void _shiftMonth(int delta) =>
      onMonthChanged(DateTime(month.year, month.month + delta));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month);
    // DateTime.weekday is 1 (Mon) to 7 (Sun); shift so the grid starts on Sunday.
    final gridStart = DateTime(first.year, first.month, 1 - first.weekday % 7);
    final showingThisMonth =
        today.year == month.year && today.month == month.month;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 200) _shiftMonth(velocity < 0 ? 1 : -1);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${monthNames[month.month - 1]} ${month.year}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!showingThisMonth)
                  TextButton(
                    onPressed: () {
                      onMonthChanged(DateTime(today.year, today.month));
                      onDaySelected(today);
                    },
                    child: const Text('Today'),
                  ),
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final label in _weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                for (var week = 0; week < 6; week++)
                  Row(
                    children: [
                      for (var weekday = 0; weekday < 7; weekday++)
                        Expanded(
                          child: _buildDay(
                            context,
                            DateTime(
                              gridStart.year,
                              gridStart.month,
                              gridStart.day + week * 7 + weekday,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDay(BuildContext context, DateTime day) {
    final colors = Theme.of(context).colorScheme;
    final events = eventsForDay(day);
    final inMonth = day.month == month.month;
    final isToday = isSameDay(day, today);
    final isSelected = isSameDay(day, selectedDay);
    final isHoliday = events.any((e) => e.category == EventCategory.holiday);
    final categories = {for (final event in events) event.category}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final Color? background;
    if (isSelected) {
      background = colors.primary;
    } else if (isHoliday) {
      background = EventCategory.holiday.color.withValues(
        alpha: inMonth ? 0.22 : 0.08,
      );
    } else {
      background = null;
    }
    final foreground = isSelected
        ? colors.onPrimary
        : inMonth
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        selected: isSelected,
        label:
            '${formatLongDate(day)}, '
            '${events.isEmpty ? 'no events' : '${events.length} events'}',
        child: Material(
          color: background ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isToday && !isSelected
                ? BorderSide(color: colors.primary, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onDaySelected(day),
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: isToday || isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final category in categories.take(4))
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? colors.onPrimary
                                  : category.color.withValues(
                                      alpha: inMonth ? 1 : 0.4,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
