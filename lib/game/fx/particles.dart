import 'package:flame/components.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import '../splatfront_game.dart';

/// A one-shot expanding ring, used to show where a spell landed.
///
/// Deliberately a single drawn circle rather than a particle system: section
/// 13 caps live particles at 300, and a spell going off should never be the
/// thing that spends them. Real bursts become pre-baked Rive at Phase 8.
class BurstEffect extends PositionComponent
    with HasGameReference<SplatfrontGame> {
  BurstEffect({
    required Vector2 at,
    required this.radius,
    required this.colour,
    this.duration = 0.45,
  }) : super(position: at, anchor: Anchor.center, priority: 40);

  final double radius;
  final Color colour;
  final double duration;

  double _elapsed = 0;

  static final Paint _ring = Paint()..style = PaintingStyle.stroke;
  static final Paint _fill = Paint();

  @override
  void update(double dt) {
    _elapsed += dt;
    // Queued, not removed on the spot: this runs inside the tree walk, and
    // taking a component out of the world from in there throws.
    if (_elapsed >= duration) game.despawnComponent(this);
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / duration).clamp(0.0, 1.0);
    final fade = 1.0 - t;
    if (fade <= 0) return;

    // Snaps out fast, then eases.
    final grown = radius * (0.35 + 0.65 * Curves.easeOut.transform(t));

    _fill.color = colour.withValues(alpha: 0.22 * fade);
    canvas.drawCircle(Offset.zero, grown, _fill);

    _ring
      ..color = colour.withValues(alpha: 0.85 * fade)
      ..strokeWidth = 0.12 * fade + 0.04;
    canvas.drawCircle(Offset.zero, grown, _ring);
  }
}
