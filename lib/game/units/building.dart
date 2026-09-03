import 'package:flutter/foundation.dart';

import 'unit.dart';

/// A unit that does not walk.
///
/// Everything that makes a building a building is data: its speed is `static`
/// in `cards.json`, which resolves to zero, so the ordinary movement code
/// moves it nowhere and it can only hit what comes to it. The one thing that
/// is genuinely code is the clock.
///
/// **Every building currently ships with `lifetime: 0`, which means it stands
/// until something kills it.** That is the owner's call, reversing the design
/// note's timer: a gun that vanished on its own made four elixir feel like a
/// rental, and a building you have to actually break is a better fight. The
/// timer itself is untouched — set a lifetime above zero in `cards.json` and
/// that card goes back on a clock, with no code change.
///
/// What still stops the board silting up with turrets is the live-building
/// cap (`buildings.maxLive` in `progression.json`), which refuses the drop
/// rather than taking the card. The design note called the cap and the timer
/// two different problems; with the timer off, the cap is carrying both.
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
  double? get secondsLeft => stats.isTemporary
      ? (stats.lifetime - _age).clamp(0.0, stats.lifetime)
      : null;

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
