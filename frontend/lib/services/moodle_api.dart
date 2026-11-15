import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webview_cookie_manager_flutter/webview_cookie_manager.dart';

import "../models/moodle_event.dart";

class MoodleApiException implements Exception {
  MoodleApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MoodleService extends ChangeNotifier {
  final http.Client client; 
  final String baseUrl;

  MoodleService({
    required this.client,
    required this.baseUrl   
  });

  final WebviewCookieManager _cookieManager = WebviewCookieManager();
  String _sessionToken = "";
  bool _signedIn = false;

  /// Whether the backend holds a working Moodle session. Updated by
  /// [isAuthorized], a successful login, and [signOut]. Listeners are notified
  /// when a login succeeds or the user signs out.
  bool get signedIn => _signedIn;

  /// Ends the Moodle session on the backend and forgets it on this device.
  Future<void> signOut() async {
    final http.Response response;
    try {
      response = await client.post(Uri.parse('$baseUrl/api/moodle/logout'));
    } on Exception {
      throw MoodleApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
    if (response.statusCode != 200) {
      throw MoodleApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
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
    for (Cookie cookie in cookies){
      if(cookie.name == "MoodleSessionlsumoodle4" && cookie.value != _sessionToken){
        // New session token found
        _sessionToken = cookie.value;
        await dispatchSessionToken();
        break;
      }
    }
  }

  Future<LoginResponse> dispatchSessionToken() async {
    final http.Response response;

    try{
      response = await client.post(
        Uri.parse('$baseUrl/api/moodle/login'),
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'token': _sessionToken,
          'backend_login': kIsWeb
        })
      );
    } on Exception {
      throw MoodleApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
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
    final loginResponse =  LoginResponse.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );

    if (loginResponse.success){
      _signedIn = true;
      notifyListeners();
    }

    return loginResponse;
  }

  /// The user's Moodle deadlines and sessions, or null when they haven't
  /// logged in to Moodle (or the session expired).
  Future<MoodleEventsData?> fetchEvents() async {
    final http.Response response;
    try {
      response = await client
          .get(Uri.parse('$baseUrl/api/moodle/events'))
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw MoodleApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
    if (response.statusCode == 401) return null;
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
    final http.Response response;

    try {
      response = await client.get(Uri.parse('$baseUrl/api/moodle/authorized'));
    } catch (e) { 
      throw MoodleApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
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
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic> 
    );
    _signedIn = authorized.authorized;
    return authorized;
  }
} 
