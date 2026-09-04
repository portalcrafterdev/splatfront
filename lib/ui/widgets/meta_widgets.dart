import 'package:flutter/material.dart';

import '../../core/palette.dart';
import 'motion.dart';
import '../../core/save/player_profile.dart';

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
        color: Palette.uiSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.outline, width: 3),
        boxShadow: const [
          BoxShadow(color: Palette.outlineShadow, offset: Offset(0, 5)),
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
                    color: Palette.uiText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
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
                color: Palette.uiText,
                fontSize: 15,
                fontWeight: FontWeight.w900,
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
