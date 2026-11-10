/// A club or organization event from TigerLink.
class ClubEvent {
  const ClubEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.description,
    this.location,
    this.venue,
    this.place,
    this.latitude,
    this.longitude,
    this.url,
    this.club,
    this.clubAcronym,
    this.eventType,
    this.tags = const [],
  });

  factory ClubEvent.fromJson(Map<String, dynamic> json) => ClubEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    // The backend sends UTC; show it in the device's local time.
    start: DateTime.parse(json['start'] as String).toLocal(),
    end: json['end'] == null
        ? null
        : DateTime.parse(json['end'] as String).toLocal(),
    allDay: json['all_day'] as bool? ?? false,
    location: json['location'] as String?,
    venue: json['venue'] as String?,
    place: json['place'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    url: json['url'] as String?,
    club: json['club'] as String?,
    clubAcronym: json['club_acronym'] as String?,
    eventType: json['event_type'] as String?,
    tags: [for (final tag in json['tags'] as List? ?? []) tag as String],
  );

  final String id;
  final String title;
  final String? description;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? location;

  /// The location without TigerLink's default Student Union address, e.g.
  /// "167 Coates Hall". Prefer this for display.
  final String? venue;

  /// The campus building the venue was matched to, if any.
  final String? place;
  final double? latitude;
  final double? longitude;
  final String? url;
  final String? club;
  final String? clubAcronym;
  final String? eventType;
  final List<String> tags;

  DateTime get day => DateTime(start.year, start.month, start.day);

  /// Whether the event can be pinned on the map.
  bool get hasCoordinates => latitude != null && longitude != null;
}

class ClubEventsData {
  const ClubEventsData({
    required this.events,
    required this.source,
    required this.fetchedAt,
    required this.stale,
  });

  factory ClubEventsData.fromJson(Map<String, dynamic> json) => ClubEventsData(
    events: [
      for (final event in json['events'] as List)
        ClubEvent.fromJson(event as Map<String, dynamic>),
    ],
    source: json['source'] as String,
    fetchedAt: DateTime.parse(json['fetched_at'] as String).toLocal(),
    stale: json['stale'] as bool,
  );

  final List<ClubEvent> events;
  final String source;
  final DateTime fetchedAt;

  /// True when the backend's last refresh from TigerLink failed.
  final bool stale;

  /// The distinct event types present, sorted, for building filter chips.
  List<String> get eventTypes {
    final types = {for (final e in events) e.eventType}..remove(null);
    return types.cast<String>().toList()..sort();
  }

  /// The distinct club names present, sorted, for the "follow clubs" picker.
  /// Events with no named club are skipped since there's nothing to follow.
  List<String> get clubs {
    final names = {for (final e in events) e.club}..remove(null);
    return names.cast<String>().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
