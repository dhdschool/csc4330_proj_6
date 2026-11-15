import 'package:frontend/services/moodle_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A MoodleService for widget tests that never touches the network: any
/// request it makes gets a 503, as if Moodle were down.
MoodleService fakeMoodleService() => MoodleService(
  client: MockClient((_) async => http.Response('', 503)),
  baseUrl: 'http://moodle.test',
);
