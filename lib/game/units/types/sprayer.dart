import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// Paints while it shoots: the best value painter in the set.
///
/// Its range keeps it standing still and firing a lot, and a stationary unit
/// would only ever stamp one spot — so its spray lands where it is aiming
/// rather than under its own feet, claiming the ground it is holding.
class Sprayer extends Unit {
  Sprayer({required super.stats, required super.team, required super.position});

  static const String id = 'sprayer';
  static const String riveArtboard = 'sprayer';

  static Sprayer spawn(UnitStats stats, Team team, Vector2 position) =>
      Sprayer(stats: stats, team: team, position: position);

  @override
  void onAttack(Unit target) {
    game.fireProjectile(
      from: position,
      at: target.position,
      team: team,
      paintRadius: stats.paint,
      speed: 14.0,
      size: 0.15,
      arcHeight: 0.35,
    );
  }
}
