import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// Carries an aura: friendly units near it take less damage.
///
/// The aura itself is read by whoever is being hit (see [Unit.auraReduction]),
/// so it covers melee, ranged and spell damage without any of them knowing
/// Wardens exist. This type only draws the ring.
class Warden extends Unit {
  Warden({required super.stats, required super.team, required super.position});

  static const String id = 'warden';
  static const String riveArtboard = 'warden';

  static Warden spawn(UnitStats stats, Team team, Vector2 position) =>
      Warden(stats: stats, team: team, position: position);

  static final Paint _auraPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.06;

  @override
  void render(Canvas canvas) {
    if (isAlive && stats.hasAura) {
      _auraPaint.color = Palette.of(team).withValues(alpha: 0.35);
      canvas.drawCircle(
        Offset(stats.radius, stats.radius),
        stats.auraRadius,
        _auraPaint,
      );
    }
    super.render(canvas);
  }
}
