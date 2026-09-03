import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// Glass cannon. Longest reach in the set, dies to any rush.
///
/// Fully stat-driven: everything that makes it distinct lives in
/// `cards.json`. This type names it and gives its Rive artboard a home.
class SniperNib extends Unit {
  SniperNib({
    required super.stats,
    required super.team,
    required super.position,
  });

  static const String id = 'sniper_nib';
  static const String riveArtboard = 'sniper_nib';

  static SniperNib spawn(UnitStats stats, Team team, Vector2 position) =>
      SniperNib(stats: stats, team: team, position: position);

  @override
  void onAttack(Unit target) {
    // Fast and flat, to sell the eight units of range.
    game.fireProjectile(
      from: position,
      at: target.position,
      team: team,
      speed: 26.0,
      size: 0.09,
    );
  }
}
