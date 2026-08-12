import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// The cannon. One shot lands on everything near where it hits, which is what
/// makes it the answer to Dab and Swarmlets.
///
/// It is also the only unit that throws paint past the front line: the shell
/// flies to where it was aimed and splats there, so a Nozzle sitting safely in
/// its own half can still claim ground in the enemy's.
class Nozzle extends Unit {
  Nozzle({required super.stats, required super.team, required super.position});

  static const String id = 'nozzle';
  static const String riveArtboard = 'nozzle';

  static Nozzle spawn(UnitStats stats, Team team, Vector2 position) =>
      Nozzle(stats: stats, team: team, position: position);

  @override
  void onAttack(Unit target) {
    game.fireProjectile(
      from: position,
      at: target.position,
      team: team,
      // The splat matches the blast, so where the shell hurt is where the
      // ground changed colour.
      paintRadius: stats.splashRadius > 0 ? stats.splashRadius : stats.paint,
      speed: 8.0,
      size: 0.26,
      // Lobbed high: this is a mortar, and the arc is what makes it read as
      // a thrown shell rather than a bullet skimming the floor.
      arcHeight: 1.9,
    );
  }

  @override
  void dealDamage(Unit target) {
    final radius = stats.splashRadius;
    if (radius <= 0) {
      super.dealDamage(target);
      return;
    }

    // Everything of the enemy's within the blast, the primary target
    // included. Damage goes through takeDamage, so auras still apply.
    final splashSquared = radius * radius;
    for (final other in game.units.toList()) {
      if (other.team == team || !other.isAlive) continue;
      if (!stats.targets.canHit(flying: other.stats.flying)) continue;
      if (target.position.distanceToSquared(other.position) > splashSquared) {
        continue;
      }
      other.takeDamage(stats.damage);
    }
  }
}
