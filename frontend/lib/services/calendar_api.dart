import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/calendar_event.dart';
import '../models/club_event.dart';

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

abstract interface class ClubRepository {
  Future<ClubEventsData> fetchClubEvents();
}

class CalendarApi implements CalendarRepository, ClubRepository {
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

  /// Fetches upcoming club events from TigerLink via the backend.
  ///
  /// The backend sorts ascending and caps the result, so we ask for events
  /// from today onward — otherwise the cap would return only past events.
  @override
  Future<ClubEventsData> fetchClubEvents() async {
    final today = DateTime.now();
    final start =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$baseUrl/api/tigerlink/events').replace(
      queryParameters: {'start': start, 'limit': '1500'},
    );
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 30));
    } on Exception {
      throw CalendarApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
    if (response.statusCode == 503) {
      throw CalendarApiException(
        'TigerLink events are unavailable right now. Try again in a few minutes.',
      );
    }
    if (response.statusCode != 200) {
      throw CalendarApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
    return ClubEventsData.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
