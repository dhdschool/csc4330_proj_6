import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/calendar_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _calendarJson = {
  'events': [
    {
      'id': 'a',
      'title': 'Classes begin',
      'category': 'classes',
      'start_date': '2026-08-24',
      'end_date': '2026-08-24',
      'date_text': 'August 24',
      'terms': ['Fall Semester 2026'],
      'academic_year': '2026-2027',
    },
  ],
  'unscheduled': [],
  'source': 'https://www.lsu.edu/registrar',
  'fetched_at': '2026-11-06T12:00:00Z',
  'stale': false,
};

const _clubJson = {
  'events': [
    {
      'id': '1',
      'title': 'Chess Club Meeting',
      'start': '2026-11-20T18:00:00Z',
      'all_day': false,
      'club': 'Chess Club',
      'tags': [],
    },
  ],
  'source': 'https://tigerlink.lsu.edu/events',
  'fetched_at': '2026-11-06T12:00:00Z',
  'stale': false,
};

/// A CalendarApi whose backend answers every request with [status] and [body],
/// recording the requests it receives.
(CalendarApi, List<http.Request>) _api(int status, [Object? body]) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return http.Response(body == null ? '' : jsonEncode(body), status);
  });
  return (CalendarApi(baseUrl: 'http://backend.test', client: client), requests);
}

class _NetworkDown implements Exception {}

void main() {
  group('fetchCalendar', () {
    test('parses the academic calendar', () async {
      final (api, requests) = _api(200, _calendarJson);
      final data = await api.fetchCalendar();

      expect(requests.single.url.path, '/api/lsu/calendar/events');
      expect(data.events.single.title, 'Classes begin');
      expect(data.stale, isFalse);
    });

    test('explains when LSU is unavailable', () async {
      final (api, _) = _api(503);
      await expectLater(
        api.fetchCalendar(),
        throwsA(
          isA<CalendarApiException>().having(
            (e) => e.message,
            'message',
            contains('unavailable right now'),
          ),
        ),
      );
    });

    test('reports other server errors with their status', () async {
      final (api, _) = _api(500);
      await expectLater(
        api.fetchCalendar(),
        throwsA(
          isA<CalendarApiException>().having(
            (e) => e.message,
            'message',
            contains('(500)'),
          ),
        ),
      );
    });

    test('says when the server can\'t be reached', () async {
      final api = CalendarApi(
        baseUrl: 'http://backend.test',
        client: MockClient((_) async => throw _NetworkDown()),
      );
      await expectLater(
        api.fetchCalendar(),
        throwsA(
          isA<CalendarApiException>().having(
            (e) => e.message,
            'message',
            "Couldn't reach the calendar server at http://backend.test.",
          ),
        ),
      );
    });
  });

  group('fetchClubEvents', () {
    test('asks for events from today onward', () async {
      final (api, requests) = _api(200, _clubJson);
      final data = await api.fetchClubEvents();

      final url = requests.single.url;
      final today = DateTime.now();
      final expected =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      expect(url.path, '/api/tigerlink/events');
      // Without a start date the backend's cap would return only past events.
      expect(url.queryParameters['start'], expected);
      expect(url.queryParameters['limit'], '1500');
      expect(data.events.single.club, 'Chess Club');
    });

    test('explains when TigerLink is unavailable', () async {
      final (api, _) = _api(503);
      await expectLater(
        api.fetchClubEvents(),
        throwsA(
          isA<CalendarApiException>().having(
            (e) => e.message,
            'message',
            contains('TigerLink events are unavailable'),
          ),
        ),
      );
    });

    test('reports other server errors with their status', () async {
      final (api, _) = _api(404);
      await expectLater(
        api.fetchClubEvents(),
        throwsA(
          isA<CalendarApiException>().having(
            (e) => e.message,
            'message',
            contains('(404)'),
          ),
        ),
      );
    });

    test('says when the server can\'t be reached', () async {
      final api = CalendarApi(
        baseUrl: 'http://backend.test',
        client: MockClient((_) async => throw _NetworkDown()),
      );
      await expectLater(
        api.fetchClubEvents(),
        throwsA(isA<CalendarApiException>()),
      );
    });
  });

  group('defaultBackendUrl', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the Android emulator reaches the host at 10.0.2.2', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(defaultBackendUrl(), 'http://10.0.2.2:8000');
    });

    test('other platforms use localhost', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(defaultBackendUrl(), 'http://localhost:8000');
    });
  });
}
