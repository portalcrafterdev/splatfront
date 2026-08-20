import 'package:flame/components.dart';

import '../../core/palette.dart';
import '../cards/card_model.dart';
import '../splatfront_game.dart';
import '../units/unit.dart';
import 'types/freeze.dart';
import 'types/paint_bomb.dart';
import 'types/solvent.dart';
import 'types/surge.dart';

/// What a spell does when it lands.
///
/// Spells are the one thing that ignores the deploy rule: they may be thrown
/// anywhere on the arena, including deep in enemy paint. That is what makes
/// Paint Bomb able to open a landing zone where you have none.
abstract class Spell {
  const Spell();

  /// [caster] is the side that played it, and [at] is in world units.
  void cast({
    required SplatfrontGame game,
    required Team caster,
    required Vector2 at,
    required SpellStats stats,
  });

  /// Every unit inside the blast, filtered by side.
  ///
  /// A dying unit is skipped: a corpse mid-fade should not soak a Freeze.
  static List<Unit> unitsInRadius(
    SplatfrontGame game,
    Vector2 at,
    double radius, {
    Team? onlyTeam,
    Team? exceptTeam,
  }) {
    final squared = radius * radius;
    return [
      for (final unit in game.units)
        if (unit.isAlive &&
            (onlyTeam == null || unit.team == onlyTeam) &&
            (exceptTeam == null || unit.team != exceptTeam) &&
            unit.position.distanceToSquared(at) <= squared)
          unit,
    ];
  }
}

/// Which spell effect maps to which implementation.
///
/// Keyed by the `effect` string in `cards.json`, so adding a spell is a JSON
/// entry plus one class here.
const Map<SpellEffect, Spell> spellsByEffect = <SpellEffect, Spell>{
  SpellEffect.damageAndPaint: PaintBomb(),
  SpellEffect.stun: Freeze(),
  SpellEffect.wipeToNeutral: Solvent(),
  SpellEffect.buff: Surge(),
};
