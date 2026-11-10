import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../utils/date_format.dart';
import 'event_details_sheet.dart';

class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category, this.size = 40});

  final EventCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Icon(category.icon, color: category.color, size: size * 0.55),
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.trailing});

  final CalendarEvent event;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      event.isScheduled
          ? formatDateRange(event.startDate!, event.endDate!)
          : event.dateText,
      if (event.classesEndAt != null)
        'Classes end ${formatTime(event.classesEndAt!)}',
    ].join(' · ');

    // A flat list row with a divider, rather than a card.
    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: () => showEventDetails(context, event),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  CategoryBadge(category: event.category, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (event.tentative) ...[
                          const SizedBox(height: 4),
                          const TentativeChip(),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                  Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                ],
              ),
            ),
            const Divider(indent: 64),
          ],
        ),
      ),
    );
  }
}

class TentativeChip extends StatelessWidget {
  const TentativeChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'TENTATIVE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
