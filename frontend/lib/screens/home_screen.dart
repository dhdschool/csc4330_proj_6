import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/models/moodle_event.dart';

import '../models/calendar_event.dart';
import '../models/club_event.dart';
import '../services/calendar_api.dart';
import '../services/followed_clubs.dart';
import '../services/moodle_api.dart';
import '../theme.dart';
import '../utils/date_format.dart';
import '../widgets/next_break_banner.dart';
import 'agenda_view.dart';
import 'calendar_view.dart';
import 'clubs_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    this.clubRepository,
    required this.moodleService,
    this.followStore,
    this.goingStore,
    this.personalFeedStore,
    this.clock,
    this.onSignInRequested,
  });

  final CalendarRepository repository;

  /// Club events load from here. Null leaves the Clubs tab unavailable, which
  /// keeps the widget tests that only exercise the academic calendar simple.
  final ClubRepository? clubRepository;

  final MoodleService moodleService;

  /// Which clubs the user follows. Defaults to a non-persistent store when the
  /// app doesn't supply one.
  final FollowStore? followStore;

  /// Club events marked "Going"; they appear on the calendar.
  final GoingStore? goingStore;

  /// The user's personal TigerLink calendar link, whose events appear on the
  /// calendar.
  final PersonalFeedStore? personalFeedStore;

  /// Overridable so tests can pin "today".
  final DateTime Function()? clock;

  /// Opens the Moodle sign-in screen, for users who skipped it at launch.
  final VoidCallback? onSignInRequested;

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

  // Deadlines and sessions from the user's Moodle courses, shown alongside the
  // academic calendar. Empty until they log in to Moodle.
  List<CalendarEvent> _moodleEvents = const [];

  // Falls back to in-memory stores when the app doesn't provide them.
  late final FollowStore _followStore =
      widget.followStore ?? MemoryFollowStore();
  late final GoingStore _goingStore = widget.goingStore ?? MemoryGoingStore();
  late final PersonalFeedStore _feedStore =
      widget.personalFeedStore ?? MemoryPersonalFeedStore();

  // Events from the personal TigerLink calendar link, if one is saved.
  List<ClubEvent> _personalEvents = const [];

  /// Whether club events belong on the calendar, so they're worth loading
  /// at startup instead of when the Clubs tab is first opened.
  bool get _wantsClubsOnCalendar =>
      _followStore.clubs.isNotEmpty || _goingStore.ids.isNotEmpty;

  static const _clubsTab = 2;
  static const _screenTitles = ['Academic Calendar', 'Agenda', 'Club Events'];

  late DateTime _today = dateOnly((widget.clock ?? DateTime.now)());
  late DateTime _focusedMonth = DateTime(_today.year, _today.month);
  late DateTime _selectedDay = _today;

  @override
  void initState() {
    super.initState();
    _load();
    widget.moodleService.addListener(_moodleListener);
    // Following a club or marking an event "Going" updates the calendar.
    _followStore.addListener(_onClubChoicesChanged);
    _goingStore.addListener(_onClubChoicesChanged);
  }

  @override
  void dispose(){
    widget.moodleService.removeListener(_moodleListener);
    _followStore.removeListener(_onClubChoicesChanged);
    _goingStore.removeListener(_onClubChoicesChanged);
    super.dispose();
  }

  void _onClubChoicesChanged() {
    if (!mounted) return;
    setState(() {});
    // The first follow or "Going" needs the club events loaded.
    if (_wantsClubsOnCalendar && !_clubsRequested) _loadClubs();
  }

  Future<void> _loadPersonalFeed() async {
    final repository = widget.clubRepository;
    final url = _feedStore.url;
    if (repository == null || url == null) {
      if (_personalEvents.isNotEmpty) setState(() => _personalEvents = const []);
      return;
    }
    try {
      final data = await repository.fetchPersonalClubEvents(url);
      if (!mounted) return;
      setState(() => _personalEvents = data.events);
    } on Exception catch (error) {
      // Optional, like Moodle: keep whatever we showed last.
      debugPrint('Personal TigerLink calendar not loaded: $error');
    }
  }

  /// Club events for the calendar: followed clubs, "Going" events, and the
  /// personal TigerLink calendar, each event once, sorted by start.
  List<CalendarEvent> get _clubCalendarEvents {
    final byId = <String, ClubEvent>{};
    for (final event in _clubData?.events ?? const <ClubEvent>[]) {
      final club = event.club;
      if ((club != null && _followStore.isFollowing(club)) ||
          _goingStore.isGoing(event.id)) {
        byId[event.id] = event;
      }
    }
    for (final event in _personalEvents) {
      byId[event.id] = event;
    }
    final events = [
      for (final event in byId.values) CalendarEvent.fromClubEvent(event),
    ]..sort(_compareEvents);
    return events;
  }

  /// Lets the user paste, change or remove their personal TigerLink calendar
  /// link. A new link is checked by loading it before it's saved.
  Future<void> _editPersonalFeed() async {
    final repository = widget.clubRepository;
    if (repository == null) return;
    // Returns the new link, '' to remove it, or null when cancelled.
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PersonalFeedDialog(
        initialUrl: _feedStore.url,
      ),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    if (result.isEmpty) {
      await _feedStore.setUrl(null);
      if (!mounted) return;
      setState(() => _personalEvents = const []);
      messenger.showSnackBar(
        const SnackBar(content: Text('TigerLink calendar link removed.')),
      );
      return;
    }
    try {
      final data = await repository.fetchPersonalClubEvents(result);
      await _feedStore.setUrl(result);
      if (!mounted) return;
      setState(() => _personalEvents = data.events);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Connected: ${data.events.length} events from your TigerLink '
            'calendar.',
          ),
        ),
      );
    } on CalendarApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Orders events by date, then time of day (all-day first).
  static int _compareEvents(CalendarEvent a, CalendarEvent b) {
    final byDate = a.startDate!.compareTo(b.startDate!);
    return byDate != 0
        ? byDate
        : (a.startTime ?? '').compareTo(b.startTime ?? '');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _today = dateOnly((widget.clock ?? DateTime.now)());
    });
    // These run alongside the academic calendar; they never block or fail it.
    unawaited(_loadMoodleEvents());
    unawaited(_loadPersonalFeed());
    if (_wantsClubsOnCalendar && !_clubLoading) unawaited(_loadClubs());
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

  Future<void> _loadMoodleEvents() async {
    try {
      final data = await widget.moodleService.fetchEvents();
      if (!mounted) return;
      setState(() {
        _moodleEvents = [
          for (final event in data?.events ?? const <MoodleEvent>[])
            event.toCalendarEvent(),
        ];
      });
    } on Exception catch (error) {
      // Moodle is optional, so keep whatever we showed last.
      debugPrint('Moodle events not loaded: $error');
    }
  }

  /// Merges Moodle and club events into the academic calendar by date and
  /// time. All lists are sorted; on ties the academic event comes first.
  List<CalendarEvent> _withPersonalEvents(List<CalendarEvent> academic) {
    final extra = [..._moodleEvents, ..._clubCalendarEvents]..sort(_compareEvents);
    if (extra.isEmpty) return academic;

    final merged = <CalendarEvent>[];
    var i = 0, j = 0;
    while (i < academic.length && j < extra.length) {
      merged.add(
        _compareEvents(extra[j], academic[i]) < 0 ? extra[j++] : academic[i++],
      );
    }
    return merged
      ..addAll(academic.skip(i))
      ..addAll(extra.skip(j));
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

  void _moodleListener() {
    if (widget.moodleService.signedIn) {
      _loadMoodleEvents();
    } else {
      setState(() => _moodleEvents = const []);
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.moodleService.signOut();
    } on MoodleApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
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
    final refreshing = _tab == _clubsTab
        ? _clubLoading && _clubData != null
        : _loading && _data != null;

    return Scaffold(
      // A single purple bar naming the screen. Text only: LSU allows icons
      // for utility, never as a logo.
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo/logo.png',
              height: 36,
              semanticLabel: 'LSU Calendar',
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _screenTitles[_tab].toUpperCase(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
          if (widget.moodleService.signedIn ||
              widget.onSignInRequested != null ||
              widget.clubRepository != null)
            PopupMenuButton<void>(
              tooltip: 'Moodle account',
              icon: Icon(
                widget.moodleService.signedIn
                    ? Icons.account_circle
                    : Icons.account_circle_outlined,
              ),
              itemBuilder: (context) => [
                if (widget.moodleService.signedIn)
                  PopupMenuItem(
                    onTap: _signOut,
                    child: const ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('Sign out of Moodle'),
                    ),
                  )
                else if (widget.onSignInRequested != null)
                  PopupMenuItem(
                    onTap: widget.onSignInRequested,
                    child: const ListTile(
                      leading: Icon(Icons.login),
                      title: Text('Sign in with Moodle'),
                    ),
                  ),
                if (widget.clubRepository != null)
                  PopupMenuItem(
                    onTap: _editPersonalFeed,
                    child: ListTile(
                      leading: const Icon(Icons.event_available),
                      title: const Text('TigerLink calendar link'),
                      subtitle: Text(
                        _feedStore.url == null ? 'Not connected' : 'Connected',
                      ),
                    ),
                  ),
              ],
            ),
        ],
        // A thin gold progress line while a refresh runs.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: refreshing
              ? const LinearProgressIndicator(
                  minHeight: 3,
                  color: lsuGold,
                  backgroundColor: Colors.transparent,
                )
              : const SizedBox(height: 3),
        ),
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

    final events = _withPersonalEvents(data.events).where(_isVisible).toList();
    final view = _tab == 0
        ? CalendarView(
            events: events,
            today: _today,
            focusedMonth: _focusedMonth,
            selectedDay: _selectedDay,
            onMonthChanged: (month) => setState(() => _focusedMonth = month),
            onDaySelected: (day) => setState(() {
              _selectedDay = day;
              _focusedMonth = DateTime(day.year, day.month);
            }),
          )
        : AgendaView(
            events: events,
            unscheduled: data.unscheduled.where(_isVisible).toList(),
            today: _today,
            onRefresh: _load,
            nextBreak: NextBreakBanner.findNext(data.events, _today),
          );

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

/// Asks for the personal TigerLink calendar link. Pops with the link, '' to
/// remove the saved one, or null when cancelled.
class _PersonalFeedDialog extends StatefulWidget {
  const _PersonalFeedDialog({required this.initialUrl});

  final String? initialUrl;

  @override
  State<_PersonalFeedDialog> createState() => _PersonalFeedDialogState();
}

class _PersonalFeedDialogState extends State<_PersonalFeedDialog> {
  late final _controller = TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('TigerLink calendar link'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Events you star on TigerLink will show up on your calendar. '
              'Go to tigerlink.lsu.edu/ics_helper, sign in, find "Your '
              'Personal Feed of Events" and tap Copy Link, then paste it '
              'here.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'https://tigerlink.lsu.edu/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This link works like a password to your TigerLink calendar, '
              'so it stays on this device.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initialUrl != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final url = _controller.text.trim();
            if (url.isNotEmpty) Navigator.pop(context, url);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
