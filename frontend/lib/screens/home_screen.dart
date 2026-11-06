import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../models/club_event.dart';
import '../services/calendar_api.dart';
import '../services/followed_clubs.dart';
import '../utils/date_format.dart';
import 'agenda_view.dart';
import 'calendar_view.dart';
import 'clubs_view.dart';
import 'holidays_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    this.clubRepository,
    this.followStore,
    this.clock,
  });

  final CalendarRepository repository;

  /// Club events load from here. Null leaves the Clubs tab unavailable, which
  /// keeps the widget tests that only exercise the academic calendar simple.
  final ClubRepository? clubRepository;

  /// Which clubs the user follows. Defaults to a non-persistent store when the
  /// app doesn't supply one.
  final FollowStore? followStore;

  /// Overridable so tests can pin "today".
  final DateTime Function()? clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CalendarData? _data;
  String? _error;
  bool _loading = true;
  int _tab = 0;
  final Set<EventCategory> _hiddenCategories = {};

  // Club events load lazily the first time the Clubs tab is opened.
  ClubEventsData? _clubData;
  String? _clubError;
  bool _clubLoading = false;
  bool _clubsRequested = false;

  // Falls back to an in-memory store when the app doesn't provide one.
  late final FollowStore _followStore = widget.followStore ?? MemoryFollowStore();

  static const _clubsTab = 3;

  late DateTime _today = dateOnly((widget.clock ?? DateTime.now)());
  late DateTime _focusedMonth = DateTime(_today.year, _today.month);
  late DateTime _selectedDay = _today;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _today = dateOnly((widget.clock ?? DateTime.now)());
    });
    try {
      final data = await widget.repository.fetchCalendar();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      final message = error is CalendarApiException
          ? error.message
          : 'Something went wrong loading the calendar.';
      setState(() => _error = message);
      // Keep showing the calendar we already have; just say the refresh failed.
      if (_data != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadClubs() async {
    final repository = widget.clubRepository;
    if (repository == null) return;
    setState(() {
      _clubLoading = true;
      _clubsRequested = true;
    });
    try {
      final data = await repository.fetchClubEvents();
      if (!mounted) return;
      setState(() {
        _clubData = data;
        _clubError = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      final message = error is CalendarApiException
          ? error.message
          : 'Something went wrong loading club events.';
      setState(() => _clubError = message);
      if (_clubData != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _clubLoading = false);
    }
  }

  void _onTabSelected(int index) {
    setState(() => _tab = index);
    // Fetch club events the first time the tab is opened, not at startup.
    if (index == _clubsTab && !_clubsRequested) _loadClubs();
  }

  bool _isVisible(CalendarEvent event) =>
      !_hiddenCategories.contains(event.category);

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Show categories',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => update(_hiddenCategories.clear),
                        child: const Text('All'),
                      ),
                      TextButton(
                        onPressed: () => update(() {
                          _hiddenCategories
                            ..addAll(EventCategory.values)
                            ..remove(EventCategory.holiday);
                        }),
                        child: const Text('Holidays only'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in EventCategory.values)
                        FilterChip(
                          avatar: Icon(category.icon, color: category.color),
                          label: Text(category.label),
                          selected: !_hiddenCategories.contains(category),
                          onSelected: (selected) => update(() {
                            selected
                                ? _hiddenCategories.remove(category)
                                : _hiddenCategories.add(category);
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = _hiddenCategories.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month),
            SizedBox(width: 10),
            Text('LSU Calendar'),
          ],
        ),
        actions: [
          // The category filter only applies to the academic calendar tabs.
          if (_tab == 0 || _tab == 1)
            IconButton(
              tooltip: 'Filter categories',
              onPressed: _data == null ? null : _openFilters,
              icon: Badge(
                isLabelVisible: filtered,
                backgroundColor: colors.secondary,
                child: const Icon(Icons.filter_list),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _clubLoading
                ? null
                : _tab == _clubsTab
                ? _loadClubs
                : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: (_tab == _clubsTab ? _clubLoading && _clubData != null : _loading && _data != null)
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_view_month_outlined),
            selectedIcon: Icon(Icons.calendar_view_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_agenda_outlined),
            selectedIcon: Icon(Icons.view_agenda),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.beach_access_outlined),
            selectedIcon: Icon(Icons.beach_access),
            label: 'Holidays',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Clubs',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_tab == _clubsTab) return _buildClubsBody();

    final data = _data;
    if (data == null) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final events = data.events.where(_isVisible).toList();
    final view = switch (_tab) {
      0 => CalendarView(
        events: events,
        today: _today,
        focusedMonth: _focusedMonth,
        selectedDay: _selectedDay,
        onMonthChanged: (month) => setState(() => _focusedMonth = month),
        onDaySelected: (day) => setState(() {
          _selectedDay = day;
          _focusedMonth = DateTime(day.year, day.month);
        }),
      ),
      1 => AgendaView(
        events: events,
        unscheduled: data.unscheduled.where(_isVisible).toList(),
        today: _today,
        onRefresh: _load,
      ),
      _ => HolidaysView(
        holidays: [
          for (final event in data.events)
            if (event.category == EventCategory.holiday) event,
        ],
        today: _today,
        onRefresh: _load,
      ),
    };

    return Column(
      children: [
        if (data.stale) const _StaleBanner(),
        Expanded(child: view),
      ],
    );
  }

  Widget _buildClubsBody() {
    if (widget.clubRepository == null) {
      return const _ErrorView(
        message: 'Club events are not available in this build.',
        onRetry: null,
      );
    }
    final data = _clubData;
    if (data == null) {
      if (_clubLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _ErrorView(message: _clubError!, onRetry: _loadClubs);
    }
    return Column(
      children: [
        if (data.stale)
          const _StaleBanner(
            message: "Couldn't reach TigerLink, so events may be out of date.",
          ),
        Expanded(
          child: ClubsView(
            data: data,
            today: _today,
            onRefresh: _loadClubs,
            followStore: _followStore,
          ),
        ),
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({
    this.message =
        "Couldn't reach LSU's site, so some dates may be out of date.",
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 20, color: colors.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              "Couldn't load the calendar",
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
