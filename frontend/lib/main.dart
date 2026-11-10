import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/calendar_api.dart';
import 'services/followed_clubs.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One CalendarApi serves both the academic calendar and TigerLink club events.
  final api = CalendarApi();
  // Load the user's followed clubs from device storage.
  final follows = await PrefsFollowStore.create();
  runApp(
    LsuCalendarApp(repository: api, clubRepository: api, followStore: follows),
  );
}

class LsuCalendarApp extends StatelessWidget {
  const LsuCalendarApp({
    super.key,
    required this.repository,
    this.clubRepository,
    this.followStore,
    this.clock,
  });

  final CalendarRepository repository;
  final ClubRepository? clubRepository;
  final FollowStore? followStore;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LSU Calendar',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Always light, even when the device is in dark mode.
      themeMode: ThemeMode.light,
      home: HomeScreen(
        repository: repository,
        clubRepository: clubRepository,
        followStore: followStore,
        clock: clock,
      ),
    );
  }
}
