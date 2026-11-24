import 'package:flutter/material.dart';
import 'package:frontend/services/moodle_api.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'screens/auth_gate.dart';
import 'screens/home_screen.dart';
import 'services/calendar_api.dart';
import 'services/followed_clubs.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  http.Client client = http.Client();
  String baseUrl = defaultBackendUrl();
  // One CalendarApi serves both the academic calendar and TigerLink club events.
  final api = CalendarApi(client: client, baseUrl: baseUrl);
  // Moodle sign-in; the session ID is kept on the device so reopening the app
  // stays signed in.
  final moodle = MoodleService(
    client: client,
    baseUrl: baseUrl,
    sessionStore: PrefsMoodleSessionStore(),
  );
  // Club choices saved on the device: followed clubs, events marked "Going",
  // and the personal TigerLink calendar link.
  final follows = await PrefsFollowStore.create();
  final going = await PrefsGoingStore.create();
  final personalFeed = await PrefsPersonalFeedStore.create();
  runApp(
    LsuCalendarApp(
      repository: api,
      clubRepository: api,
      moodleService: moodle,
      followStore: follows,
      goingStore: going,
      personalFeedStore: personalFeed,
    ),
  );
}

class LsuCalendarApp extends StatelessWidget {
  LsuCalendarApp({
    super.key,
    required this.repository,
    this.clubRepository,
    required this.moodleService,
    this.followStore,
    GoingStore? goingStore,
    PersonalFeedStore? personalFeedStore,
    this.clock,
  }) : goingStore = goingStore ?? MemoryGoingStore(),
       personalFeedStore = personalFeedStore ?? MemoryPersonalFeedStore();

  final CalendarRepository repository;
  final ClubRepository? clubRepository;
  final MoodleService moodleService;
  final FollowStore? followStore;
  final GoingStore goingStore;
  final PersonalFeedStore personalFeedStore;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    // Above MaterialApp so bottom sheets (club event details, with their
    // Register button) can reach the "Going" list from any screen.
    return ChangeNotifierProvider<GoingStore>.value(
      value: goingStore,
      child: MaterialApp(
        title: 'LSU Calendar',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Always light, even when the device is in dark mode.
        themeMode: ThemeMode.light,
        // Opens to the Moodle sign-in screen unless already signed in.
        home: AuthGate(
          moodleService: moodleService,
          homeBuilder: (context, requestSignIn) => HomeScreen(
            repository: repository,
            clubRepository: clubRepository,
            moodleService: moodleService,
            followStore: followStore,
            goingStore: goingStore,
            personalFeedStore: personalFeedStore,
            clock: clock,
            onSignInRequested: requestSignIn,
          ),
        ),
      ),
    );
  }
}
