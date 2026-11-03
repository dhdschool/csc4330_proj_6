import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../utils/date_format.dart';
import '../widgets/event_tile.dart';

/// Events in date order, grouped by month, with undated events at the end.
class AgendaView extends StatefulWidget {
  const AgendaView({
    super.key,
    required this.events,
    required this.unscheduled,
    required this.today,
    required this.onRefresh,
  });

  final List<CalendarEvent> events;
  final List<CalendarEvent> unscheduled;
  final DateTime today;
  final Future<void> Function() onRefresh;

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = _showPast
        ? widget.events
        : [
            for (final event in widget.events)
              if (!event.endDate!.isBefore(widget.today)) event,
          ];

    // Flatten into one list so ListView.builder can build rows lazily.
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${events.length} events',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilterChip(
              label: const Text('Show past'),
              selected: _showPast,
              onSelected: (value) => setState(() => _showPast = value),
            ),
          ],
        ),
      ),
    ];
    DateTime? currentMonth;
    for (final event in events) {
      final start = event.startDate!;
      if (currentMonth == null ||
          currentMonth.year != start.year ||
          currentMonth.month != start.month) {
        currentMonth = DateTime(start.year, start.month);
        rows.add(
          _SectionHeader('${monthNames[start.month - 1]} ${start.year}'),
        );
      }
      rows.add(
        EventTile(
          event: event,
          trailing: _DateBox(date: start, today: widget.today),
        ),
      );
    }
    if (events.isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No events match your filters.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (widget.unscheduled.isNotEmpty) {
      rows.add(const _SectionHeader('Dates to be announced'));
      rows.addAll([
        for (final event in widget.unscheduled) EventTile(event: event),
      ]);
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: rows.length,
            itemBuilder: (context, index) => rows[index],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// A small "NOV / 26" block, highlighted when the date is today.
class _DateBox extends StatelessWidget {
  const _DateBox({required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = isSameDay(date, today);
    final color = isToday
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 44,
      child: Column(
        children: [
          Text(
            shortWeekday(date).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
          Text(
            '${date.day}',
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
