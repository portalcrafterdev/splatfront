import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../../fx/beam.dart';
import '../building.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// A laser on a post. The only card that paints a line rather than a blob.
///
/// Where the Turret lobs a shell and splats where it lands, this burns a
/// stripe of ground all the way out to whatever it is shooting. That makes it
/// the card for cutting a corridor into enemy colour: the stripe is a deploy
/// path, not just damage.
class Beamer extends Building {
  Beamer({required super.stats, required super.team, required super.position});

  static const String id = 'beamer';
  static const String riveArtboard = 'beamer';

  static Beamer spawn(UnitStats stats, Team team, Vector2 position) =>
      Beamer(stats: stats, team: team, position: position);

  /// How finely the stripe is stamped, in world units between stamps. Small
  /// enough that the line is continuous at the widest shell radius.
  static const double _stampStep = 0.55;

  @override
  void onAttack(Unit target) {
    game.spawnComponent(
      BeamEffect(from: position, to: target.position, team: team),
    );

    final radius = stats.shellPaint;
    if (radius <= 0) return;

    // Stamp from the emitter out to the target. Capped so a very long shot
    // cannot turn one attack tick into hundreds of stamps.
    final span = position.distanceTo(target.position);
    final steps = math.min((span / _stampStep).ceil(), 24);
    for (var i = 1; i <= steps; i++) {
      final at = position + (target.position - position) * (i / steps);
      game.arena.paintLayer.stamp(at, radius, team);
    }
    game.burst(target.position, team, count: 5, spread: radius * 1.4);
  }
}
