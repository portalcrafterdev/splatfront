import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../../cards/card_model.dart';
import '../../splatfront_game.dart';
import '../spell.dart';

/// Stops a push dead. No damage, and no paint either — Freeze buys time,
/// it does not take ground.
class Freeze extends Spell {
  const Freeze();

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
      exceptTeam: caster,
    )) {
      unit.stun(stats.duration);
    }
  }
}
