import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Local save. One Hive box holding one JSON blob.
///
/// No generated adapters on purpose: the profile is a few kilobytes of plain
/// data, and a hand-written `toJson` keeps the save format visible and
/// versioned in one file instead of spread across codegen output.
class HiveBoxes {
  const HiveBoxes._();

  static const String profileBox = 'profile';
  static const String profileKey = 'player';

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter();
    await Hive.openBox<String>(profileBox);
    _ready = true;
  }

  static Box<String> get _box => Hive.box<String>(profileBox);

  /// The saved profile as raw JSON, or null on a first run.
  static Map<String, dynamic>? read() {
    final raw = _box.get(profileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      // A corrupt save should cost the player their progress, not the app.
      // Better to start fresh than to crash on every launch.
      return null;
    }
  }

  static Future<void> write(Map<String, dynamic> json) =>
      _box.put(profileKey, jsonEncode(json));

  static Future<void> clear() => _box.delete(profileKey);
}
