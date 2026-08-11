import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// Standard front line. Closes to melee and swings.
///
/// Everything about it is stat-driven, so this type exists to name it and to
/// hold its Rive artboard once the art lands.
class Brusher extends Unit {
  Brusher({required super.stats, required super.team, required super.position});

  static const String id = 'brusher';
  static const String riveArtboard = 'brusher';

  static Brusher spawn(UnitStats stats, Team team, Vector2 position) =>
      Brusher(stats: stats, team: team, position: position);
}
