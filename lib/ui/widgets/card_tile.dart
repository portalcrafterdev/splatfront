import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../game/cards/card_model.dart';
import 'unit_art_view.dart';

/// One card in the hand.
///
/// A troop card draws the character it actually deploys, using the same art
/// the arena does, so you pick a card by recognising the thing rather than by
/// reading its name. A card you cannot pay for is dimmed and its cost badge
/// goes flat, so the reason it is unplayable is visible at a glance.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.width,
    this.affordable = true,
    this.dragging = false,
    this.scale = 1.0,
    this.cooldown = 0,
    this.cooldownSeconds = 0,
    this.team = Team.blue,
  });

  final CardModel card;
  final double width;
  final bool affordable;

  /// Whose card this is, which is whose colour the character is drawn in.
  ///
  /// Defaults to the player's side. A card in your hand showing the enemy's
  /// colour is the sort of thing you only notice once and then cannot stop
  /// seeing — and it happened the moment the player stopped being red.
  final Team team;

  /// How much of the slot's cooldown is left, 1 down to 0.
  ///
  /// The card is visible the whole time — you should be able to plan around
  /// what is coming — but it is dimmed under a falling shutter with the
  /// seconds on it, so a card you cannot play never looks like a card that is
  /// simply not responding.
  final double cooldown;

  /// Whole seconds left, for the number on the shutter.
  final double cooldownSeconds;

  bool get onCooldown => cooldown > 0;

  /// True while this card is the one being dragged over the arena.
  final bool dragging;

  /// The next-card preview renders at 60%.
  final double scale;

  double get height => width * 1.25;

  /// Spells have no body to draw, so each gets its own mark instead.
  static const Map<String, IconData> _spellIcons = <String, IconData>{
    'paint_bomb': Icons.bubble_chart,
    'freeze': Icons.ac_unit,
    'solvent': Icons.opacity,
    'surge': Icons.bolt,
  };

  @override
  Widget build(BuildContext context) {
    final tint = card.isSpell ? Palette.elixir : Palette.accent;
    final radius = BorderRadius.circular(10 * scale);

    return Opacity(
      opacity: dragging
          ? 0.35
          : onCooldown
          ? 0.75
          : (affordable ? 1.0 : 0.5),
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: affordable
                  ? tint.withValues(alpha: 0.9)
                  : Palette.hudTextDim.withValues(alpha: 0.35),
              width: affordable ? 2 : 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Palette.hudSurface,
                Color.lerp(Palette.hudSurface, tint, 0.18)!,
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: _art()),
                if (card.bodyCount > 1)
                  Positioned(top: 3 * scale, right: 5 * scale, child: _count()),
                Positioned(left: 0, right: 0, bottom: 0, child: _footer()),
                if (onCooldown) Positioned.fill(child: _shutter()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A dark shutter covering the fraction of the cooldown still to run, with
  /// the seconds left over it. It falls as the card comes back.
  Widget _shutter() => Stack(
    fit: StackFit.expand,
    children: [
      Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: cooldown.clamp(0.0, 1.0),
          child: ColoredBox(
            color: Palette.hudBackground.withValues(alpha: 0.72),
          ),
        ),
      ),
      Center(
        child: Text(
          cooldownSeconds.ceil().toString(),
          style: TextStyle(
            color: Palette.hudText,
            fontSize: 22 * scale,
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4)],
          ),
        ),
      ),
    ],
  );

  Widget _art() {
    if (card.isSpell) {
      return Padding(
        padding: EdgeInsets.only(bottom: height * 0.18),
        child: Icon(
          _spellIcons[card.id] ?? Icons.auto_awesome,
          size: width * 0.46,
          color: Palette.elixir,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: height * 0.14),
      child: UnitArtView(cardId: card.id, size: height * 0.72, team: team),
    );
  }

  /// Name and cost, on a strip dark enough to stay readable over the art.
  Widget _footer() => Container(
    padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 2 * scale),
    color: Palette.hudBackground.withValues(alpha: 0.78),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _costBadge(),
        SizedBox(width: 4 * scale),
        Flexible(
          child: FittedBox(
            child: Text(
              card.name,
              maxLines: 1,
              style: TextStyle(
                color: Palette.hudText,
                fontSize: 11 * scale,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _costBadge() => Container(
    width: 18 * scale,
    height: 18 * scale,
    decoration: BoxDecoration(
      color: affordable ? Palette.elixir : Palette.hudTextDim,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: FittedBox(
      child: Padding(
        padding: EdgeInsets.all(2 * scale),
        child: Text(
          '${card.cost}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );

  Widget _count() => Container(
    padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
    decoration: BoxDecoration(
      color: Palette.hudBackground.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(6 * scale),
    ),
    child: Text(
      'x${card.bodyCount}',
      style: TextStyle(
        color: Palette.hudText,
        fontSize: 9 * scale,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
