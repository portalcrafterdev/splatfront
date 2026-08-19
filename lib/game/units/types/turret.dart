import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../../core/constants.dart';
import '../../../core/palette.dart';
import '../building.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// A cannon on a stand. The one card that throws paint over the front line.
///
/// It cannot walk and it cannot chase, so everything it is worth comes from
/// where you put it: dropped at the edge of your own colour it shells ground
/// you could not otherwise reach, and the splat lands where the shell lands
/// rather than under its own feet.
///
/// With something to shoot it shells that. With nothing to shoot it keeps
/// firing anyway, lobbing shells all the way round itself — which is the
/// point of a gun in a game scored on ground. Waiting for a target meant four
/// elixir bought thirty seconds of a building doing nothing at all whenever
/// the fighting was somewhere else, and standing idle paints no floor.
class Turret extends Building {
  Turret({required super.stats, required super.team, required super.position});

  static const String id = 'turret';
  static const String riveArtboard = 'turret';

  static Turret spawn(UnitStats stats, Team team, Vector2 position) =>
      Turret(stats: stats, team: team, position: position);

  /// The angle between one idle shell and the next.
  ///
  /// The golden angle, so consecutive shells never line up and the circle
  /// fills in evenly however many have been fired. A round fraction of a turn
  /// would retrace the same few spokes.
  static const double _goldenAngle = 2.399963229728653;

  /// Counts down to the next idle shell. Separate from the combat timer,
  /// because this one runs when there is nothing to shoot at.
  double _idleTimer = 0;

  /// How many idle shells have gone out, which sets both the bearing and how
  /// far this one is thrown.
  int _idleShot = 0;

  /// Where the barrel is pointing, for the art.
  double _aim = 0;
  double get aim => _aim;

  @override
  void onAttack(Unit target) {
    _aim = math.atan2(
      target.position.y - position.y,
      target.position.x - position.x,
    );
    _lob(target.position);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive || isStunned) return;

    // A target takes priority: an aimed shell is worth more than a sprayed
    // one, and the ordinary combat loop is already firing it.
    if (target != null) {
      _idleTimer = stats.attackInterval;
      return;
    }

    _idleTimer -= dt;
    if (_idleTimer > 0) return;
    _idleTimer = stats.attackInterval;
    _lobOutward();
  }

  /// One shell into open ground, on a bearing that walks round the compass.
  void _lobOutward() {
    // How many shells make one sweep out to full range. Falls back to a
    // sweep of twelve so a turret whose card omits the number still fires.
    final sweep = stats.volley > 0 ? stats.volley : 12;

    final shot = _idleShot++;
    final angle = shot * _goldenAngle;
    _aim = angle;

    // Square root, not a straight ramp: it spreads the shells evenly over the
    // *area* of the circle. Stepping the distance linearly crowds them into
    // the middle, because a ring twice as far out has twice the ground in it.
    final t = (shot % sweep + 1) / sweep;
    final distance = stats.range * math.sqrt(t);

    _lob(
      Vector2(
        position.x + math.cos(angle) * distance,
        position.y + math.sin(angle) * distance,
      ),
    );
  }

  /// Throws one shell at [at], kept inside the board.
  ///
  /// Clamped because a bearing pointing off the edge would otherwise splat
  /// past the arena, where the sampler cannot score it — paint spent on
  /// nothing. Held at the boundary it still claims the edge tiles.
  void _lob(Vector2 at) {
    game.fireProjectile(
      from: position,
      at: Vector2(
        at.x.clamp(0.0, ArenaSpec.worldWidth),
        at.y.clamp(0.0, ArenaSpec.worldHeight),
      ),
      team: team,
      paintRadius: stats.shellPaint,
      speed: 8.0,
      size: 0.28,
      arcHeight: 2.3,
    );
  }
}
