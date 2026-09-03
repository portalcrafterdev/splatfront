import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../game/arena/paint_sampler.dart';

/// The scoreboard: **your** colour fills from the left, the opponent's from
/// the right, and the two meet at the current split. The gap between them is
/// neutral ground.
///
/// Keyed to the sides rather than to the colours. The "You" plate sits at the
/// top left, so the bar filling from the left has to be yours — hard-coding
/// red on the left put the player's own colour on the wrong end the moment
/// the player stopped being red.
///
/// Driven straight off the arena's [ValueNotifier] so nothing in the widget
/// tree above the arena ever rebuilds.
class CoverageBar extends StatelessWidget {
  const CoverageBar({
    super.key,
    required this.coverage,
    required this.playerTeam,
    this.height = 26,
    this.showLabels = true,
  });

  final ValueListenable<Coverage> coverage;

  /// Whose side the left-hand end belongs to.
  final Team playerTeam;
  final double height;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Coverage>(
      valueListenable: coverage,
      builder: (context, value, _) {
        return TweenAnimationBuilder<double>(
          duration: Timings.coverageLerp,
          curve: Curves.easeOut,
          tween: Tween(begin: 0, end: value.forTeam(playerTeam)),
          builder: (context, mine, _) {
            return TweenAnimationBuilder<double>(
              duration: Timings.coverageLerp,
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: value.forTeam(playerTeam.opponent)),
              builder: (context, theirs, _) =>
                  _bar(context, mine: mine, theirs: theirs),
            );
          },
        );
      },
    );
  }

  Widget _bar(
    BuildContext context, {
    required double mine,
    required double theirs,
  }) {
    final neutral = (1.0 - mine - theirs).clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            // Stretch, not the default centre: a ColoredBox with no child is
            // zero-height, so a centred row would paint nothing at all.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: (mine * 10000).round(),
                child: ColoredBox(color: Palette.of(playerTeam)),
              ),
              Expanded(
                flex: (neutral * 10000).round(),
                child: const ColoredBox(color: Palette.neutral),
              ),
              Expanded(
                flex: (theirs * 10000).round(),
                child: ColoredBox(color: Palette.of(playerTeam.opponent)),
              ),
            ],
          ),

          // A lit top edge and a shaded bottom, so the bar reads as a moulded
          // meter rather than as two flat swatches butted together. Cheap:
          // one gradient over the whole strip, no per-side work.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x24FFFFFF),
                    Color(0x00FFFFFF),
                    Color(0x1F000000),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // The halfway mark.
          //
          // Without it this bar makes you *read* to find out who is winning:
          // two percentages, subtract one from the other. With it the answer
          // is a shape — the seam between the colours is left of the tick or
          // right of it, and that is legible from the corner of the eye while
          // you are looking at the arena. It is a tug-of-war rope, and a
          // tug-of-war needs a centre line.
          if (showLabels) const Center(child: _HalfwayTick()),

          if (showLabels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_percent(mine), _percent(theirs)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _percent(double value) => Text(
    '${(value * 100).round()}%',
    style: const TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      shadows: [Shadow(color: Color(0x99000000), blurRadius: 2)],
    ),
  );
}

/// The 50% line, drawn light with a dark hairline down each side.
///
/// It has to stay visible while sitting on either team colour — and on
/// neutral grey between them — so it cannot be a single flat tone: a white
/// line vanishes on pale neutral and a dark one vanishes on blue. The
/// sandwich reads on all three.
class _HalfwayTick extends StatelessWidget {
  const _HalfwayTick();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: SizedBox(
      width: 4,
      height: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0x59000000),
              Color(0xE6FFFFFF),
              Color(0xE6FFFFFF),
              Color(0x59000000),
            ],
            stops: [0.0, 0.25, 0.75, 1.0],
          ),
        ),
      ),
    ),
  );
}
