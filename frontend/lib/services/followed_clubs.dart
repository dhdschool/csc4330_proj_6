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
