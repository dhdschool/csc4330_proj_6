import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../theme.dart';
import '../utils/date_format.dart';
import 'event_tile.dart';

Future<void> showEventDetails(BuildContext context, CalendarEvent event) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => EventDetailsSheet(event: event),
  );
}

class EventDetailsSheet extends StatelessWidget {
  const EventDetailsSheet({super.key, required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = event.startDate;
    final end = event.endDate;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CategoryBadge(category: event.category, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.category.label.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: lsuPurple,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(event.title, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
            ],
          ),
          if (event.tentative) ...[
            const SizedBox(height: 12),
            const TentativeChip(),
          ],
          const SizedBox(height: 20),
          _DetailRow(
            icon: Icons.calendar_today,
            label: start == null
                ? 'Date not yet announced (${event.dateText})'
                : end == null || isSameDay(start, end)
                ? formatLongDate(start)
                : '${formatLongDate(start)}\nthrough ${formatLongDate(end)}',
          ),
          if (event.isMultiDay)
            _DetailRow(
              icon: Icons.timelapse,
              label: '${daysBetween(start!, end!) + 1} days',
            ),
          if (event.classesEndAt != null)
            _DetailRow(
              icon: Icons.logout,
              label: 'Classes end at ${formatTime(event.classesEndAt!)}',
            ),
          if (event.classesResumeAt != null)
            _DetailRow(
              icon: Icons.login,
              label: 'Classes resume at ${formatTime(event.classesResumeAt!)}',
            ),
          _DetailRow(icon: Icons.label_outline, label: event.terms.join(', ')),
          _DetailRow(
            icon: Icons.account_balance,
            label: 'Academic year ${event.academicYear}',
          ),
          if (event.description != null) ...[
            const Divider(height: 32),
            Text(event.description!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
