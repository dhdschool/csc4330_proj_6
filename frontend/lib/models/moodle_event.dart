import 'calendar_event.dart';

class LoginResponse {
  final bool success;

  const LoginResponse({
    required this.success
  });

  factory fromJson(Map<String, dynamic> json) => LoginResponse(
    success: json['success'] as bool
  );
}

class IsAuthorizedResponse{
  final bool authorized; 
  final String? loginUrl;

  const IsAuthorizedResponse({
    required this.authorized,
    this.loginUrl 
  });

  factory fromJson(Map<String, dynamic> json) => IsAuthorizedResponse(
    authorized: json['authorized'] as bool,
    loginUrl: json.containsKey('login_url') ? json['login_url'] : null
  );
}

/// A deadline or session from the user's Moodle calendar export.
class MoodleEvent {
  const MoodleEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.description,
    this.course,
    this.location,
  });

  factory MoodleEvent.fromJson(Map<String, dynamic> json) {
    final allDay = json['all_day'] as bool? ?? false;

    DateTime parseDate(String value) {
      final parsed = DateTime.parse(value);
      // All-day dates arrive at UTC midnight; keep the calendar day as-is.
      // Timed events are instants, so shift them into local time: a 23:59
      // Central deadline is exported as 05:59 UTC the next day.
      return allDay
          ? DateTime(parsed.year, parsed.month, parsed.day)
          : parsed.toLocal();
    }

    return MoodleEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      start: parseDate(json['start'] as String),
      end: json['end'] == null ? null : parseDate(json['end'] as String),
      allDay: allDay,
      course: json['course'] as String?,
      location: json['location'] as String?,
    );
  }

  final String id;
  final String title;
  final String? description;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? course;
  final String? location;

  /// Shapes the event like an academic calendar entry so the calendar and
  /// agenda can show both side by side.
  CalendarEvent toCalendarEvent() {
    final startDay = DateTime(start.year, start.month, start.day);
    var endDay = startDay;
    final e = end;
    if (e != null && e.isAfter(start)) {
      // iCalendar end times are exclusive, so an end at midnight belongs to
      // the day before.
      final last = e.subtract(const Duration(microseconds: 1));
      endDay = DateTime(last.year, last.month, last.day);
    }
    final details = [description, location == null ? null : 'Location: $location']
        .whereType<String>()
        .join('\n\n');

    return CalendarEvent(
      id: 'moodle-$id',
      title: title,
      description: details.isEmpty ? null : details,
      category: EventCategory.moodle,
      startDate: startDay,
      endDate: endDay,
      dateText: '',
      terms: [?course],
      academicYear: '',
      startTime: allDay ? null : _hhmm(start),
      endTime: allDay || e == null || !e.isAfter(start) ? null : _hhmm(e),
    );
  }

  static String _hhmm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

class MoodleEventsData {
  const MoodleEventsData({required this.events, required this.fetchedAt});

  factory MoodleEventsData.fromJson(Map<String, dynamic> json) =>
      MoodleEventsData(
        events: [
          for (final event in json['events'] as List)
            MoodleEvent.fromJson(event as Map<String, dynamic>),
        ],
        fetchedAt: DateTime.parse(json['fetched_at'] as String).toLocal(),
      );

  final List<MoodleEvent> events;
  final DateTime fetchedAt;
}
