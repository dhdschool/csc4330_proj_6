import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/club_event.dart';

/// Map pieces for club events, drawn with OpenStreetMap tiles (no API key).
class CampusMap {
  CampusMap._();

  /// Roughly the middle of campus, between the Union and the Quad.
  static const center = LatLng(30.4125, -91.1785);

  /// Widget tests turn tiles off, since they can't load network images.
  static bool showTiles = true;

  /// The base map layers every map in the app shares: tiles plus the
  /// attribution OpenStreetMap's tile policy requires.
  static List<Widget> baseLayers() => [
    if (showTiles)
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.frontend',
      ),
    const _Attribution(),
  ];
}

/// "© OpenStreetMap" in the corner, linking to OSM's copyright page. Smaller
/// than flutter_map's built-in label, which overflows on narrow maps.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: GestureDetector(
        onTap: () =>
            _open(Uri.parse('https://www.openstreetmap.org/copyright')),
        child: Container(
          color: Colors.white.withValues(alpha: 0.8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: const Text(
            '© OpenStreetMap',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}

Future<void> _open(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens directions to the event in the device's maps app (or the browser).
/// Uses coordinates for campus buildings, and the address text otherwise.
Future<void> openDirections(ClubEvent event) {
  final destination = event.hasCoordinates
      ? '${event.latitude},${event.longitude}'
      : '${event.venue}, Baton Rouge, LA';
  return _open(
    Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
    }),
  );
}

/// Opens the event's TigerLink page.
Future<void> openOnTigerLink(ClubEvent event) => _open(Uri.parse(event.url!));

/// A pin in LSU purple, optionally with a count of events at that spot.
class _Pin extends StatelessWidget {
  const _Pin({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(Icons.location_on, size: 44, color: colors.primary),
        if (count != null && count! > 1)
          Positioned(
            top: -2,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: colors.onSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small, non-interactive map with one pin, for the event details sheet.
class EventMapPreview extends StatelessWidget {
  const EventMapPreview({super.key, required this.event});

  final ClubEvent event;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(event.latitude!, event.longitude!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 170,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 16.5,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
            onTap: (_, _) => openDirections(event),
          ),
          children: [
            ...CampusMap.baseLayers(),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: const _Pin(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A campus map with one pin per building, for the Clubs tab's map mode.
/// Tapping a pin lists that building's events.
class ClubsMapView extends StatelessWidget {
  const ClubsMapView({
    super.key,
    required this.events,
    required this.onEventTap,
  });

  /// The events currently shown in the list; only those with coordinates
  /// get pins.
  final List<ClubEvent> events;
  final void Function(ClubEvent event) onEventTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group by coordinates, so all the Union's rooms share one pin.
    final byPlace = <String, List<ClubEvent>>{};
    for (final event in events) {
      if (!event.hasCoordinates) continue;
      byPlace
          .putIfAbsent('${event.latitude},${event.longitude}', () => [])
          .add(event);
    }
    final mapped = byPlace.values.fold<int>(0, (sum, list) => sum + list.length);
    final unmapped = events.length - mapped;

    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: CampusMap.center,
            initialZoom: 15.4,
            minZoom: 11,
            maxZoom: 19,
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            ...CampusMap.baseLayers(),
            MarkerLayer(
              markers: [
                for (final group in byPlace.values)
                  Marker(
                    point: LatLng(group.first.latitude!, group.first.longitude!),
                    width: 52,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      button: true,
                      label: '${group.first.place}, ${group.length} events',
                      child: GestureDetector(
                        key: ValueKey('pin-${group.first.place}'),
                        onTap: () => _showPlace(context, group),
                        child: _Pin(count: group.length),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                unmapped == 0
                    ? '$mapped events on the map'
                    : '$mapped on the map · $unmapped without a campus '
                          'location (often only shown on TigerLink after '
                          'sign-in)',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPlace(BuildContext context, List<ClubEvent> group) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    group.first.place ?? 'Events here',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final event in group)
                        ListTile(
                          title: Text(event.title),
                          subtitle: Text(
                            [
                              _shortDate(event.start),
                              if (event.venue != null) event.venue!,
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).pop();
                            onEventTap(event);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Tue, Nov 10, 6:00 PM"
String _shortDate(DateTime t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '${_weekdays[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}, '
      '$hour12:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}
