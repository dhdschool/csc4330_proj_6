import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/calendar_event.dart';

/// Set with `--dart-define=BACKEND_URL=https://...`. Without it, the app uses
/// the local dev server: the Android emulator reaches the host at 10.0.2.2.
String defaultBackendUrl() {
  const configured = String.fromEnvironment('BACKEND_URL');
  if (configured.isNotEmpty) return configured;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://localhost:8000';
}

class CalendarApiException implements Exception {
  CalendarApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class CalendarRepository {
  Future<CalendarData> fetchCalendar();
}

class CalendarApi implements CalendarRepository {
  CalendarApi({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultBackendUrl(),
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Fetches every event at once; the whole calendar is only a few hundred
  /// rows, so filtering happens on the device.
  @override
  Future<CalendarData> fetchCalendar() async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse('$baseUrl/api/lsu/calendar/events'))
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw CalendarApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
    if (response.statusCode == 503) {
      throw CalendarApiException(
        "LSU's calendar is unavailable right now. Try again in a few minutes.",
      );
    }
    if (response.statusCode != 200) {
      throw CalendarApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
    return CalendarData.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
