import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show rootBundle;

import 'achievements.dart';

/// One leaderboard, and the number it ranks.
///
/// Deliberately thin. Almost everything that decides how a leaderboard
/// behaves — sort order, score format, the allowed range — lives in the Play
/// Console and **cannot be changed after publishing**, so mirroring those
/// here would be a copy that can go stale and that nothing can act on. What
/// this holds is the id to submit to and the number to submit, which are the
/// only two things the app gets a say in.
class Leaderboard {
  const Leaderboard({
    required this.key,
    required this.name,
    required this.androidId,
    required this.iosId,
    required this.source,
  });

  /// Our own stable name for it. Never leaves the app.
  final String key;

  final String name;

  /// The Play Games id, from the Console's games-ids.xml.
  final String androidId;

  /// The Game Center id, from App Store Connect.
  final String iosId;

  /// Which [AchievementProgress] number is submitted as the score.
  ///
  /// The same pool the achievements are measured against, on purpose: a
  /// leaderboard reading its own private counter is a second answer to a
  /// question the profile already answers, and the two would eventually
  /// disagree with nothing to say which was right.
  final String source;

  /// Whether this can be submitted to on *this* platform yet.
  ///
  /// Per-platform for the same reason the achievements are: the two stores
  /// are filled in at different times, and a blank id must mean "skip" rather
  /// than a call into the plugin with an empty string.
  bool get isConfigured => defaultTargetPlatform == TargetPlatform.iOS
      ? iosId.isNotEmpty
      : androidId.isNotEmpty;

  factory Leaderboard.fromJson(Map<String, dynamic> json) => Leaderboard(
    key: json['key'] as String,
    name: json['name'] as String? ?? '',
    androidId: json['androidId'] as String? ?? '',
    iosId: json['iosId'] as String? ?? '',
    source: json['source'] as String? ?? '',
  );
}

/// Every leaderboard, from `assets/data/leaderboards.json`.
class LeaderboardSet {
  const LeaderboardSet({required this.all});

  final List<Leaderboard> all;

  static const LeaderboardSet empty = LeaderboardSet(all: []);

  /// The ones with a platform id behind them on this platform.
  Iterable<Leaderboard> get configured => all.where((b) => b.isConfigured);

  Leaderboard? byKey(String key) {
    for (final board in all) {
      if (board.key == key) return board;
    }
    return null;
  }

  static Future<LeaderboardSet> load() async {
    try {
      final raw = await rootBundle.loadString('assets/data/leaderboards.json');
      return LeaderboardSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Same rule as every other optional layer: a broken file takes the
      // feature away, never the game.
      return LeaderboardSet.empty;
    }
  }

  factory LeaderboardSet.fromJson(Map<String, dynamic> json) => LeaderboardSet(
    all: [
      for (final entry in (json['leaderboards'] as List? ?? const []))
        Leaderboard.fromJson(entry as Map<String, dynamic>),
    ],
  );
}
