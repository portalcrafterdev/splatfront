import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// Six tiny bodies that melt a single tank.
///
/// Fully stat-driven: everything that makes it distinct lives in
/// `cards.json`. This type names it and gives its Rive artboard a home.
class Swarmlets extends Unit {
  Swarmlets({required super.stats, required super.team, required super.position});

  static const String id = 'swarmlets';
  static const String riveArtboard = 'swarmlets';

  static Swarmlets spawn(UnitStats stats, Team team, Vector2 position) =>
      Swarmlets(stats: stats, team: team, position: position);
}
