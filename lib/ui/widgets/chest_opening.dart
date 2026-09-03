import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/audio.dart';
import '../../core/palette.dart';
import '../../game/cards/card_registry.dart';
import '../../game/units/unit_art.dart';
import '../../meta/chests.dart';
import 'unit_art_view.dart';

/// The chest opening, as a moment rather than a list.
///
/// Opening used to drop an alert dialog with the contents written out, which
/// is accurate and completely flat — the reward for winning a match and
/// waiting out a timer should be worth watching. This shakes the chest until
/// it bursts, flashes, and then deals the rewards out one at a time.
///
/// It is a route rather than a widget on the chest screen so it owns the
/// whole screen while it runs, and so dismissing it is just a pop.
Future<void> showChestOpening(
  BuildContext context, {
  required ChestReward reward,
  required String chestName,
  required CardRegistry cards,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Palette.uiBackground.withValues(alpha: 0.94),
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    // Transparent Material, so the barrier still shows through. Without a
    // Material above them every Text on this route fell back to Flutter's
    // "you forgot the Material" style and drew itself with a yellow underline,
    // which is what every label on the reward screen was wearing.
    pageBuilder: (_, _, _) => Material(
      type: MaterialType.transparency,
      child: _ChestOpening(reward: reward, chestName: chestName, cards: cards),
    ),
  ),
);

class _ChestOpening extends StatefulWidget {
  const _ChestOpening({
    required this.reward,
    required this.chestName,
    required this.cards,
  });

  final ChestReward reward;
  final String chestName;
  final CardRegistry cards;

  @override
  State<_ChestOpening> createState() => _ChestOpeningState();
}

