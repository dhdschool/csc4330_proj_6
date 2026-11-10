import 'package:flutter/material.dart';

import '../models/club_event.dart';
import '../services/followed_clubs.dart';
import '../utils/date_format.dart';
import '../widgets/club_event_tile.dart';
import '../widgets/section_header.dart';

/// Upcoming club events from TigerLink. Defaults to events from clubs the user
/// follows; a "Browse all" mode and a club picker let them discover more.
class ClubsView extends StatefulWidget {
  const ClubsView({
    super.key,
    required this.data,
    required this.today,
    required this.onRefresh,
    required this.followStore,
  });

  final ClubEventsData data;
  final DateTime today;
  final Future<void> Function() onRefresh;
  final FollowStore followStore;

  @override
  State<ClubsView> createState() => _ClubsViewState();
}

class _ClubsViewState extends State<ClubsView> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _type; // null means "all types"
  bool _showAll = false; // false = Following, true = Browse all

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Upcoming events matching the search box and type chip, and — unless we're
  /// in "Browse all" mode — limited to clubs the user follows.
  List<ClubEvent> get _visible {
    final query = _search.trim().toLowerCase();
    final following = widget.followStore.clubs;
    return [
      for (final event in widget.data.events)
        if (!event.day.isBefore(widget.today) &&
            (_type == null || event.eventType == _type) &&
            (_showAll ||
                (event.club != null && following.contains(event.club))) &&
            (query.isEmpty ||
                event.title.toLowerCase().contains(query) ||
                (event.club ?? '').toLowerCase().contains(query)))
          event,
    ];
  }

  Future<void> _openClubPicker() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ClubPicker(
        data: widget.data,
        today: widget.today,
        followStore: widget.followStore,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the followed-clubs selection changes.
    return AnimatedBuilder(
      animation: widget.followStore,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final events = _visible;
    final types = widget.data.eventTypes;
    final followCount = widget.followStore.clubs.length;

    final rows = <Widget>[];
    DateTime? currentDay;
    for (final event in events) {
      if (currentDay == null || !isSameDay(currentDay, event.day)) {
        currentDay = event.day;
        rows.add(_DayHeader(day: currentDay, today: widget.today));
      }
      final club = event.club;
      rows.add(
        ClubEventTile(
          event: event,
          following: club != null && widget.followStore.isFollowing(club),
          onToggleFollow: club == null
              ? null
              : () => widget.followStore.toggle(club),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(
                        followCount == 0
                            ? 'Following'
                            : 'Following ($followCount)',
                      ),
                      icon: const Icon(Icons.star, size: 18),
                    ),
                    const ButtonSegment(
                      value: true,
                      label: Text('All'),
                      icon: Icon(Icons.public, size: 18),
                    ),
                  ],
                  selected: {_showAll},
                  onSelectionChanged: (s) => setState(() => _showAll = s.first),
                ),
              ),
              IconButton(
                tooltip: 'Follow clubs',
                onPressed: _openClubPicker,
                icon: const Icon(Icons.group_add_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search events or clubs',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _search = '';
                        _searchController.clear();
                      }),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('All'),
                  selected: _type == null,
                  onSelected: (_) => setState(() => _type = null),
                ),
              ),
              for (final type in types)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(type),
                    selected: _type == type,
                    onSelected: (selected) =>
                        setState(() => _type = selected ? type : null),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${events.length} upcoming',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: events.isEmpty
                ? _EmptyState(
                    showAll: _showAll,
                    following: followCount > 0,
                    onBrowse: () => setState(() => _showAll = true),
                    onPickClubs: _openClubPicker,
                  )
                : Center(
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
          ),
        ),
      ],
    );
  }
}

/// Shown when no events match. The message and action depend on whether the
/// user follows any clubs yet.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.showAll,
    required this.following,
    required this.onBrowse,
    required this.onPickClubs,
  });

  final bool showAll;
  final bool following;
  final VoidCallback onBrowse;
  final VoidCallback onPickClubs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noFollowsYet = !showAll && !following;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 56, 40, 40),
          child: Column(
            children: [
              Icon(
                noFollowsYet ? Icons.star_border : Icons.event_busy,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                noFollowsYet
                    ? "You're not following any clubs yet"
                    : 'No upcoming events match your filters.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (noFollowsYet) ...[
                const SizedBox(height: 8),
                Text(
                  'Follow clubs to see their events here, or browse everything '
                  'happening on campus.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onPickClubs,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Follow clubs'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onBrowse,
                  child: const Text('Browse all events'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A searchable list of every club in the feed, with a follow toggle and a
/// count of each club's upcoming events.
class _ClubPicker extends StatefulWidget {
  const _ClubPicker({
    required this.data,
    required this.today,
    required this.followStore,
  });

  final ClubEventsData data;
  final DateTime today;
  final FollowStore followStore;

  @override
  State<_ClubPicker> createState() => _ClubPickerState();
}

class _ClubPickerState extends State<_ClubPicker> {
  final _controller = TextEditingController();
  String _search = '';

  late final Map<String, int> _upcomingByClub = _countUpcoming();

  Map<String, int> _countUpcoming() {
    final counts = <String, int>{};
    for (final event in widget.data.events) {
      final club = event.club;
      if (club == null || event.day.isBefore(widget.today)) continue;
      counts[club] = (counts[club] ?? 0) + 1;
    }
    return counts;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _search.trim().toLowerCase();
    final clubs = [
      for (final club in widget.data.clubs)
        if (query.isEmpty || club.toLowerCase().contains(query)) club,
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text('Follow clubs', style: theme.textTheme.titleLarge),
              ),
              TextField(
                controller: _controller,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search ${widget.data.clubs.length} clubs',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: AnimatedBuilder(
                  animation: widget.followStore,
                  builder: (context, _) => clubs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No clubs match your search.'),
                        )
                      : ListView.builder(
                          itemCount: clubs.length,
                          itemBuilder: (context, index) {
                            final club = clubs[index];
                            final following = widget.followStore.isFollowing(
                              club,
                            );
                            final count = _upcomingByClub[club] ?? 0;
                            return ListTile(
                              title: Text(club),
                              subtitle: Text(
                                count == 1
                                    ? '1 upcoming event'
                                    : '$count upcoming events',
                              ),
                              trailing: IconButton(
                                tooltip: following ? 'Unfollow' : 'Follow',
                                icon: Icon(
                                  following ? Icons.star : Icons.star_border,
                                  color: following
                                      ? theme.colorScheme.primary
                                      : null,
                                ),
                                onPressed: () =>
                                    widget.followStore.toggle(club),
                              ),
                              onTap: () => widget.followStore.toggle(club),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final label = isSameDay(day, today)
        ? 'Today · ${formatDateRange(day, day, withYear: false)}'
        : formatDateRange(day, day);
    return SectionHeader(label);
  }
}
