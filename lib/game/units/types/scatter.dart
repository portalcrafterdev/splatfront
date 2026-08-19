import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../building.dart';
import '../unit_stats.dart';

/// A mortar that fires all the way round itself.
///
/// Every other gun in the set picks a target and shoots it. This one does not
/// aim at all: on its own timer it throws a full ring of shells outward, each
/// one splatting where it lands, and the ring turns a little each volley so
/// the gaps between last time's craters get filled this time.
///
/// That makes it an area machine rather than a weapon. It will happily fire
/// into an empty arena, which is the point — dropped on your own front line
/// it paints a wide circle of ground you never had to walk to. The damage is
/// deliberately small: what you are paying for is coverage.
class Scatter extends Building {
  Scatter({required super.stats, required super.team, required super.position});

  static const String id = 'scatter';
  static const String riveArtboard = 'scatter';

  static Scatter spawn(UnitStats stats, Team team, Vector2 position) =>
      Scatter(stats: stats, team: team, position: position);

  /// Counts down to the next ring. Independent of the combat loop, because
  /// this gun does not wait for something to shoot at.
  double _volleyTimer = 0;

  /// How far the ring has rotated. Advanced by a deliberately irregular step
  /// so successive volleys interleave instead of landing in the same spots.
  double _spin = 0;

  /// The turn between volleys, as a fraction of the gap between two shells.
  static const double _spinStep = 0.41;

  /// Where the barrels are pointing, for the art to draw.
  double get spin => _spin;

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive || isStunned) return;

    _volleyTimer -= dt;
    if (_volleyTimer > 0) return;
    _volleyTimer = stats.attackInterval;
    _fireRing();
  }

  void _fireRing() {
    final shells = stats.volley;
    if (shells <= 0) return;

    final step = math.pi * 2 / shells;
    _spin = (_spin + step * _spinStep) % (math.pi * 2);

    for (var i = 0; i < shells; i++) {
      final angle = _spin + i * step;
      final at = Vector2(
        position.x + math.cos(angle) * stats.range,
        position.y + math.sin(angle) * stats.range,
      );
      game.fireProjectile(
        from: position,
        at: at,
        team: team,
        paintRadius: stats.shellPaint,
        speed: 7.0,
        size: 0.20,
        arcHeight: 1.5,
      );
    }

    _shellEnemiesInRing();
  }

  /// The barrage hits everything inside the ring it just landed.
  ///
  /// Applied here rather than by each shell, for the same reason every other
  /// gun applies damage on its own tick: a [Projectile] carries paint, never
  /// damage, so the hit rate in `cards.json` stays the hit rate.
  void _shellEnemiesInRing() {
    final reach = stats.range + stats.shellPaint;
    final reachSquared = reach * reach;
    for (final other in game.units.toList()) {
      if (other.team == team || !other.isAlive) continue;
      if (!stats.targets.canHit(flying: other.stats.flying)) continue;
      if (position.distanceToSquared(other.position) > reachSquared) continue;
      other.takeDamage(stats.damage);
    }
  }
}
