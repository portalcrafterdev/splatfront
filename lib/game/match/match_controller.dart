import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../../core/audio.dart';
import '../../core/constants.dart';
import '../../core/palette.dart';
import '../bot/bot_difficulty.dart';
import '../splatfront_game.dart';
import 'match_result.dart';

enum MatchPhase {
  /// 3, 2, 1, Splat. Nothing may be deployed and no elixir accrues.
  countdown,

  /// Normal time.
  playing,

  /// 30 more seconds at double elixir, entered only on a close score.
  suddenDeath,

  /// Over. The result screen is up.
  finished,
}

extension MatchPhaseX on MatchPhase {
  bool get isLive => this == MatchPhase.playing || this == MatchPhase.suddenDeath;
  bool get isOver => this == MatchPhase.finished;
}

/// Runs the clock: countdown, normal time, sudden death, and the two ways a
/// match can end.
///
/// Everything it publishes is a [ValueNotifier], so the HUD updates without a
/// single `setState` anywhere near the arena.
class MatchController extends Component
    with HasGameReference<SplatfrontGame> {
  MatchController({required this.trophyRules, required this.botTier});

  final TrophyRules trophyRules;
  final BotTier botTier;

  /// Player trophies at the start of the match. Real persistence is Phase 7.
  int playerTrophies = 0;

  final ValueNotifier<MatchPhase> phase = ValueNotifier(MatchPhase.countdown);

  /// Seconds left in the current phase.
  final ValueNotifier<double> timeRemaining = ValueNotifier(Timings.countdown);

  /// The result, once there is one.
  final ValueNotifier<MatchResult?> result = ValueNotifier(null);

  /// Set while the instant-win wipe is playing, 0..1.
  final ValueNotifier<double> wipeProgress = ValueNotifier(0);

  /// How long the leader has held [Timings.instantWinCoverage].
  double _holdTimer = 0;
  Team? _holder;

  static const double _wipeSeconds = 1.2;
  double _wipeElapsed = 0;
  bool _wiping = false;

  bool get isLive => phase.value.isLive;

  /// The countdown number to show, or null once it is over.
  /// 3, 2, 1, then 0 meaning "Splat".
  int? get countdownNumber {
    if (phase.value != MatchPhase.countdown) return null;
    return timeRemaining.value.ceil().clamp(0, 3);
  }

  @override
  void update(double dt) {
    switch (phase.value) {
      case MatchPhase.countdown:
        _tickCountdown(dt);
      case MatchPhase.playing:
      case MatchPhase.suddenDeath:
        _tickPlay(dt);
      case MatchPhase.finished:
        _tickWipe(dt);
    }
  }

  void _tickCountdown(double dt) {
    // Nothing runs during the countdown: no elixir, no bot, no deploying.
    game.player.elixir.running = false;
    game.opponent.elixir.running = false;
    game.bot?.active = false;

    timeRemaining.value -= dt;
    if (timeRemaining.value > 0) return;

    phase.value = MatchPhase.playing;
    timeRemaining.value = Timings.normalTime;
    game.player.elixir.running = true;
    game.opponent.elixir.running = true;
    game.bot?.active = true;
  }

  void _tickPlay(double dt) {
    timeRemaining.value -= dt;

    if (_checkInstantWin(dt)) return;

    if (timeRemaining.value > 0) return;

    if (phase.value == MatchPhase.playing && _isCloseEnoughForSuddenDeath) {
      _enterSuddenDeath();
      return;
    }
    _finish(
      phase.value == MatchPhase.suddenDeath
          ? EndReason.suddenDeath
          : EndReason.timeUp,
    );
  }

  bool get _isCloseEnoughForSuddenDeath {
    final coverage = game.arena.coverage.value;
    return (coverage.red - coverage.blue).abs() <=
        Timings.suddenDeathThreshold;
  }

  void _enterSuddenDeath() {
    phase.value = MatchPhase.suddenDeath;
    timeRemaining.value = Timings.suddenDeathTime;
    // Double elixir, and nothing else changes.
    game.player.elixir.suddenDeath = true;
    game.opponent.elixir.suddenDeath = true;
  }

  /// Instant win: hold 95% or more for three continuous seconds.
  bool _checkInstantWin(double dt) {
    final coverage = game.arena.coverage.value;

    Team? leader;
    if (coverage.red >= Timings.instantWinCoverage) {
      leader = Team.red;
    } else if (coverage.blue >= Timings.instantWinCoverage) {
      leader = Team.blue;
    }

    if (leader == null || leader != _holder) {
      // The hold has to be continuous, so any break resets it.
      _holder = leader;
      _holdTimer = 0;
      return false;
    }

    _holdTimer += dt;
    if (_holdTimer < Timings.instantWinHold) return false;

    _finish(EndReason.instantWin);
    return true;
  }

  void _finish(EndReason reason) {
    if (phase.value.isOver) return;

    phase.value = MatchPhase.finished;
    timeRemaining.value = 0;
    game.bot?.active = false;
    game.player.elixir.running = false;
    game.opponent.elixir.running = false;
    game.cancelDeploy();
    // The arena does not stop when the clock does: units already swinging
    // carry on fighting, dying and painting under the result overlay, and
    // every one of those made a noise until the player pressed a button to
    // leave. Interface sounds are untouched, so the victory sting still fires.
    Audio.gameplayMuted = true;

    final coverage = game.arena.coverage.value;
    final partial = MatchResult(
      coverage: coverage,
      playerTeam: game.playerTeam,
      reason: reason,
      trophyChange: 0,
    );

    result.value = MatchResult(
      coverage: coverage,
      playerTeam: game.playerTeam,
      reason: reason,
      trophyChange: trophyRules.change(
        outcome: partial.outcome,
        playerTrophies: playerTrophies,
        opponentTrophies: trophyRules.trophiesForBot(playerTrophies, botTier),
      ),
    );

    // A wipeout gets the full-screen sweep; a normal finish does not.
    _wiping = reason == EndReason.instantWin;
    _wipeElapsed = 0;
    if (!_wiping) wipeProgress.value = 0;
  }

  void _tickWipe(double dt) {
    if (!_wiping) return;
    _wipeElapsed += dt;
    wipeProgress.value = (_wipeElapsed / _wipeSeconds).clamp(0.0, 1.0);
    if (wipeProgress.value >= 1) _wiping = false;
  }

  @override
  void onRemove() {
    phase.dispose();
    timeRemaining.dispose();
    result.dispose();
    wipeProgress.dispose();
    super.onRemove();
  }
}
