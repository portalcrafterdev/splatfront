import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../core/palette.dart';
import '../splatfront_game.dart';

/// The visible flash of a laser, from the emitter to whatever it burned.
///
/// Purely the picture. The damage and the paint are applied by the unit on
/// its own attack tick, because a beam that only hurt things while its
/// animation happened to be on screen would make the hit rate a lie.
class BeamEffect extends PositionComponent
    with HasGameReference<SplatfrontGame> {
  BeamEffect({
    required Vector2 from,
    required Vector2 to,
    required this.team,
    this.duration = 0.14,
    this.beamWidth = 0.22,
  }) : _from = from.clone(),
       _to = to.clone(),
       super(priority: 32);

  final Vector2 _from;
  final Vector2 _to;
  final Team team;
  final double duration;
  final double beamWidth;

  double _elapsed = 0;

  static final Paint _core = Paint()..strokeCap = StrokeCap.round;
  static final Paint _glow = Paint()..strokeCap = StrokeCap.round;

  @override
  void update(double dt) {
    _elapsed += dt;
    // Queued, like every other self-removal: this runs inside the tree walk.
    if (_elapsed >= duration) game.despawnComponent(this);
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / duration).clamp(0.0, 1.0);
    final fade = 1 - t;
    if (fade <= 0) return;

    final a = Offset(_from.x, _from.y);
    final b = Offset(_to.x, _to.y);
    final colour = Palette.of(team);

    // A wide soft pass and a hot core, which is what sells a beam.
    _glow
      ..color = colour.withValues(alpha: 0.35 * fade)
      ..strokeWidth = beamWidth * 2.2 * fade;
    canvas.drawLine(a, b, _glow);

    _core
      ..color = const Color(0xFFFFF7EC).withValues(alpha: 0.95 * fade)
      ..strokeWidth = beamWidth * fade;
    canvas.drawLine(a, b, _core);
  }
}
