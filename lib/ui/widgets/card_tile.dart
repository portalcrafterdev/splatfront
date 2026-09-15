import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../game/cards/card_model.dart';
import 'unit_art_view.dart';
import '../type.dart';

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
            // Softened with the menus, on the owner's call.
            //
            // This was a heavy dark line, matching the one every menu tile
            // used to wear, and the argument for it was about the *arena*
            // rather than the collection: on a busy sky a card with a faint
            // edge stops being an object and starts being a smudge. That risk
            // is real and this is the line to thicken if the hand ever gets
            // hard to pick out mid-match. What holds a card together now is
            // the shadow below and the fact that it is the lightest thing on
            // the screen, both of which survive a sky behind them.
            // Back to a heavy line, with the rest of the app. The note that
            // replaced it with a hairline named the real risk and it still
            // stands: on a busy sky a card with a faint edge stops being an
            // object and starts being a smudge. That argument was always for
            // the heavy line, not against it.
            border: Border.all(
              color: affordable
                  ? Palette.hudOutline
                  : Palette.hudOutline.withValues(alpha: 0.45),
              width: 2 * scale,
            ),
            // Lighter at the top, so the light source overhead is the same
            // one the arena bezel and every menu surface assume. The tint is
            // the card's kind — teal for a body, magenta for a spell — laid
            // into the foot of the gradient rather than announced.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Palette.hudSurface,
                Color.lerp(Palette.hudSurfaceLow, tint, 0.12)!,
              ],
            ),
            // The hand is the one thing on this screen you touch, and it was
            // sitting flush against the background like a printed panel. A
            // card you can pay for is lifted; one you cannot is flat on the
            // floor, which is a second, wordless reading of the same fact
            // the dimming already gives.
            //
            // Carrying more of the load now that the edge is a hairline: a
            // tight contact shadow plus a wider ambient one, which is what
            // gives a borderless card its shape against both a pale page and
            // a sky.
            // Hard and offset, not blurred — a soft shadow under a hard line
            // reads as a rendering mistake. A card you can pay for is lifted
            // off the tray; one you cannot is flat on it, which is a second,
            // wordless reading of the same fact the dimming already gives.
            boxShadow: affordable && !dragging
                ? [
                    BoxShadow(
                      color: Palette.hudOutline,
                      offset: Offset(0, 3 * scale),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: _art()),
                // The cost is the one number checked before every single
                // play — against the elixir bar four millimetres below it —
                // and it was sharing a line with the card's name in 11pt.
                // Its own corner, at its own size, is what that deserves.
                Positioned(
                  top: 3 * scale,
                  left: 3 * scale,
                  child: _costBadge(),
                ),
                // Yields the corner to the countdown. The body count is a
                // permanent fact about the card and will still be there in
                // five seconds; the number of seconds left will not.
                if (card.bodyCount > 1 && !onCooldown)
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
  /// the seconds left in a corner badge. It falls as the card comes back.
  ///
  /// The number used to sit dead centre at 22pt, over the character.
  /// **Playing any card locks the whole hand**, so all four cards wore the
  /// same digit at the same moment — in the largest, most central mark each
  /// one had. Four cards whose whole job is to be told apart at a glance,
  /// every one of them shouting the single thing they had in common, right
  /// across the art that distinguishes them.
  ///
  /// The blind is what says "not yet", and it does that without a number at
  /// all. The digit only says how long, which is a corner's job.
  Widget _shutter() => Stack(
    fit: StackFit.expand,
    children: [
      Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: cooldown.clamp(0.0, 1.0),
          child: ColoredBox(
            color: Palette.hudBackground.withValues(alpha: 0.62),
          ),
        ),
      ),
      Positioned(top: 3 * scale, right: 3 * scale, child: _lockBadge()),
    ],
  );

  /// The seconds left, built like [_costBadge] so the two corners match.
  Widget _lockBadge() => Container(
    width: 18 * scale,
    height: 18 * scale,
    decoration: BoxDecoration(
      color: Palette.hudBackground.withValues(alpha: 0.88),
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.9),
        width: 1.5 * scale,
      ),
    ),
    alignment: Alignment.center,
    child: FittedBox(
      child: Padding(
        padding: EdgeInsets.all(2 * scale),
        child: Text(
          cooldownSeconds.ceil().toString(),
          style: const TextStyle(
            fontFamily: Fonts.display,
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );

  Widget _art() {
    if (card.isSpell) {
      return Padding(
        padding: EdgeInsets.only(bottom: height * 0.18),
        child: Icon(
          _spellIcons[card.id] ?? Icons.auto_awesome,
          size: width * 0.5,
          color: Palette.elixir,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: height * 0.14),
      child: UnitArtView(cardId: card.id, size: height * 0.78, team: team),
    );
  }

  /// The name, on a strip dark enough to stay readable over the art.
  ///
  /// It fades up into the art rather than butting against it with a hard
  /// edge: a flat bar across the bottom of a small tile cuts the character
  /// in half, and the character is how a card is actually recognised.
  Widget _footer() => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(4 * scale, 6 * scale, 4 * scale, 3 * scale),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Palette.hudSurfaceLow.withValues(alpha: 0.0),
          Palette.hudSurfaceLow,
        ],
      ),
    ),
    // scaleDown, never plain FittedBox.
    //
    // The name used to sit in a Row beside the cost badge, where Flexible
    // bounded it. Alone in a full-width strip a bare FittedBox has nothing
    // stopping it, and it scales text *up* to fill the box as happily as
    // down — which turned every card name into a headline twice the size of
    // the card's own art.
    child: FittedBox(
      fit: BoxFit.scaleDown,
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
  );

  Widget _costBadge() => Container(
    width: 21 * scale,
    height: 21 * scale,
    decoration: BoxDecoration(
      color: affordable ? Palette.elixir : Palette.hudTextDim,
      shape: BoxShape.circle,
      // A dark ring, because the badge sits over the art rather than over a
      // known ground, and a bare magenta disc on a pale unit disappears.
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.9),
        width: 1.5 * scale,
      ),
    ),
    alignment: Alignment.center,
    child: FittedBox(
      child: Padding(
        padding: EdgeInsets.all(2 * scale),
        child: Text(
          '${card.cost}',
          style: const TextStyle(
            fontFamily: Fonts.display,
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );

  Widget _count() => Container(
    padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
    decoration: BoxDecoration(
      color: Palette.hudBackground.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(6 * scale),
    ),
    child: Text(
      'x${card.bodyCount}',
      style: TextStyle(
        color: Colors.white,
        fontSize: 9 * scale,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
