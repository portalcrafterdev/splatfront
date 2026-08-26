import 'dart:math' as math;

import 'package:flame/components.dart';

import '../splatfront_game.dart';

/// Kicks the camera when something lands hard.
///
/// One component owns the whole effect rather than each impact nudging the
/// camera itself: overlapping shakes would otherwise fight over
/// `viewfinder.position` and leave the arena parked off centre. Here the
/// strongest shake wins, and the camera is always put back exactly where it
/// started.
class ScreenShake extends Component with HasGameReference<SplatfrontGame> {
  ScreenShake({this.maxOffset = 0.55});

  /// Hard ceiling in world units. The arena is 16 wide, and anything past
  /// about half a unit stops reading as impact and starts reading as a bug.
  final double maxOffset;

  double _remaining = 0;
  double _duration = 0;
  double _amplitude = 0;

  final math.Random _random = math.Random();
  final Vector2 _rest = Vector2.zero();

  bool get isShaking => _remaining > 0;

  /// Adds a shake of [amplitude] world units for [seconds].
  ///
  /// Takes the stronger of the two rather than summing, so a Paint Bomb going
  /// off during a brawl does not multiply into a screen-wide earthquake.
  void shake({required double amplitude, double seconds = 0.25}) {
    final capped = amplitude.clamp(0.0, maxOffset);
    if (capped <= 0) return;

    if (capped >= _amplitude) {
      _amplitude = capped;
      _duration = seconds;
      _remaining = seconds;
    } else if (_remaining < seconds * 0.5) {
      // A weaker knock still extends a shake that is nearly over.
      _remaining = seconds * 0.5;
      _duration = math.max(_duration, _remaining);
    }
  }

  @override
  void update(double dt) {
    if (_remaining <= 0) return;

    _remaining -= dt;
    if (_remaining <= 0) {
      _remaining = 0;
      _amplitude = 0;
      game.camera.viewfinder.position = _rest;
      return;
    }

    // Squared falloff: hits hard, settles quickly.
    final t = _remaining / _duration;
    final strength = _amplitude * t * t;

    game.camera.viewfinder.position = Vector2(
      (_random.nextDouble() * 2 - 1) * strength,
      (_random.nextDouble() * 2 - 1) * strength,
    );
  }
}
