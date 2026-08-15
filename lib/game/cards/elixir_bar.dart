import 'package:flutter/foundation.dart';

import '../../core/constants.dart';

/// The elixir pool behind the bar.
///
/// One elixir every [Timings] regen interval, capped at ten, and doubled in
/// sudden death. The HUD watches [value] rather than rebuilding on a timer.
class ElixirBar {
  ElixirBar({double start = ElixirSpec.start})
    : value = ValueNotifier(start.clamp(0.0, ElixirSpec.max));

  /// Current elixir, fractional so the active bar segment can part-fill.
  final ValueNotifier<double> value;

  /// Sudden death doubles the regen rate and nothing else.
  bool suddenDeath = false;

  /// Set false during the countdown, so elixir does not accrue before Splat.
  bool running = true;

  /// Income scaling from territory held, set every coverage sample.
  ///
  /// Above 1 fills faster. Held at 1 by the sandboxes and by anything that
  /// has not wired the arena up, so the bar still works on its own.
  double rateMultiplier = 1.0;

  double get amount => value.value;

  /// Seconds to earn one elixir, after sudden death and territory.
  ///
  /// A multiplier over 1 means income goes *up*, so it divides the interval
  /// rather than multiplying it. Floored so a rounding error can never make
  /// the interval zero and hand a side infinite elixir in one frame.
  double get secondsPerElixir {
    final base = suddenDeath
        ? ElixirSpec.regenSuddenDeath
        : ElixirSpec.regenNormal;
    return base / rateMultiplier.clamp(0.1, 5.0);
  }

  /// Whole segments filled, 0..10.
  int get filledSegments => amount.floor();

  /// How far the next segment has filled, 0..1.
  double get partialFill => amount - amount.floorToDouble();

  /// Called the moment the bar tops out, once per fill.
  ///
  /// A callback rather than the bar playing a sound itself: the bot has one
  /// of these too, and nobody wants to hear its economy.
  void Function()? onFull;

  void update(double dt) {
    if (!running) return;
    final next = amount + dt / secondsPerElixir;
    if (next >= ElixirSpec.max) {
      if (amount < ElixirSpec.max) {
        value.value = ElixirSpec.max;
        onFull?.call();
      }
      return;
    }
    value.value = next;
  }

  bool canAfford(int cost) => amount >= cost;

  /// Spends [cost] if it is there. Returns false and changes nothing if not,
  /// so a caller can never go negative by forgetting to check.
  bool spend(int cost) {
    if (!canAfford(cost)) return false;
    value.value = amount - cost;
    return true;
  }

  void reset({double to = ElixirSpec.start}) =>
      value.value = to.clamp(0.0, ElixirSpec.max);

  void dispose() => value.dispose();
}
