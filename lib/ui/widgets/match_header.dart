import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../game/arena/paint_sampler.dart';
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
    this.showPlates = true,
    this.onPause,
  });

  final ValueListenable<Coverage> coverage;
  final MatchController? match;
  final Team playerTeam;

  /// The debug sandboxes have no opponent, so they skip the plates.
  final bool showPlates;

  /// Stops the clock. Null in the sandboxes, which have no match to pause.
  final VoidCallback? onPause;

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
                name: opponentName,
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
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (onPause != null) const SizedBox(width: 42),
          _TimerPill(match: match),
          if (onPause case final pause?) ...[
            const SizedBox(width: 8),
            _PauseButton(onPressed: pause),
          ],
        ],
      ),
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
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.brush_rounded, size: 12, color: Colors.white),
    );
    final label = Text(
      name,
      style: TextStyle(
        color: colour,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.3,
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colour.withValues(alpha: 0.16),
          Palette.hudSurface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
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
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: urgent ? Palette.accent : Palette.hudBezelLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Palette.hudOutline.withValues(alpha: 0.28),
        width: 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x38000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        MatchTimer(match: match, ink: Colors.white),
      ],
    ),
  );
}

/// Stops the clock.
///
/// Sized and grounded like the clock beside it rather than as a bare icon:
/// it sits over sky and cloud, and an unfilled glyph on that ground is
/// invisible half the time. The blank of the same width on the other side of
/// the pill is what keeps the clock centred on the screen, which is where the
/// eye goes for it.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Pause',
    child: GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.hudBezelLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
        color: Palette.hudOutline.withValues(alpha: 0.28),
        width: 1,
      ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.pause_rounded, size: 18, color: Colors.white),
      ),
    ),
  );
}

/// What the opponent is called on their name plate.
///
/// These used to read "Novice Bot", "Rival Bot", "Veteran Bot", on the
/// section 17 rule 6 argument that v1 has to say plainly it is single
/// player. **The word was dropped on the owner's call**, and the rule it
/// was serving still holds: what the reference game's reviews punish is
/// implying an opponent who is not there, not the absence of multiplayer.
///
/// "Red Team" is the side you are actually fighting. It is true, it is a
/// phrase everybody knows, and it cannot be mistaken for somebody's handle
/// — which is the only part of this that would be a lie. The plain
/// statement moved to the Levels page and the store listing, which is where
/// a promise to a player is actually made. What must never come back is a
/// *personal* name on that plate; `roster_rules_test.dart` is what stops it.
///
/// It does not vary by level, and there is nothing left for it to vary by:
/// difficulty tiers are gone, so the only opponent the game has is the side
/// itself. Three near-identical plates were three ways of saying red.
const String opponentName = 'Red Team';
