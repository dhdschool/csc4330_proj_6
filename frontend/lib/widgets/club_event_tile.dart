import 'package:flutter/material.dart';

import '../models/club_event.dart';
import '../utils/date_format.dart';

/// Maps a TigerLink event type to an icon and color. Unknown types fall back
/// to a neutral default, so new types from the feed still render.
({IconData icon, Color color}) _styleFor(String? type) => switch (type) {
  'Meeting' => (icon: Icons.groups, color: Color(0xFF1E88E5)),
  'Social' => (icon: Icons.celebration, color: Color(0xFFD81B60)),
  'Service' => (icon: Icons.volunteer_activism, color: Color(0xFF43A047)),
  'Spiritual' => (icon: Icons.self_improvement, color: Color(0xFF8E24AA)),
  'Academic/Educational' => (icon: Icons.school, color: Color(0xFF461D7C)),
  'Workshop' => (icon: Icons.build, color: Color(0xFF00897B)),
  'Informational' => (icon: Icons.info, color: Color(0xFF3949AB)),
  'Office Drop-ins' => (icon: Icons.meeting_room, color: Color(0xFF6D4C41)),
  'Fundraiser' => (icon: Icons.attach_money, color: Color(0xFFE0A800)),
  _ => (icon: Icons.event, color: Color(0xFFEF6C00)),
};

/// "3:00 PM" from a local DateTime.
String _clockTime(DateTime time) {
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour12:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

class ClubEventTile extends StatelessWidget {
  const ClubEventTile({
    super.key,
    required this.event,
    this.following = false,
    this.onToggleFollow,
  });

  final ClubEvent event;

  /// Whether the user follows this event's club.
  final bool following;

  /// Toggles following the club. Null when the event has no named club.
  final VoidCallback? onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _styleFor(event.eventType);
    final time = event.allDay ? 'All day' : _clockTime(event.start);
    final subtitle = [time, if (event.club != null) event.club!].join(' · ');

    // A flat list row with a divider, rather than a card.
    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: () => showClubEventDetails(context, event),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(style.icon, color: style.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onToggleFollow != null)
                    IconButton(
                      tooltip: following
                          ? 'Unfollow ${event.club}'
                          : 'Follow ${event.club}',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        following ? Icons.star : Icons.star_border,
                        color: following ? style.color : null,
                        size: 22,
                      ),
                      onPressed: onToggleFollow,
                    ),
                ],
              ),
            ),
            const Divider(indent: 68),
          ],
        ),
      ),
    );
  }
}

Future<void> showClubEventDetails(BuildContext context, ClubEvent event) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ClubEventDetails(event: event),
  );
}

class _ClubEventDetails extends StatelessWidget {
  const _ClubEventDetails({required this.event});

  final ClubEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _styleFor(event.eventType);
    final end = event.end;
    final timeLine = event.allDay
        ? 'All day'
        : end != null && isSameDay(event.start, end)
        ? '${_clockTime(event.start)} – ${_clockTime(end)}'
        : _clockTime(event.start);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.eventType != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, size: 16, color: style.color),
                      const SizedBox(width: 6),
                      Text(
                        event.eventType!,
                        style: TextStyle(
                          color: style.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(event.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              _DetailRow(icon: Icons.event, text: formatLongDate(event.start)),
              _DetailRow(icon: Icons.schedule, text: timeLine),
              if (event.club != null)
                _DetailRow(icon: Icons.groups, text: event.club!),
              if (event.location != null)
                _DetailRow(icon: Icons.place, text: event.location!),
              if (event.description != null) ...[
                const SizedBox(height: 16),
                Text(event.description!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
