import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// The anti-air answer. Ranged, and the only common card that reaches both ground and air.
///
/// Fully stat-driven: everything that makes it distinct lives in
/// `cards.json`. This type names it and gives its Rive artboard a home.
class Pin extends Unit {
  Pin({required super.stats, required super.team, required super.position});

  static const String id = 'pin';
  static const String riveArtboard = 'pin';

  static Pin spawn(UnitStats stats, Team team, Vector2 position) =>
      Pin(stats: stats, team: team, position: position);

  @override
  void onAttack(Unit target) {
    // Visible, but carrying no paint: Pin claims ground by walking over it,
    // not by shooting at it.
    game.fireProjectile(
      from: position,
      at: target.position,
      team: team,
      speed: 18.0,
      size: 0.10,
    );
  }
}
