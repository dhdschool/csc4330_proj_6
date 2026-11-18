import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_cookie_manager_flutter/webview_cookie_manager.dart';

import "../models/moodle_event.dart";

class MoodleApiException implements Exception {
  MoodleApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where the app keeps the session ID the backend gives it at sign-in. The
/// backend only shares a user's Moodle data with requests carrying their ID.
abstract class MoodleSessionStore {
  Future<String?> read();
  Future<void> write(String? sessionId);
}

/// Keeps the session ID on the device, so reopening the app stays signed in.
class PrefsMoodleSessionStore implements MoodleSessionStore {
  static const _key = 'moodle_session';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String? sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sessionId == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, sessionId);
    }
  }
}

/// A non-persistent store, used as the default and in tests.
class MemoryMoodleSessionStore implements MoodleSessionStore {
  MemoryMoodleSessionStore([this._sessionId]);

  String? _sessionId;

  @override
  Future<String?> read() async => _sessionId;

  @override
  Future<void> write(String? sessionId) async => _sessionId = sessionId;
}

class MoodleService extends ChangeNotifier {
  final http.Client client;
  final String baseUrl;
  final MoodleSessionStore _sessionStore;

  /// How long to wait for the backend, which in turn waits on Moodle. Without
  /// a limit, a slow Moodle leaves the app on its loading screen.
  final Duration timeout;

  MoodleService({
    required this.client,
    required this.baseUrl,
    MoodleSessionStore? sessionStore,
    this.timeout = const Duration(seconds: 30),
  }) : _sessionStore = sessionStore ?? MemoryMoodleSessionStore();

  final WebviewCookieManager _cookieManager = WebviewCookieManager();
  String _sessionToken = "";
  bool _signedIn = false;

  /// Whether the backend holds a working Moodle session. Updated by
  /// [isAuthorized], a successful login, and [signOut]. Listeners are notified
  /// when a login succeeds or the user signs out.
  bool get signedIn => _signedIn;

  /// `Authorization: Bearer <session>` once signed in, so the backend knows
  /// whose Moodle data to use.
  Future<Map<String, String>> _authHeaders() async {
    final sessionId = await _sessionStore.read();
    return sessionId == null ? {} : {'Authorization': 'Bearer $sessionId'};
  }

  /// Sends a request with the session header and timeout, turning network
  /// failures into a [MoodleApiException].
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    try {
      return await request(await _authHeaders()).timeout(timeout);
    } on Exception {
      throw MoodleApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
  }

  /// Ends the Moodle session on the backend and forgets it on this device.
  Future<void> signOut() async {
    final http.Response response;
    try {
      response = await _send(
        (headers) => client.post(
          Uri.parse('$baseUrl/api/moodle/logout'),
          headers: headers,
        ),
      );
    } finally {
      // Sign out on this device even if the server couldn't be reached.
      await _forgetSession();
    }
    if (response.statusCode != 200) {
      throw MoodleApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
  }

  Future<void> _forgetSession() async {
    await _sessionStore.write(null);
    _sessionToken = "";
    _signedIn = false;
    // Drop the webview's Moodle cookie so the next sign-in can be a
    // different account.
    if (!kIsWeb) {
      try {
        await _cookieManager.clearCookies();
      } on Exception catch (error) {
        debugPrint("Couldn't clear Moodle cookies: $error");
      }
    }
    notifyListeners();
  }

  Future<void> handleUrlChange({required String? url}) async {
    List<Cookie> cookies = await _cookieManager.getCookies(url);
    for (Cookie cookie in cookies) {
      if (cookie.name == "MoodleSessionlsumoodle4" &&
          cookie.value != _sessionToken) {
        // New session token found
        _sessionToken = cookie.value;
        await dispatchSessionToken();
        break;
      }
    }
  }

  Future<LoginResponse> dispatchSessionToken() async {
    final response = await _send(
      (headers) => client.post(
        Uri.parse('$baseUrl/api/moodle/login'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'token': _sessionToken,
          'backend_login': kIsWeb,
        }),
      ),
    );
    if (response.statusCode == 503) {
      throw MoodleApiException(
        "Moodle's api is unavailable right now. Try again in a few minutes.",
      );
    }
    if (response.statusCode != 200) {
      throw MoodleApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
    final loginResponse = LoginResponse.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );

    if (loginResponse.success) {
      await _sessionStore.write(loginResponse.session);
      _signedIn = true;
      notifyListeners();
    }

    return loginResponse;
  }

  /// The user's Moodle deadlines and sessions, or null when they haven't
  /// logged in to Moodle (or the session expired).
  Future<MoodleEventsData?> fetchEvents() async {
    final response = await _send(
      (headers) => client.get(
        Uri.parse('$baseUrl/api/moodle/events'),
        headers: headers,
      ),
    );
    if (response.statusCode == 401) {
      // The backend dropped the session (for example, Moodle expired it).
      await _sessionStore.write(null);
      return null;
    }
    if (response.statusCode == 503) {
      throw MoodleApiException(
        "Moodle's calendar is unavailable right now. Try again in a few minutes.",
      );
    }
    if (response.statusCode != 200) {
      throw MoodleApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
    return MoodleEventsData.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<IsAuthorizedResponse> isAuthorized() async {
    final response = await _send(
      (headers) => client.get(
        Uri.parse('$baseUrl/api/moodle/authorized'),
        headers: headers,
      ),
    );
    if (response.statusCode == 503) {
      throw MoodleApiException(
        "Moodle's api is unavailable right now. Try again in a few minutes.",
      );
    }
    if (response.statusCode != 200) {
      throw MoodleApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
    final authorized = IsAuthorizedResponse.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
    _signedIn = authorized.authorized;
    // A session the backend no longer knows is useless; don't keep sending it.
    if (!authorized.authorized) await _sessionStore.write(null);
    return authorized;
  }
}
