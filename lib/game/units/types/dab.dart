import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// Spawns three fast bodies that swarm a tank.
///
/// Fully stat-driven: everything that makes it distinct lives in
/// `cards.json`. This type names it and gives its Rive artboard a home.
class Dab extends Unit {
  Dab({required super.stats, required super.team, required super.position});

  static const String id = 'dab';
  static const String riveArtboard = 'dab';

  static Dab spawn(UnitStats stats, Team team, Vector2 position) =>
      Dab(stats: stats, team: team, position: position);
}
