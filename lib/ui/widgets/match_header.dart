import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../game/arena/paint_sampler.dart';
import '../../game/bot/bot_difficulty.dart';
import '../../game/match/match_controller.dart';
import 'coverage_bar.dart';
import 'match_overlays.dart';

/// Who is playing, who is winning, and how long is left — the block above the
/// arena.
///
/// Two name plates flank the score so a glance at the top of the screen tells
/// you which colour you are, which is the one thing the arena itself never
/// says out loud.
class MatchHeader extends StatelessWidget {
  const MatchHeader({
    super.key,
    required this.coverage,
    required this.match,
    required this.playerTeam,
    required this.botTier,
    this.showPlates = true,
  });

  final ValueListenable<Coverage> coverage;
  final MatchController? match;
  final Team playerTeam;
  final BotTier botTier;

  /// The debug sandboxes have no opponent, so they skip the plates.
  final bool showPlates;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showPlates)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
          child: Row(
            children: [
              _NamePlate(team: playerTeam, name: 'You', alignEnd: false),
              const Spacer(),
              _NamePlate(
                team: playerTeam.opponent,
                name: botTier.opponentName,
                alignEnd: true,
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CoverageBar(coverage: coverage, playerTeam: playerTeam),
        ),
      ),
      const SizedBox(height: 5),
      _TimerPill(match: match),
      const SizedBox(height: 5),
    ],
  );
}

/// A team's colour, emblem and name, on the side of the screen it fights for.
class _NamePlate extends StatelessWidget {
  const _NamePlate({
    required this.team,
    required this.name,
    required this.alignEnd,
  });

  final Team team;
  final String name;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colour = Palette.of(team);
    final emblem = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.opacity, size: 13, color: Colors.white),
    );
    final label = Text(
      name,
      style: TextStyle(
        color: colour,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colour.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignEnd
            ? [label, const SizedBox(width: 6), emblem]
            : [emblem, const SizedBox(width: 6), label],
      ),
    );
  }
}

/// The clock, on a pill so it reads as a readout rather than as loose text.
///
/// The pill turns with the clock rather than leaving the digits to do it
/// alone. In the last ten seconds a player is looking at the arena, not at
/// the top of the screen, and a colour change confined to four small
/// characters is not something peripheral vision picks up.
class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.match});

  final MatchController? match;

  @override
  Widget build(BuildContext context) {
    final match = this.match;
    if (match == null) return _pill(urgent: false);

    return ValueListenableBuilder<MatchPhase>(
      valueListenable: match.phase,
      builder: (context, phase, _) => ValueListenableBuilder<double>(
        valueListenable: match.timeRemaining,
        builder: (context, remaining, _) => _pill(
          urgent:
              phase == MatchPhase.suddenDeath ||
              (phase == MatchPhase.playing && remaining.ceil() <= 10),
        ),
      ),
    );
  }

  Widget _pill({required bool urgent}) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    decoration: BoxDecoration(
      color: urgent
          ? Palette.accent.withValues(alpha: 0.18)
          : Palette.hudSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: urgent
            ? Palette.accent
            : Palette.hudTextDim.withValues(alpha: 0.28),
        width: urgent ? 1.5 : 1,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timer_outlined,
          size: 13,
          color: urgent ? Palette.accent : Palette.hudTextDim,
        ),
        const SizedBox(width: 6),
        MatchTimer(match: match),
      ],
    ),
  );
}

extension BotTierPlate on BotTier {
  /// What the opponent is called on their name plate. Ours, not a borrowed
  /// roster: section 14 rules out another game's names.
  ///
  /// Every one of them says "Bot", and that is not decoration. Section 17
  /// rule 6: v1 is single player and has to say so plainly on the battle
  /// screen. "Novice" and "Veteran" on their own read as the handles of real
  /// people, which is the fake-opponent-name trick the reference game's
  /// reviews punish — not for lacking multiplayer, but for implying it.
  String get opponentName => switch (this) {
    BotTier.easy => 'Novice Bot',
    BotTier.normal => 'Rival Bot',
    BotTier.hard => 'Veteran Bot',
  };
}
