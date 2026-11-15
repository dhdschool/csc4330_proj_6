import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/calendar_event.dart';
import 'package:frontend/services/calendar_api.dart';
import 'package:frontend/services/moodle_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _EmptyCalendar implements CalendarRepository {
  @override
  Future<CalendarData> fetchCalendar() async => CalendarData.fromJson({
    'events': [],
    'unscheduled': [],
    'source': 'https://lsu.edu',
    'fetched_at': '2026-11-01T00:00:00Z',
    'stale': false,
  });
}

/// A fake backend whose Moodle session can be switched on and off.
class _FakeBackend {
  _FakeBackend({required this.signedIn});

  bool signedIn;
  final requests = <String>[];

  late final client = MockClient((request) async {
    requests.add(request.url.path);
    switch (request.url.path) {
      case '/api/moodle/authorized':
        return http.Response(
          jsonEncode({
            'authorized': signedIn,
            'login_url': signedIn ? null : 'https://moodle.lsu.edu/login',
          }),
          200,
        );
      case '/api/moodle/events':
        if (!signedIn) return http.Response('', 401);
        return http.Response(
          jsonEncode({
            'events': [
              {
                'id': 'a1',
                'title': 'Assignment 4 is due',
                // Noon UTC is the same calendar day in nearly every zone.
                'start': '2026-11-20T12:00:00Z',
                'end': '2026-11-20T12:00:00Z',
                'all_day': false,
                'course': 'CSC 4501',
              },
            ],
            'fetched_at': '2026-11-15T00:00:00Z',
          }),
          200,
        );
      case '/api/moodle/logout':
        signedIn = false;
        return http.Response(jsonEncode({'success': true}), 200);
    }
    return http.Response('', 404);
  });
}

Future<_FakeBackend> _pumpApp(WidgetTester tester, {required bool signedIn}) async {
  final backend = _FakeBackend(signedIn: signedIn);
  await tester.pumpWidget(
    LsuCalendarApp(
      repository: _EmptyCalendar(),
      moodleService: MoodleService(
        client: backend.client,
        baseUrl: 'http://backend.test',
      ),
      clock: () => DateTime(2026, 11, 20, 9),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 2400);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.5;
    // Signing out clears the webview's cookies; answer that platform call,
    // which otherwise never completes in a widget test.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('webview_cookie_manager'),
      (call) async => null,
    );
  });

  testWidgets('opens to the sign-in screen, and skipping shows the calendar', (
    tester,
  ) async {
    await _pumpApp(tester, signedIn: false);

    expect(find.text('Sign in with Moodle'), findsOneWidget);
    expect(find.text('ACADEMIC CALENDAR'), findsNothing);

    await tester.tap(find.text('Continue without signing in'));
    await tester.pumpAndSettle();

    expect(find.text('ACADEMIC CALENDAR'), findsOneWidget);
    // Only three tabs now that Moodle sign-in has its own screen.
    expect(find.byType(NavigationDestination), findsNWidgets(3));

    // The account menu can bring the sign-in screen back.
    await tester.tap(find.byTooltip('Moodle account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with Moodle'));
    await tester.pumpAndSettle();
    expect(find.text('Continue without signing in'), findsOneWidget);
  });

  testWidgets('a signed-in user goes straight to their Moodle deadlines', (
    tester,
  ) async {
    final backend = await _pumpApp(tester, signedIn: true);

    expect(find.text('Sign in with Moodle'), findsNothing);
    expect(backend.requests, contains('/api/moodle/events'));
    expect(find.text('Assignment 4 is due'), findsOneWidget);
  });

  testWidgets('signing out returns to the sign-in screen', (tester) async {
    final backend = await _pumpApp(tester, signedIn: true);

    await tester.tap(find.byTooltip('Moodle account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of Moodle'));
    await tester.pumpAndSettle();

    expect(backend.requests, contains('/api/moodle/logout'));
    expect(find.text('Continue without signing in'), findsOneWidget);
  });
}
