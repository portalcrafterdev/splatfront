import 'package:flutter/foundation.dart';

import 'unit.dart';

/// A unit that does not walk.
///
/// Everything that makes a building a building is data: its speed is `static`
/// in `cards.json`, which resolves to zero, so the ordinary movement code
/// moves it nowhere and it can only hit what comes to it. The one thing that
/// is genuinely code is the clock — a building holds ground for a while and
/// then goes, which is what stops a board from silting up with turrets.
///
/// It is still a [Unit] in every other respect: it is targeted like one, it
/// takes damage like one, auras cover it, and it leaves a splash when it
/// dies. Nothing in targeting or combat needs to know buildings exist.
abstract class Building extends Unit {
  Building({
    required super.stats,
    required super.team,
    required super.position,
  });

  double _age = 0;

  /// Seconds left before it expires, or null if it stands until killed.
  double? get secondsLeft =>
      stats.isTemporary ? (stats.lifetime - _age).clamp(0.0, stats.lifetime) : null;

  /// How much of its life is gone, 0 to 1. Drives the wear on the art.
  double get wear =>
      stats.isTemporary ? (_age / stats.lifetime).clamp(0.0, 1.0) : 0.0;

  @override
  @mustCallSuper
  void update(double dt) {
    super.update(dt);
    if (isDying || !stats.isTemporary) return;

    _age += dt;
    // Expires rather than takes lethal damage: running out of time is not a
    // hit, and should not flash, chime or credit anybody with a kill.
    if (_age >= stats.lifetime) expire();
  }
}
