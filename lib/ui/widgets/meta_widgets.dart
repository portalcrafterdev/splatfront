import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';
import 'motion.dart';
import '../../core/save/player_profile.dart';
import '../type.dart';

/// Shared header for the meta screens: what this page is, and the two
/// numbers you spend, kept in sight while you spend them.
///
/// A card rather than an `AppBar`, and that is the point. Home wears a heavy
/// bordered band with an offset shadow, and every other tab used to drop it
/// for a flat title — so the app read as one designed screen and three
/// settings pages. This is the same block in a quieter register: same corner,
/// same border weight, same shadow, cream instead of orange, because orange
/// is spent on Home and on the button you are meant to press.
///
/// It also had `titleSpacing: 0`, which put the first letter of every page
/// title hard against the edge of the screen.
class MetaHeader extends StatelessWidget {
  const MetaHeader({
    super.key,
    required this.title,
    required this.profile,
    this.subtitle,
  });

  final String title;
  final PlayerProfile profile;

  /// One line on what the page is for. Worth writing when the page cannot
  /// say it by itself; leave it off when the content is self-evident.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: Palette.uiSurfaceHigh,
        borderRadius: BorderRadius.circular(20),
        // Outlined, like every other surface in the app again. It had gone
        // soft along with the rest; it is the first thing on every page, so
        // leaving it soft while the tiles below it went back to a hard edge
        // would make the header the one flat object on a page of chunky ones.
        border: Border.all(color: Palette.outline, width: Panel.stroke),
        boxShadow: const [
          BoxShadow(
            color: Palette.outlineShadow,
            offset: Offset(0, Panel.lift),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Fonts.display,
                    color: Palette.uiText,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CurrencyChip(
                icon: Icons.emoji_events,
                value: profile.trophies,
                colour: Palette.info,
              ),
              const SizedBox(width: 6),
              CurrencyChip(
                icon: Icons.monetization_on,
                value: profile.coins,
                colour: Palette.accent,
              ),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 5),
            Text(
              sub,
              style: const TextStyle(
                color: Palette.uiTextDim,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A heading over a group, with the count that makes it worth reading.
///
/// Sentence case, not a tracked-out capitalised eyebrow. Six of those across
/// three screens said nothing that the rows underneath did not already say —
/// "AUDIO" over a slider labelled Music is a label on a label.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});

  final String text;

  /// The number, if there is one worth showing. This is the part that earns
  /// the heading its line.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final count = trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // Both halves give way rather than pushing the row off the screen.
          //
          // Two plain Texts in a Row have no give at all, and the counts here
          // grow with the save: "Level 250" beside "738 of 3000 stars" is
          // wider than a 360dp phone once the campaign is a few hundred
          // levels in. The heading truncates first, because the count is the
          // half that changes and the half worth reading.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: Fonts.display,
                color: Palette.uiText,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                count,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.uiTextDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CurrencyChip extends StatelessWidget {
  const CurrencyChip({
    super.key,
    required this.icon,
    required this.value,
    required this.colour,
  });

  final IconData icon;
  final int value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Palette.uiSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colour.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 5),
        // Counts rather than snaps: these two numbers are the reward for the
        // last match, and a number that jumps gives that away for free.
        AnimatedCount(
          value: value,
          style: const TextStyle(
            color: Palette.uiText,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

/// A short, human duration: "2h 14m", "8m 03s", "12s".
String formatDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }
  return '${d.inSeconds}s';
}

/// Progress you can count, for a target small enough to be worth counting.
///
/// "3 / 15" asks the reader to hold two numbers and divide one by the other.
/// Fifteen squares, four of them filled, asks them to look. That is the whole
/// argument, and it is the reason this exists: the audience is six to ten,
/// and a fraction is a year-four idea.
///
/// **Only for small targets.** Past [max] the pips get too narrow to tell
/// apart on a phone and counting them is slower than reading a bar, so a
/// quest like "paint 60% in a match" keeps its bar. [suits] is the test;
/// callers should ask it rather than guessing, so the cutover happens in one
/// place.
class Pips extends StatelessWidget {
  const Pips({
    super.key,
    required this.done,
    required this.target,
    this.colour = Palette.lime,
    this.doneColour = Palette.success,
  });

  final int done;
  final int target;

  /// Part-done. Lime rather than green: green is the colour of finished, and
  /// a row of green squares with two gaps in it reads as finished-with-gaps.
  final Color colour;

  /// All of them. The row turns green together, which is the moment worth
  /// marking.
  final Color doneColour;

  /// The most pips worth drawing.
  static const int max = 15;

  /// Whether a target this size should be pips at all.
  static bool suits(int target) => target > 0 && target <= max;

  @override
  Widget build(BuildContext context) {
    final complete = done >= target;
    final fill = complete ? doneColour : colour;

    return Semantics(
      // The pips are decoration to a screen reader; the numbers are not.
      label: '$done of $target',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < target; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: i < done ? fill : Palette.uiBackground,
                    borderRadius: BorderRadius.circular(3),
                    // Only the empty ones are drawn as outlines — they are
                    // the holes still waiting to be filled, and a hole is an
                    // edge with nothing in it. A filled pip is just the
                    // colour: at 10dp a line around it eats most of the
                    // square it is supposed to be framing.
                    border: i < done
                        ? null
                        : Border.all(
                            color: Palette.uiTextDim.withValues(alpha: 0.3),
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One card stat as a bar, measured against the whole roster.
///
/// **This replaces printed numbers, and the reason is the audience.** "620 HP,
/// 40 damage, 0.8/s" is three units of measurement and a rate; it tells an
/// eight-year-old nothing, and it tells most adults nothing either without a
/// second card to compare it to. A bar is that comparison, built in: the
/// track is the strongest card in the set, so a short bar means *short for a
/// Splatfront card* rather than short on some invisible absolute scale.
///
/// The numbers themselves are untouched — they still live in `cards.json` and
/// still drive the match. Only the display changes.
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    required this.colour,
    this.growth,
  });

  final String label;

  /// 0 to 1, already divided by the roster's best.
  final double value;

  final Color colour;

  /// What one level adds, like "+8%". Null for the stats levelling does not
  /// touch — paint radius and speed never move, and printing "+0%" beside
  /// them would be worse than saying nothing.
  final String? growth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              color: Palette.uiTextDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 11,
              child: ColoredBox(
                color: Palette.uiBackground,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    // A bar with no child is zero-sized, and a fractional box
                    // needs to be told to fill its cross axis.
                    heightFactor: 1,
                    // Never quite nothing. The weakest card in the set still
                    // has the stat, and an empty track reads as "this card
                    // does not do this at all" — which is only true of a
                    // paint value of zero, and those get no bar.
                    widthFactor: value.clamp(0.06, 1.0),
                    child: ColoredBox(color: colour),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            growth ?? '',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Palette.lime,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A countdown drawn as a ring that fills, with no digits in it.
///
/// **This is the least child-readable element the app had.** "2h 41m" asks
/// for two units, base sixty, and a sense of how long an hour is — the last
/// of which a six-year-old does not have. A ring answers the only question
/// they are actually asking, which is *how much is left*, by showing it.
///
/// Deliberately not animated. It is redrawn by the screen's one-second tick
/// like the digits it replaced, and a tween on top of that would be a second
/// animation chasing the first. Nothing here loops.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.colour,
    this.size = 62,
    this.track,
    this.child,
  });

  /// 0 to 1.
  final double value;
  final Color colour;
  final double size;
  final Color? track;

  /// Drawn in the middle of the ring, usually the chest itself.
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(
            value: value.clamp(0.0, 1.0),
            colour: colour,
            track: track ?? Palette.uiBackground,
          ),
        ),
        ?child,
      ],
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.colour,
    required this.track,
  });

  final double value;
  final Color colour;
  final Color track;

  static const double _width = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (size.shortestSide - _width) / 2;

    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawCircle(centre, radius, brush..color = track);
    if (value <= 0) return;

    // From the top, clockwise, which is the direction a clock face and every
    // loading ring anyone has ever seen both go.
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      brush..color = colour,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.colour != colour || old.track != track;
}
