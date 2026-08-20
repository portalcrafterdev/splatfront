import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../../cards/card_model.dart';
import '../../splatfront_game.dart';
import '../spell.dart';

/// Damage plus a full recolour. The bread and butter: it clears a landing
/// zone and gives you the ground to land on in one throw.
class PaintBomb extends Spell {
  const PaintBomb();

  @override
  void cast({
    required SplatfrontGame game,
    required Team caster,
    required Vector2 at,
    required SpellStats stats,
  }) {
    // Enemies only. A spell that hurt your own push would make the card
    // unplayable behind a front line, which is exactly where it is wanted.
    for (final unit in Spell.unitsInRadius(
      game,
      at,
      stats.radius,
      exceptTeam: caster,
    )) {
      unit.takeDamage(stats.damage);
    }

    game.arena.paintLayer.stampSpell(at, stats.radius, caster);
  }
}
