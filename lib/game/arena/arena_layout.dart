import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants.dart';
import '../../core/palette.dart';
import 'deploy_zone.dart';

/// A static blocker. Units path around it, paint never covers it, nobody can
/// deploy on it.
class Blocker {
  const Blocker(this.rect);

  final Rect rect; // world units

  Vector2 get centre => Vector2(rect.center.dx, rect.center.dy);

  /// Radius of the circle used for the cheap steering avoidance in unit AI.
  double get avoidRadius => rect.longestSide * 0.5;
}

/// One arena: its floor tint, its blockers and the trophy floor that unlocks
/// it. Loaded from `assets/data/levels.json`, never hardcoded.
class ArenaLayout {
  const ArenaLayout({
    required this.id,
    required this.name,
    required this.trophies,
    required this.floor,
    required this.blockers,
  });

  final String id;
  final String name;
  final int trophies;
  final Color floor;
  final List<Blocker> blockers;

  static const ArenaLayout fallback = ArenaLayout(
    id: 'arena_1',
    name: 'Primer Yard',
    trophies: 0,
    floor: Palette.arenaFloor,
    blockers: [],
  );

  factory ArenaLayout.fromJson(Map<String, dynamic> json) => ArenaLayout(
    id: json['id'] as String,
    name: json['name'] as String,
    trophies: (json['trophies'] as num).toInt(),
    floor: _parseColour(json['floor'] as String?) ?? Palette.arenaFloor,
    blockers: [
      for (final b in (json['blockers'] as List<dynamic>? ?? const []))
        Blocker(
          Rect.fromLTWH(
            (b['x'] as num).toDouble(),
            (b['y'] as num).toDouble(),
            (b['w'] as num).toDouble(),
            (b['h'] as num).toDouble(),
          ),
        ),
    ],
  );

  /// Marks every grid cell whose centre falls inside a blocker. Those cells
  /// are unpaintable and are excluded from the coverage denominator entirely,
  /// so obstacles never dilute the score.
  Uint8List buildBlockedMask() {
    final mask = Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows);
    if (blockers.isEmpty) return mask;
    for (var row = 0; row < ArenaSpec.gridRows; row++) {
      for (var col = 0; col < ArenaSpec.gridCols; col++) {
        final c = DeployZone.cellCentre(col, row);
        for (final b in blockers) {
          if (b.rect.contains(Offset(c.x, c.y))) {
            mask[DeployZone.cellIndex(col, row)] = 1;
            break;
          }
        }
      }
    }
    return mask;
  }

  static Future<List<ArenaLayout>> loadAll() async {
    final raw = await rootBundle.loadString('assets/data/levels.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final a in json['arenas'] as List<dynamic>)
        ArenaLayout.fromJson(a as Map<String, dynamic>),
    ];
  }

  /// The highest arena the player has unlocked at [trophyCount].
  static ArenaLayout forTrophies(List<ArenaLayout> all, int trophyCount) {
    var best = all.first;
    for (final a in all) {
      if (trophyCount >= a.trophies) best = a;
    }
    return best;
  }

  static Color? _parseColour(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(cleaned.length <= 6 ? 0xFF000000 | value : value);
  }
}
