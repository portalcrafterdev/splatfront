import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// A spinning blade that walks. Hits everything it is standing among.
///
/// Its swing is not aimed at one body: it carves a circle of [UnitStats
/// .splashRadius] around itself, so it trades badly against a single tank and
/// very well against anything that arrives in a group. It also lays the
/// second-widest trail in the set, because a blade that is grinding through a
/// crowd should be throwing paint everywhere.
class Whirl extends Unit {
  Whirl({required super.stats, required super.team, required super.position});

  static const String id = 'whirl';
  static const String riveArtboard = 'whirl';

  static Whirl spawn(UnitStats stats, Team team, Vector2 position) =>
      Whirl(stats: stats, team: team, position: position);

  @override
  void dealDamage(Unit target) {
    final radius = stats.splashRadius;
    if (radius <= 0) {
      super.dealDamage(target);
      return;
    }

    // Centred on the blade, not on the target: this is a spin, so standing
    // behind it is no safer than standing in front.
    final reachSquared = radius * radius;
    for (final other in game.units.toList()) {
      if (other.team == team || !other.isAlive) continue;
      if (!stats.targets.canHit(flying: other.stats.flying)) continue;
      if (position.distanceToSquared(other.position) > reachSquared) continue;
      other.takeDamage(stats.damage);
    }
  }

  @override
  void onAttack(Unit target) {
    game.burst(position, team, count: 6, spread: stats.splashRadius * 1.1);
  }
}
