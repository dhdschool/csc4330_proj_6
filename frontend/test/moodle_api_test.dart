import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/moodle_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backend that hands out session "s1" and remembers what it was sent.
class _Backend {
  final requests = <http.Request>[];
  int loginStatus = 200;
  bool hang = false;

  late final client = MockClient((request) async {
    requests.add(request);
    if (hang) await Completer<void>().future; // never answers
    switch (request.url.path) {
      case '/api/moodle/login':
        return http.Response(
          jsonEncode({'success': true, 'session': 's1'}),
          loginStatus,
        );
      case '/api/moodle/authorized':
        final signedIn = request.headers['Authorization'] == 'Bearer s1';
        return http.Response(
          jsonEncode({
            'authorized': signedIn,
            'login_url': signedIn ? null : 'https://login.test',
          }),
          200,
        );
      case '/api/moodle/events':
        if (request.headers['Authorization'] != 'Bearer s1') {
          return http.Response('', 401);
        }
        return http.Response(
          jsonEncode({'events': [], 'fetched_at': '2026-11-15T00:00:00Z'}),
          200,
        );
      case '/api/moodle/logout':
        return http.Response(jsonEncode({'success': true}), 200);
    }
    return http.Response('', 404);
  });

  String? authHeaderFor(String path) =>
      requests.lastWhere((r) => r.url.path == path).headers['Authorization'];
}

MoodleService _service(
  _Backend backend, {
  MoodleSessionStore? store,
  Duration timeout = const Duration(seconds: 30),
}) => MoodleService(
  client: backend.client,
  baseUrl: 'http://backend.test',
  sessionStore: store,
  timeout: timeout,
);

/// Stands in for a network failure.
class _NetworkDown implements Exception {
  const _NetworkDown();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // Signing out clears the webview's cookies through this channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('webview_cookie_manager'),
          (call) async => null,
        );
  });

  test('before signing in, requests carry no session', () async {
    final backend = _Backend();
    final result = await _service(backend).isAuthorized();

    expect(result.authorized, isFalse);
    expect(backend.authHeaderFor('/api/moodle/authorized'), isNull);
  });

  test('signing in stores the session and sends it afterwards', () async {
    final backend = _Backend();
    final store = MemoryMoodleSessionStore();
    final service = _service(backend, store: store);

    final login = await service.dispatchSessionToken();
    expect(login.success, isTrue);
    expect(await store.read(), 's1');
    expect(service.signedIn, isTrue);

    expect(await service.fetchEvents(), isNotNull);
    expect(backend.authHeaderFor('/api/moodle/events'), 'Bearer s1');
    expect((await service.isAuthorized()).authorized, isTrue);
  });

  test('a saved session is used after the app restarts', () async {
    final backend = _Backend();
    // A store that already holds the session from an earlier run.
    final service = _service(backend, store: MemoryMoodleSessionStore('s1'));

    expect((await service.isAuthorized()).authorized, isTrue);
    expect(backend.authHeaderFor('/api/moodle/authorized'), 'Bearer s1');
  });

  test('signing out forgets the session on the device', () async {
    final backend = _Backend();
    final store = MemoryMoodleSessionStore('s1');
    final service = _service(backend, store: store);

    await service.signOut();

    expect(backend.authHeaderFor('/api/moodle/logout'), 'Bearer s1');
    expect(await store.read(), isNull);
    expect(service.signedIn, isFalse);
  });

  test('signing out still forgets the session if the server is down', () async {
    final store = MemoryMoodleSessionStore('s1');
    final service = MoodleService(
      client: MockClient((_) async => throw const _NetworkDown()),
      baseUrl: 'http://backend.test',
      sessionStore: store,
    );

    await expectLater(service.signOut(), throwsA(isA<MoodleApiException>()));
    expect(await store.read(), isNull);
  });

  test('a session the backend rejects is dropped', () async {
    final backend = _Backend();
    final store = MemoryMoodleSessionStore('stale');
    final service = _service(backend, store: store);

    expect(await service.fetchEvents(), isNull);
    expect(await store.read(), isNull);
  });

  test('a backend that never answers times out instead of hanging', () async {
    final backend = _Backend()..hang = true;
    final service = _service(
      backend,
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      service.isAuthorized(),
      throwsA(
        isA<MoodleApiException>().having(
          (e) => e.message,
          'message',
          contains("Couldn't reach"),
        ),
      ),
    );
  });

  test('a failed login stores nothing', () async {
    final backend = _Backend()..loginStatus = 503;
    final store = MemoryMoodleSessionStore();

    await expectLater(
      _service(backend, store: store).dispatchSessionToken(),
      throwsA(isA<MoodleApiException>()),
    );
    expect(await store.read(), isNull);
  });

  test('the device store keeps the session across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    await PrefsMoodleSessionStore().write('s1');
    expect(await PrefsMoodleSessionStore().read(), 's1');

    await PrefsMoodleSessionStore().write(null);
    expect(await PrefsMoodleSessionStore().read(), isNull);
  });
}
