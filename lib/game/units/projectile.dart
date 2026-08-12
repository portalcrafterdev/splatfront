import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../core/audio.dart';
import '../../core/palette.dart';
import '../splatfront_game.dart';

/// A shot in flight, from a ranged unit to where it was aimed.
///
/// Damage is not carried here: it lands the instant the unit swings, the same
/// as a melee hit, so range never turns into a delay the balance numbers did
/// not account for. What the shot does carry is the paint. A cannon that
/// stamps under its own feet is painting ground it already owns; one whose
/// shell lands in enemy colour and repaints it is how a ranged painter earns
/// its cost, and it is the only way paint gets thrown past the front line.
class Projectile extends PositionComponent
    with HasGameReference<SplatfrontGame> {
  Projectile({
    required Vector2 from,
    required this.destination,
    required this.team,
    required this.speed,
    this.paintRadius = 0,
    this.size2 = 0.16,
    this.arcHeight = 0,
  }) : _span = from.distanceTo(destination),
       super(
         position: from.clone(),
         anchor: Anchor.center,
         size: Vector2.all(size2 * 2),
         priority: 30,
       );

  /// How high the shot is lofted at the midpoint of its flight, in world
  /// units. Zero is a flat shot — a rifle round. A real number turns it into
  /// a lob, which is the whole visual difference between a bullet and a
  /// thrown ball.
  final double arcHeight;

  /// Distance from launch to target, fixed at launch so progress along the
  /// flight can be measured without recomputing the whole path.
  final double _span;

  /// Where it was aimed. Fixed at launch, so a shot does not home in on a
  /// target that has since walked away — it lands where it was sent.
  final Vector2 destination;

  final Team team;

  /// World units per second.
  final double speed;

  /// Radius of the splat it leaves on impact. 0 for a shot that only hurts.
  final double paintRadius;

  /// Visual radius of the shot itself.
  final double size2;

  /// Distance within which the shot counts as arrived. A shot that overshoots
  /// by a fraction of a frame should land, not turn around.
  static const double _arrival = 0.12;

  final Vector2 _step = Vector2.zero();

  /// How far along the flight, 0 at launch and 1 on impact.
  double get progress {
    if (_span <= 0) return 1;
    return (1 - position.distanceTo(destination) / _span).clamp(0.0, 1.0);
  }

  /// How high the ball currently rides above its own shadow.
  ///
  /// A parabola through zero at both ends, so it leaves the muzzle and meets
  /// the ground exactly where the splat lands.
  double get _lift {
    if (arcHeight <= 0) return 0;
    final t = progress;
    return 4 * arcHeight * t * (1 - t);
  }

  static final Paint _body = Paint()..isAntiAlias = true;
  static final Paint _rim = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;
  static final Paint _shadow = Paint()..isAntiAlias = true;

  /// Removal is queued, so a landed shot still gets an update or two before
  /// it leaves the tree. Without this it would splat once per frame.
  bool _landed = false;

  @override
  void update(double dt) {
    if (_landed) return;

    _step
      ..setFrom(destination)
      ..sub(position);

    final remaining = _step.length;
    final travel = speed * dt;

    if (remaining <= travel + _arrival) {
      position.setFrom(destination);
      _land();
      return;
    }

    _step.scale(travel / remaining);
    position.add(_step);
  }

  void _land() {
    _landed = true;
    if (paintRadius > 0) {
      game.arena.paintLayer.stamp(position, paintRadius, team);
      game.burst(
        position,
        team,
        count: (4 + paintRadius * 3).round(),
        spread: paintRadius * 1.2,
        duration: 0.4,
      );
      Audio.play(Sfx.splat);
      // Only a cannon shell is heavy enough to be felt.
      if (paintRadius >= 1.2) {
        game.shake(amplitude: 0.07, seconds: 0.16);
      }
    }
    game.despawnComponent(this);
  }

  @override
  void render(Canvas canvas) {
    final ground = Offset(size2, size2);
    final lift = _lift;
    final ball = ground.translate(0, -lift);

    // A shadow on the ground under the ball, growing as the ball comes down.
    // Without it a lobbed shot reads as a ball sliding along the floor.
    if (arcHeight > 0) {
      final closeness = 1 - (lift / arcHeight).clamp(0.0, 1.0);
      _shadow.color = Color.fromRGBO(0, 0, 0, 0.10 + 0.16 * closeness);
      canvas.drawOval(
        Rect.fromCenter(
          center: ground,
          width: size2 * (1.3 + 0.7 * closeness),
          height: size2 * (0.5 + 0.3 * closeness),
        ),
        _shadow,
      );
    }

    // A pale core inside a team-coloured shell, ringed in dark.
    //
    // A ball in the flat team colour is invisible for the half of its flight
    // that crosses its own paint, which is most of the interesting half. The
    // pale centre is what makes it readable over either side's ground.
    _body.color = Palette.of(team);
    canvas.drawCircle(ball, size2, _body);

    _body.color = const Color(0xFFFFF7EC);
    canvas.drawCircle(ball, size2 * 0.52, _body);

    _rim
      ..color = const Color(0xCC241F1A)
      ..strokeWidth = size2 * 0.34;
    canvas.drawCircle(ball, size2, _rim);
  }
}
