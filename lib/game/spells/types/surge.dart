import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../../cards/card_model.dart';
import '../../splatfront_game.dart';
import '../spell.dart';

/// Friendly units only: faster, and painting harder, for a few seconds.
/// The card that wins the last fifteen seconds of a close match.
class Surge extends Spell {
  const Surge();

  @override
  void cast({
    required SplatfrontGame game,
    required Team caster,
    required Vector2 at,
    required SpellStats stats,
  }) {
    for (final unit in Spell.unitsInRadius(
      game,
      at,
      stats.radius,
      onlyTeam: caster,
    )) {
      unit.applyBuff(
        seconds: stats.duration,
        speed: stats.speedMultiplier,
        paintRate: stats.paintRateMultiplier,
      );
    }
  }
}
