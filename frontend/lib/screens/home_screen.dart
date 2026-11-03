import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../services/calendar_api.dart';
import '../utils/date_format.dart';
import 'agenda_view.dart';
import 'calendar_view.dart';
import 'holidays_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, this.clock});

  final CalendarRepository repository;

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
          if (_tab != 2)
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
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _loading && _data != null
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
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
        ],
      ),
    );
  }

  Widget _buildBody() {
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
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

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
                "Couldn't reach LSU's site, so some dates may be out of date.",
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
  final VoidCallback onRetry;

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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
