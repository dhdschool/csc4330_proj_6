import 'package:flutter/material.dart';

/// Mirrors the `category` values the backend returns.
enum EventCategory {
  holiday('Holiday', Icons.beach_access, Color(0xFFE0A800)),
  classes('Classes', Icons.school, Color(0xFF461D7C)),
  exam('Exams', Icons.edit_note, Color(0xFFC62828)),
  deadline('Deadline', Icons.alarm, Color(0xFFEF6C00)),
  grades('Grades', Icons.grading, Color(0xFF00897B)),
  registration('Registration', Icons.how_to_reg, Color(0xFF1E88E5)),
  studyPeriod('Study Period', Icons.menu_book, Color(0xFF5E35B1)),
  orientation('Orientation', Icons.waving_hand, Color(0xFF43A047)),
  commencement('Commencement', Icons.celebration, Color(0xFFD81B60)),
  other('Other', Icons.event, Color(0xFF757575));

  const EventCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static EventCategory fromApi(String value) => switch (value) {
    'holiday' => holiday,
    'classes' => classes,
    'exam' => exam,
    'deadline' => deadline,
    'grades' => grades,
    'registration' => registration,
    'study_period' => studyPeriod,
    'orientation' => orientation,
    'commencement' => commencement,
    _ => other,
  };
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.dateText,
    required this.terms,
    required this.academicYear,
    this.description,
    this.startDate,
    this.endDate,
    this.tentative = false,
    this.classesEndAt,
    this.classesResumeAt,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    category: EventCategory.fromApi(json['category'] as String),
    startDate: _parseDate(json['start_date']),
    endDate: _parseDate(json['end_date']),
    dateText: json['date_text'] as String,
    terms: [for (final term in json['terms'] as List) term as String],
    academicYear: json['academic_year'] as String,
    tentative: json['tentative'] as bool? ?? false,
    classesEndAt: json['classes_end_at'] as String?,
    classesResumeAt: json['classes_resume_at'] as String?,
  );

  final String id;
  final String title;
  final String? description;
  final EventCategory category;

  /// Null only for events LSU hasn't dated yet.
  final DateTime? startDate;
  final DateTime? endDate;

  /// The date exactly as LSU wrote it, such as "TBD" or "March 30 - April 3".
  final String dateText;
  final List<String> terms;
  final String academicYear;
  final bool tentative;

  /// 24-hour local times, such as "16:30", for holidays covering part of a day.
  final String? classesEndAt;
  final String? classesResumeAt;

  bool get isScheduled => startDate != null;

  bool get isMultiDay => isScheduled && endDate != startDate;

  bool occursOn(DateTime day) =>
      isScheduled && !day.isBefore(startDate!) && !day.isAfter(endDate!);

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    final parsed = DateTime.parse(value as String);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}

class CalendarData {
  const CalendarData({
    required this.events,
    required this.unscheduled,
    required this.source,
    required this.fetchedAt,
    required this.stale,
  });

  factory CalendarData.fromJson(Map<String, dynamic> json) => CalendarData(
    events: [
      for (final event in json['events'] as List)
        CalendarEvent.fromJson(event as Map<String, dynamic>),
    ],
    unscheduled: [
      for (final event in json['unscheduled'] as List)
        CalendarEvent.fromJson(event as Map<String, dynamic>),
    ],
    source: json['source'] as String,
    fetchedAt: DateTime.parse(json['fetched_at'] as String).toLocal(),
    stale: json['stale'] as bool,
  );

  final List<CalendarEvent> events;
  final List<CalendarEvent> unscheduled;
  final String source;
  final DateTime fetchedAt;

  /// True when the backend's last refresh from LSU failed.
  final bool stale;
}