class _ChestOpeningState extends State<_ChestOpening>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  /// Where the chest stops shaking and bursts, as a fraction of the run.
  static const double _burst = 0.42;

  /// Fired once, at the burst, rather than when the button was pressed —
  /// the sound should land with the picture.
  bool _banged = false;

  @override
  void initState() {
    super.initState();
    _controller
      ..addListener(_onTick)
      ..forward();
  }

  void _onTick() {
    if (!_banged && _controller.value >= _burst) {
      _banged = true;
      Audio.play(Sfx.chestOpen);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  /// Skips to the end on a tap, so nobody has to sit through it twice.
  void _skipOrClose() {
    if (_controller.isAnimating) {
      _controller.forward(from: 1.0);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.reward.cards.entries.toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skipOrClose,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final opened = t >= _burst;
          // 0 before the burst, ramping to 1 over the rest of the run.
          final reveal = opened
              ? ((t - _burst) / (1 - _burst)).clamp(0.0, 1.0)
              : 0.0;

          return SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The chest's box gives back its height once the chest has
                // gone. It used to be a fixed 190, so after the burst an
                // empty 190-tall block stayed at the top of a centred column
                // and shoved every reward below it off centre — the column
                // was centred, the thing you were looking at was not.
                //
                // Collapsed after the flash rather than with it: the flash
                // ring expands from where the chest was, and moving that
                // while it plays would drag the burst up the screen.
                SizedBox(
                  height: 190 * (1 - _settle(reveal)),
                  child: Center(child: _chest(t, opened, reveal)),
                ),
                SizedBox(height: 8 * (1 - _settle(reveal))),
                Opacity(
                  opacity: reveal,
                  child: Text(
                    '${widget.chestName} chest',
                    style: const TextStyle(
                      color: Palette.uiTextDim,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _coins(reveal),
                const SizedBox(height: 18),
                Flexible(child: _cards(entries, reveal)),
                const SizedBox(height: 18),
                // The hint keeps its space whether or not it is showing, so
                // it cannot nudge everything above it a second time on the
                // frame it appears. It is *built* only once the run has
                // finished rather than hidden behind a zero opacity: while
                // the reveal is still playing a tap skips ahead, and saying
                // "tap to close" then would be a lie about what the tap does.
                SizedBox(
                  height: 20,
                  child: reveal >= 1
                      ? const Text(
                          'Tap to close',
                          style: TextStyle(
                            color: Palette.uiTextDim,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// How far through the settle the layout is: 0 until the flash has
  /// finished, then 0 to 1 as the chest's empty space is given back.
  double _settle(double reveal) => ((reveal - 0.35) / 0.35).clamp(0.0, 1.0);

  /// The chest itself: shakes harder and harder, then blows apart.
  Widget _chest(double t, bool opened, double reveal) {
    if (!opened) {
      // Shake amplitude ramps with the wind-up, so the burst feels earned.
      final wind = (t / _burst).clamp(0.0, 1.0);
      final shake = math.sin(t * 60) * 5 * wind;
      final tilt = math.sin(t * 44) * 0.06 * wind;
      return Transform.translate(
        offset: Offset(shake, 0),
        child: Transform.rotate(
          angle: tilt,
          child: Transform.scale(
            scale: 1 + wind * 0.25,
            child: const Icon(
              Icons.inventory_2,
              size: 96,
              color: Palette.accent,
            ),
          ),
        ),
      );
    }

    // The flash: a ring that expands and fades over the first slice of the
    // reveal, with the chest fading out behind it.
    final flash = (reveal / 0.35).clamp(0.0, 1.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        if (flash < 1)
          Container(
            width: 90 + 220 * flash,
            height: 90 + 220 * flash,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Palette.accent.withValues(alpha: 1 - flash),
                width: 6 * (1 - flash) + 1,
              ),
            ),
          ),
        Opacity(
          opacity: (1 - flash * 1.4).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1.25 + flash * 0.6,
            child: const Icon(
              Icons.inventory_2,
              size: 96,
              color: Palette.accent,
            ),
          ),
        ),
      ],
    );
  }

  /// Coins, counting up rather than simply appearing.
  Widget _coins(double reveal) {
    final shown = (widget.reward.coins * (reveal / 0.6).clamp(0.0, 1.0))
        .round();
    return Opacity(
      opacity: (reveal / 0.2).clamp(0.0, 1.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.monetization_on, color: Palette.accent, size: 26),
          const SizedBox(width: 10),
          Text(
            '$shown',
            style: const TextStyle(
              color: Palette.uiText,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Card copies, dealt out one after another.
  Widget _cards(List<MapEntry<String, int>> entries, double reveal) {
    if (entries.isEmpty) return const SizedBox.shrink();

    // The cards share the back half of the reveal, each with its own slot.
    const from = 0.35;
    final per = (1 - from) / entries.length;

    return SingleChildScrollView(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < entries.length; i++)
            _cardChip(
              entries[i],
              ((reveal - (from + per * i)) / per).clamp(0.0, 1.0),
            ),
        ],
      ),
    );
  }

  Widget _cardChip(MapEntry<String, int> entry, double t) {
    if (t <= 0) return const SizedBox.shrink();
    final card = widget.cards[entry.key];

    return Opacity(
      opacity: t,
      child: Transform.scale(
        // Overshoots a little on the way in, so each one pops, and settles
        // at exactly 1. It used to land at 1.15, so every tile rendered 15%
        // larger than the box it was laid out in and grew into its neighbours.
        scale: 0.6 + 0.4 * Curves.easeOutBack.transform(t),
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Palette.uiSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Palette.accent.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 46,
                child: card.isSpell
                    ? const Icon(
                        Icons.auto_awesome,
                        color: Palette.elixir,
                        size: 30,
                      )
                    : unitArt.containsKey(card.id)
                    ? UnitArtView(cardId: card.id, size: 46)
                    : const Icon(Icons.style, color: Palette.accent),
              ),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  card.name,
                  style: const TextStyle(
                    color: Palette.uiTextDim,
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                '+${entry.value}',
                style: const TextStyle(
                  color: Palette.uiText,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
