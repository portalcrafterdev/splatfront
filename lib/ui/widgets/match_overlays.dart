import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../game/arena/paint_sampler.dart';
import '../../game/match/match_controller.dart';
import '../../game/match/match_result.dart';
import '../../meta/campaign.dart';
import 'coverage_bar.dart';
import 'match_background.dart';

/// The clock. Counts the countdown down to Splat, then normal time, then
/// sudden death, and turns amber in the last ten seconds.
class MatchTimer extends StatelessWidget {
  const MatchTimer({
    super.key,
    required this.match,
    this.ink = Palette.hudText,
  });

  final MatchController? match;

  /// The digits' colour when the clock is not urgent.
  ///
  /// The HUD's pill keeps a dark ground on a light screen — it is the readout
  /// glanced at most, and it has to hold up over cloud as well as over sky —
  /// so it passes white. The result overlay prints the same widget on a pale
  /// card and takes the default.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final match = this.match;
    if (match == null) return _TimerText(text: '--:--', colour: ink);

    return ValueListenableBuilder<MatchPhase>(
      valueListenable: match.phase,
      builder: (context, phase, _) => ValueListenableBuilder<double>(
        valueListenable: match.timeRemaining,
        builder: (context, remaining, _) {
          final seconds = remaining.ceil().clamp(0, 999);
          final urgent = phase == MatchPhase.suddenDeath || seconds <= 10;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phase == MatchPhase.suddenDeath)
                const Text(
                  'SUDDEN DEATH',
                  style: TextStyle(
                    color: Palette.accent,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              _TimerText(
                text: phase == MatchPhase.countdown
                    ? 'GET READY'
                    : _clock(seconds),
                colour: urgent && phase != MatchPhase.countdown
                    ? Palette.accent
                    : ink,
              ),
            ],
          );
        },
      ),
    );
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _TimerText extends StatelessWidget {
  const _TimerText({required this.text, this.colour = Palette.hudText});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      text,
      style: TextStyle(
        color: colour,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// 3, 2, 1, Splat, over the arena.
class CountdownOverlay extends StatelessWidget {
  const CountdownOverlay({super.key, required this.match});

  final MatchController match;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MatchPhase>(
      valueListenable: match.phase,
      builder: (context, phase, _) {
        if (phase != MatchPhase.countdown) return const SizedBox.shrink();

        return ValueListenableBuilder<double>(
          valueListenable: match.timeRemaining,
          builder: (context, remaining, _) {
            final number = remaining.ceil().clamp(0, 3);
            final label = number == 0 ? 'SPLAT!' : '$number';

            // Each number pops in as it changes.
            final within = 1.0 - (remaining - remaining.floorToDouble());

            return IgnorePointer(
              child: ColoredBox(
                color: Palette.hudBackground.withValues(alpha: 0.45),
                child: Center(
                  child: Transform.scale(
                    scale: 0.8 + 0.4 * (1 - within).clamp(0.0, 1.0),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: number == 0
                            ? Palette.accent
                            : Palette.hudOnScrim,
                        fontSize: number == 0 ? 48 : 88,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        shadows: const [
                          Shadow(color: Color(0xAA000000), blurRadius: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The full-screen sweep that plays when someone is wiped out at 95%.
class WipeOverlay extends StatelessWidget {
  const WipeOverlay({super.key, required this.match});

  final MatchController match;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: match.wipeProgress,
      builder: (context, progress, _) {
        if (progress <= 0) return const SizedBox.shrink();
        final winner = match.result.value?.winner;
        if (winner == null) return const SizedBox.shrink();

        return IgnorePointer(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: ColoredBox(color: Palette.of(winner).withValues(alpha: 0.9)),
          ),
        );
      },
    );
  }
}

/// The end screen: final coverage animating in, and the trophy change.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.result,
    required this.onRematch,
    required this.onHome,
    this.chestKept = true,
    this.campaign,
  });

  final MatchResult result;
  final VoidCallback onRematch;
  final VoidCallback onHome;

  /// Set on a campaign level. The campaign does not move trophies, so the
  /// end screen shows the stars the level was worth instead of a number that
  /// would be a lie.
  final CampaignBattle? campaign;

  /// Whether the chest this win earned actually went into a slot. False when
  /// every slot was already full and it was forfeited.
  final bool chestKept;

  @override
  Widget build(BuildContext context) {
    final accent = switch (result.outcome) {
      MatchOutcome.win => Palette.red,
      MatchOutcome.loss => Palette.blue,
      MatchOutcome.draw => Palette.neutral,
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        // The same sky the match was played under, opaque, so the board is
        // hidden while the result is read. A dark scrim over a light theme
        // was the one screen still lit from the old palette.
        MatchBackground(playerTeam: result.playerTeam),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              // A card, not text on sky.
              //
              // The headline is drawn in the winning side's colour, and a
              // team colour printed straight onto a blue sky is exactly the
              // case section 14 keeps the arena's bezel dark for: 34pt of
              // #2D69D7 on #6FC4F0 has almost no contrast. On white it has
              // all of it, and the panel gives the result somewhere to sit.
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: BoxDecoration(
                  color: Palette.hudSurface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Palette.hudOutline, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x59000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.headline,
                      style: TextStyle(
                        color: accent,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.subtitle,
                      style: const TextStyle(
                        color: Palette.hudTextDim,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // The bar slides to the final split rather than snapping.
                    _FinalCoverage(
                      coverage: result.coverage,
                      playerTeam: result.playerTeam,
                    ),

                    const SizedBox(height: 22),
                    if (campaign case final level?)
                      _StarsEarned(
                        level: level,
                        stars: level.starsFor(
                          won: result.won,
                          playerShare: result.playerShare,
                        ),
                        playerShare: result.playerShare,
                      )
                    else
                      _TrophyChange(change: result.trophyChange),

                    if (result.chestEarned) ...[
                      const SizedBox(height: 14),
                      _ChestEarned(kept: chestKept),
                    ],

                    const SizedBox(height: 26),
                    _ResultButton(
                      label: 'REMATCH',
                      onPressed: onRematch,
                      accent: accent,
                    ),
                    const SizedBox(height: 10),
                    _ResultButton(
                      label: 'HOME',
                      onPressed: onHome,
                      secondary: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FinalCoverage extends StatefulWidget {
  const _FinalCoverage({required this.coverage, required this.playerTeam});

  final Coverage coverage;

  /// Which end of the bar is yours.
  final Team playerTeam;

  @override
  State<_FinalCoverage> createState() => _FinalCoverageState();
}

class _FinalCoverageState extends State<_FinalCoverage> {
  final ValueNotifier<Coverage> _shown = ValueNotifier(const Coverage.zero());

  @override
  void initState() {
    super.initState();
    // One frame at zero, then animate to the final split.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shown.value = widget.coverage;
    });
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: CoverageBar(
      coverage: _shown,
      playerTeam: widget.playerTeam,
      height: 34,
    ),
  );
}

/// The three stars a campaign level was worth, and the one line that says
/// what the next one would have taken.
///
/// The miss is the useful half. "You held 54%" on its own is a fact about
/// the past; "60% for the second star" is the thing that decides whether the
/// player taps REMATCH, so the shortfall is spelled out rather than left for
/// them to work out from a row of grey outlines.
class _StarsEarned extends StatelessWidget {
  const _StarsEarned({
    required this.level,
    required this.stars,
    required this.playerShare,
  });

  final CampaignBattle level;
  final int stars;
  final double playerShare;

  @override
  Widget build(BuildContext context) {
    final next = level.nextStarAt(stars);
    final percent = (playerShare * 100).round();

    return Column(
      children: [
        Text(
          'LEVEL ${level.level}',
          style: const TextStyle(
            color: Palette.hudTextDim,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: i <= stars ? 44 : 38,
                  color: i <= stars
                      ? Palette.gold
                      : Palette.hudTextDim.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          switch (stars) {
            0 => 'No stars. Win the match to earn the first.',
            3 => 'You held $percent% of the board.',
            _ =>
              'You held $percent%. '
                  '${(next! * 100).round()}% earns the next star.',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.hudTextDim, fontSize: 12),
        ),
      ],
    );
  }
}

class _TrophyChange extends StatelessWidget {
  const _TrophyChange({required this.change});

  final int change;

  @override
  Widget build(BuildContext context) {
    final positive = change > 0;
    final colour = change == 0
        ? Palette.hudTextDim
        : (positive ? Palette.success : Palette.danger);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events, color: colour, size: 20),
        const SizedBox(width: 8),
        Text(
          change == 0 ? '0' : '${positive ? '+' : ''}$change',
          style: TextStyle(
            color: colour,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'trophies',
          style: TextStyle(color: Palette.hudTextDim, fontSize: 12),
        ),
      ],
    );
  }
}

/// What the win actually did for your chest slots.
///
/// This used to say "Chest earned" on every win, whether or not one was
/// stored. With both slots full a win forfeits its chest, so the message was
/// telling players a chest had arrived and then none appeared — which reads
/// exactly like a chest that will not open. It now says which of the two
/// happened, and what to do about it.
class _ChestEarned extends StatelessWidget {
  const _ChestEarned({required this.kept});

  /// True when the chest went into a slot; false when it was forfeited.
  final bool kept;

  @override
  Widget build(BuildContext context) {
    final accent = kept ? Palette.accent : Palette.hudTextDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.hudSurfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kept ? Icons.inventory_2 : Icons.block, color: accent, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              kept
                  ? 'Chest earned'
                  : 'No free slot — chest lost. Open one to keep the next.',
              style: TextStyle(
                color: kept ? Palette.hudText : Palette.hudTextDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultButton extends StatelessWidget {
  const _ResultButton({
    required this.label,
    required this.onPressed,
    this.accent = Palette.accent,
    this.secondary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Color accent;
  final bool secondary;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: secondary ? Palette.hudSurfaceLow : accent,
        foregroundColor: secondary ? Palette.hudText : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: secondary ? Palette.hudOutline : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
      ),
    ),
  );
}

/// The match, held.
///
/// Deliberately the same object as the end screen: sky behind, one card in
/// the middle, the same two buttons in the same places. A pause is not a
/// different room, and a player who has just learned where RESUME sits should
/// find HOME in the place DEFEAT put it.
///
/// It covers the arena rather than dimming it. A frozen board under a
/// half-transparent sheet looks like the game has hung; a board that is
/// simply not there reads as deliberate.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.playerTeam,
    required this.onResume,
    required this.onQuit,
  });

  final Team playerTeam;
  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      MatchBackground(playerTeam: playerTeam),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: BoxDecoration(
                color: Palette.hudSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Palette.hudOutline, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.pause_circle_filled_rounded,
                    size: 46,
                    color: Palette.accent,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'PAUSED',
                    style: TextStyle(
                      color: Palette.hudText,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Says the thing a player actually wants confirmed before
                  // they dare leave the screen.
                  const Text(
                    'The clock is stopped',
                    style: TextStyle(
                      color: Palette.hudTextDim,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _ResultButton(label: 'RESUME', onPressed: onResume),
                  const SizedBox(height: 10),
                  // No trophies, no stars, no chest: quitting a match part
                  // way through is a forfeit, and saying so here is cheaper
                  // than a player finding out afterwards.
                  const Text(
                    'Leaving forfeits the match.',
                    style: TextStyle(color: Palette.hudTextDim, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  _ResultButton(
                    label: 'HOME',
                    onPressed: onQuit,
                    secondary: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
