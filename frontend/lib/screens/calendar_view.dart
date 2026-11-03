import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../utils/date_format.dart';
import '../widgets/event_tile.dart';
import '../widgets/month_calendar.dart';

/// The month grid with the selected day's events below it, or beside it on
/// wide screens.
class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.events,
    required this.today,
    required this.focusedMonth,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  final List<CalendarEvent> events;
  final DateTime today;
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  /// Maps each day to the events on it, expanding multi-day events.
  Map<DateTime, List<CalendarEvent>> _indexByDay() {
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      for (
        var day = event.startDate!;
        !day.isAfter(event.endDate!);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        (byDay[day] ??= []).add(event);
      }
    }
    return byDay;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _indexByDay();
    final calendar = MonthCalendar(
      month: focusedMonth,
      selectedDay: selectedDay,
      today: today,
      eventsForDay: (day) => byDay[day] ?? const [],
      onDaySelected: onDaySelected,
      onMonthChanged: onMonthChanged,
    );
    final dayEvents = byDay[selectedDay] ?? const <CalendarEvent>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(children: [calendar, const _Legend()]),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    _DayHeader(day: selectedDay, today: today),
                    ..._dayEventWidgets(context, dayEvents),
                  ],
                ),
              ),
            ],
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                calendar,
                const _Legend(),
                const Divider(height: 24),
                _DayHeader(day: selectedDay, today: today),
                ..._dayEventWidgets(context, dayEvents),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _dayEventWidgets(
    BuildContext context,
    List<CalendarEvent> dayEvents,
  ) {
    if (dayEvents.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No LSU calendar events on this day.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    return [for (final event in dayEvents) EventTile(event: event)];
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offset = daysBetween(today, day);
    final relative = switch (offset) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text.rich(
        TextSpan(
          children: [
            if (relative != null)
              TextSpan(
                text: '$relative · ',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            TextSpan(text: formatLongDate(day)),
          ],
        ),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  static const _shown = [
    EventCategory.holiday,
    EventCategory.classes,
    EventCategory.exam,
    EventCategory.deadline,
    EventCategory.grades,
    EventCategory.commencement,
  ];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 4,
        children: [
          for (final category in _shown)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: category.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(category.label, style: style),
              ],
            ),
        ],
      ),
    );
  }
}
