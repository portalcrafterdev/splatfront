import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../splatfront_game.dart';

/// A burst of paint droplets thrown out from a point.
///
/// One component draws the whole burst rather than one component per droplet,
/// so a busy fight costs a handful of components instead of hundreds. Section
/// 13 caps live particles at 300; [Splatter.budget] enforces that from the
/// spawn side, because the cheapest particle is the one never created.
class Splatter extends PositionComponent with HasGameReference<SplatfrontGame> {
  Splatter._({
    required Vector2 at,
    required this.colour,
    required this.count,
    required this.spread,
    required this.duration,
    required math.Random random,
  }) : super(position: at, anchor: Anchor.center, priority: 35) {
    for (var i = 0; i < count; i++) {
      // Aimed evenly around the circle with a jitter, rather than fully at
      // random: pure randomness clumps, and a clumped splat looks like a
      // mistake rather than a splash.
      final angle =
          (i / count) * math.pi * 2 + (random.nextDouble() - 0.5) * 0.9;
      final speed = spread * (0.45 + random.nextDouble() * 0.75);
      _vx.add(math.cos(angle) * speed);
      _vy.add(math.sin(angle) * speed);
    }
  }

  /// How many droplets are alive across the whole game right now.
  static int live = 0;

  /// The section 13 ceiling. A burst that would cross it is trimmed rather
  /// than dropped, so a big moment still reads even under load.
  static const int budget = PerfBudget.maxLiveParticles;

  /// Makes a burst, or null if there is no budget left for one.
  ///
  /// Returning null rather than an empty component keeps the caller honest:
  /// there is nothing to add to the tree.
  static Splatter? maybe({
    required Vector2 at,
    required Team team,
    required math.Random random,
    int count = 8,
    double spread = 2.4,
    double duration = 0.45,
  }) {
    final room = budget - live;
    if (room <= 1) return null;
    final trimmed = math.min(count, room);

    live += trimmed;
    return Splatter._(
      at: at,
      colour: Palette.of(team),
      count: trimmed,
      spread: spread,
      duration: duration,
      random: random,
    );
  }

  final Color colour;
  final int count;
  final double spread;
  final double duration;

  final List<double> _vx = <double>[];
  final List<double> _vy = <double>[];

  /// Droplet positions this frame, laid out as x,y pairs.
  ///
  /// Allocated once per burst and rewritten in place, so drawing costs no
  /// garbage — at three hundred live droplets a per-frame list would be three
  /// hundred allocations a frame.
  late final Float32List _points = Float32List(count * 2);

  double _elapsed = 0;
  bool _released = false;

  /// Droplets are drawn as round stroke caps in one [Canvas.drawRawPoints]
  /// call rather than one `drawCircle` each. At the three-hundred particle
  /// budget that is one draw op a burst instead of hundreds, and anti-aliased
  /// circles are among the most expensive things this game asks for.
  static final Paint _drop = Paint()
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) {
    _elapsed += dt;
    // Queued, not removed on the spot: this runs inside the tree walk, and
    // taking a component out of the world from in there throws.
    if (_elapsed >= duration) game.despawnComponent(this);
  }

  @override
  void onRemove() {
    release();
    super.onRemove();
  }

  /// Droplets go back to the budget exactly once, however the component
  /// leaves — removed, or the whole arena torn down mid-burst.
  void release() {
    if (_released) return;
    _released = true;
    live = math.max(0, live - count);
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / duration).clamp(0.0, 1.0);
    final fade = 1 - t * t;
    if (fade <= 0) return;

    // Droplets slow as they fly, like thrown paint rather than sparks, and
    // shrink as they dry out.
    final travel = t * (2 - t);
    for (var i = 0; i < _vx.length; i++) {
      _points[i * 2] = _vx[i] * travel;
      _points[i * 2 + 1] = _vy[i] * travel;
    }

    _drop
      ..color = colour.withValues(alpha: fade)
      ..strokeWidth = _dropSize * 2 * (1 - t * 0.55);
    canvas.drawRawPoints(PointMode.points, _points, _drop);
  }

  /// Droplet radius. One size for the whole burst rather than one per
  /// droplet, because a single [Canvas.drawRawPoints] call can only carry one
  /// stroke width — and one draw op beats a bag of slightly different circles.
  static const double _dropSize = 0.10;
}
