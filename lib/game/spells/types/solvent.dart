import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../../cards/card_model.dart';
import '../../splatfront_game.dart';
import '../spell.dart';

/// Wipes the ground to neutral. Nobody's colour, so nobody may deploy there
/// — including the side that threw it. Purely defensive.
class Solvent extends Spell {
  const Solvent();

  @override
  void cast({
    required SplatfrontGame game,
    required Team caster,
    required Vector2 at,
    required SpellStats stats,
  }) {
    // No damage, and it does not care whose paint it erases.
    game.arena.paintLayer.stampSpell(at, stats.radius, Team.neutral);
  }
}
