import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../building.dart';
import '../unit_stats.dart';

/// A wall of paint. Soaks a push so your own troops do not have to.
///
/// It deals no damage, but it is the nearest enemy to anything that walks
/// into it, so a push spends its time hitting a barricade instead of your
/// Roller. Cheap enough to throw down as an answer rather than a plan.
class Barricade extends Building {
  Barricade({
    required super.stats,
    required super.team,
    required super.position,
  });

  static const String id = 'barricade';
  static const String riveArtboard = 'barricade';

  static Barricade spawn(UnitStats stats, Team team, Vector2 position) =>
      Barricade(stats: stats, team: team, position: position);
}
