import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The set of clubs the user has chosen to follow. Notifies listeners when the
/// selection changes so views can rebuild. Implementations persist differently
/// (on-device vs. in-memory for tests).
abstract class FollowStore extends ChangeNotifier {
  Set<String> get clubs;
  bool isFollowing(String club) => clubs.contains(club);
  Future<void> toggle(String club);
}

/// Persists followed clubs on the device with shared_preferences.
class PrefsFollowStore extends FollowStore {
  PrefsFollowStore._(this._prefs, this._clubs);

  static const _key = 'followed_clubs';

  final SharedPreferences _prefs;
  final Set<String> _clubs;

  /// Loads the saved selection. Call once at startup.
  static Future<PrefsFollowStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key) ?? const <String>[];
    return PrefsFollowStore._(prefs, saved.toSet());
  }

  @override
  Set<String> get clubs => UnmodifiableSetView(_clubs);

  @override
  Future<void> toggle(String club) async {
    if (!_clubs.remove(club)) _clubs.add(club);
    notifyListeners();
    await _prefs.setStringList(_key, _clubs.toList()..sort());
  }
}

/// A non-persistent store, used as a fallback and in tests.
class MemoryFollowStore extends FollowStore {
  MemoryFollowStore([Iterable<String> initial = const []])
    : _clubs = initial.toSet();

  final Set<String> _clubs;

  @override
  Set<String> get clubs => UnmodifiableSetView(_clubs);

  @override
  Future<void> toggle(String club) async {
    if (!_clubs.remove(club)) _clubs.add(club);
    notifyListeners();
  }
}

/// Club events the user has marked "Going" (usually by tapping Register).
/// They appear on the calendar even when the user doesn't follow the club.
abstract class GoingStore extends ChangeNotifier {
  Set<String> get ids;
  bool isGoing(String eventId) => ids.contains(eventId);
  Future<void> setGoing(String eventId, bool going);
}

/// Persists "Going" events on the device with shared_preferences.
class PrefsGoingStore extends GoingStore {
  PrefsGoingStore._(this._prefs, this._ids);

  static const _key = 'going_events';

  final SharedPreferences _prefs;
  final Set<String> _ids;

  static Future<PrefsGoingStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsGoingStore._(prefs, (prefs.getStringList(_key) ?? []).toSet());
  }

  @override
  Set<String> get ids => UnmodifiableSetView(_ids);

  @override
  Future<void> setGoing(String eventId, bool going) async {
    final changed = going ? _ids.add(eventId) : _ids.remove(eventId);
    if (!changed) return;
    notifyListeners();
    await _prefs.setStringList(_key, _ids.toList()..sort());
  }
}

/// A non-persistent store, used as a fallback and in tests.
class MemoryGoingStore extends GoingStore {
  MemoryGoingStore([Iterable<String> initial = const []])
    : _ids = initial.toSet();

  final Set<String> _ids;

  @override
  Set<String> get ids => UnmodifiableSetView(_ids);

  @override
  Future<void> setGoing(String eventId, bool going) async {
    final changed = going ? _ids.add(eventId) : _ids.remove(eventId);
    if (changed) notifyListeners();
  }
}

/// The user's personal TigerLink calendar link ("Your Personal Feed of
/// Events" on tigerlink.lsu.edu/ics_helper), whose events appear on the
/// calendar. It works like a password to that calendar, so it's only kept on
/// the device.
abstract class PersonalFeedStore {
  String? get url;
  Future<void> setUrl(String? url);
}

class PrefsPersonalFeedStore implements PersonalFeedStore {
  PrefsPersonalFeedStore._(this._prefs, this._url);

  static const _key = 'tigerlink_personal_feed';

  final SharedPreferences _prefs;
  String? _url;

  static Future<PrefsPersonalFeedStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsPersonalFeedStore._(prefs, prefs.getString(_key));
  }

  @override
  String? get url => _url;

  @override
  Future<void> setUrl(String? url) async {
    _url = url;
    if (url == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, url);
    }
  }
}

class MemoryPersonalFeedStore implements PersonalFeedStore {
  MemoryPersonalFeedStore([this.url]);

  @override
  String? url;

  @override
  Future<void> setUrl(String? url) async => this.url = url;
}
