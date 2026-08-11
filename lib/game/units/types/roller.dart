import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// The main painter. Walks straight, leaves a huge trail.
///
/// "Walks straight" is data, not code: its `aggroRange` is 0 in `cards.json`,
/// so it never diverts to chase and only hits what is already in its path.
class Roller extends Unit {
  Roller({required super.stats, required super.team, required super.position});

  static const String id = 'roller';
  static const String riveArtboard = 'roller';

  static Roller spawn(UnitStats stats, Team team, Vector2 position) =>
      Roller(stats: stats, team: team, position: position);
}
