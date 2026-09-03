import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../../core/palette.dart';
import '../arena/paint_sampler.dart';
import '../bot/bot_difficulty.dart';

/// Why the match stopped.
enum EndReason {
  /// The 90 seconds ran out with a clear enough gap.
  timeUp,

  /// Sudden death ran out.
  suddenDeath,

  /// Someone held 95% for three continuous seconds.
  instantWin,
}

enum MatchOutcome { win, loss, draw }

/// Trophy maths from section 9, loaded from `assets/data/progression.json`.
class TrophyRules {
  const TrophyRules({
    required this.win,
    required this.loss,
    required this.trophiesPerAdjustment,
    required this.maxAdjustment,
    required this.botTrophyOffset,
  });

  final int win;
  final int loss;
  final int trophiesPerAdjustment;
  final int maxAdjustment;

  /// How far above or below the player the bot counts as, by difficulty.
  final Map<BotTier, int> botTrophyOffset;

  int trophiesForBot(int playerTrophies, BotTier tier) =>
      math.max(0, playerTrophies + (botTrophyOffset[tier] ?? 0));

  /// Base change, adjusted by the gap between the two sides.
  ///
  /// Beating someone above you is worth more; losing to them costs less. The
  /// adjustment is capped both ways so a mismatch can never invert the sign.
  int change({
    required MatchOutcome outcome,
    required int playerTrophies,
    required int opponentTrophies,
  }) {
    if (outcome == MatchOutcome.draw) return 0;

    final gap = opponentTrophies - playerTrophies;
    final adjustment = (gap / trophiesPerAdjustment).round().clamp(
      -maxAdjustment,
      maxAdjustment,
    );

    final base = outcome == MatchOutcome.win ? win : loss;
    final change = base + adjustment;

    // A win never loses trophies and a loss never gains them.
    return outcome == MatchOutcome.win
        ? math.max(1, change)
        : math.min(-1, change);
  }

  factory TrophyRules.fromJson(Map<String, dynamic> json) {
    final offsets =
        json['botTrophyOffset'] as Map<String, dynamic>? ?? const {};
    return TrophyRules(
      win: (json['win'] as num).toInt(),
      loss: (json['loss'] as num).toInt(),
      trophiesPerAdjustment:
          (json['trophiesPerAdjustment'] as num?)?.toInt() ?? 25,
      maxAdjustment: (json['maxAdjustment'] as num?)?.toInt() ?? 10,
      botTrophyOffset: {
        for (final tier in BotTier.values)
          tier: (offsets[tier.name] as num?)?.toInt() ?? 0,
      },
    );
  }

  static Future<TrophyRules> load() async {
    final raw = await rootBundle.loadString('assets/data/progression.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return TrophyRules.fromJson(json['trophies'] as Map<String, dynamic>);
  }
}

/// What it costs to play, while a match is running.
///
/// The first rule is the one that ties the whole game together: elixir comes
/// in faster the more of the arena you hold. Paint is already the scoreboard
/// and already the deploy zone; this makes it the income too, so falling
/// behind on coverage costs you the means to catch up, and a push that claims
/// ground pays for the next one.
///
/// The second is a brake on the hand: a slot goes cold for a few seconds
/// after you spend it, so the order you play cards in matters and a full hand
/// cannot be dumped in one breath.
class MatchRules {
  const MatchRules({
    required this.territorySpread,
    this.cardRefillSeconds = 0,
    this.deployAnywhere = false,
    this.deployClaimRadius = 0,
    this.maxLiveBuildings = 0,
  });

  /// How far the regeneration multiplier swings between holding nothing and
  /// holding everything. 0.25 gives 0.75x to 1.25x, even at 1.0x.
  final double territorySpread;

  /// Seconds the whole hand stays locked after any card is played.
  final double cardRefillSeconds;

  /// Whether a card may be dropped on ground you do not own.
  ///
  /// False is the original rule from section 3: a body could only land on
  /// your own colour, so painting forward was what extended your reach. True
  /// lets you drop anywhere and claim the ground as you land.
  final bool deployAnywhere;

  /// Radius the drop paints in the playing side's colour, when
  /// [deployAnywhere] is on. This is what makes landing on enemy ground turn
  /// it yours rather than just being allowed.
  final double deployClaimRadius;

  /// How many buildings one side may have standing at once. 0 means no cap.
  ///
  /// Section 17: the reference game had no cap, and turret spam is one of the
  /// three failures its reviews name. The per-building lifetime timer is a
  /// different lever and does not replace this one — a timer bounds how long
  /// a gun stands, a cap bounds how many stand together.
  final int maxLiveBuildings;

  /// Flat income, no lockout, original deploy rule.
  ///
  /// The default for the debug sandboxes and for any test that is not about
  /// these rules. The shipped values come from `progression.json`.
  static const MatchRules flat = MatchRules(territorySpread: 0);

  /// The regeneration multiplier for a side holding [share] of the board.
  ///
  /// Clamped so a wipe-out never stops income dead — a side pinned at 0%
  /// still needs enough elixir to play its way out.
  double multiplierFor(double share) {
    final clamped = share.clamp(0.0, 1.0);
    return 1 + (clamped - 0.5) * 2 * territorySpread;
  }

  factory MatchRules.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? hand,
    Map<String, dynamic>? deploy,
    Map<String, dynamic>? buildings,
  }) => MatchRules(
    territorySpread: (json['territorySpread'] as num).toDouble(),
    cardRefillSeconds: (hand?['refillSeconds'] as num?)?.toDouble() ?? 0,
    deployAnywhere: deploy?['anywhere'] as bool? ?? false,
    deployClaimRadius: (deploy?['claimRadius'] as num?)?.toDouble() ?? 0,
    maxLiveBuildings: (buildings?['maxLive'] as num?)?.toInt() ?? 0,
  );

  static Future<MatchRules> load() async {
    final raw = await rootBundle.loadString('assets/data/progression.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final elixir = json['elixir'] as Map<String, dynamic>?;
    if (elixir == null) return flat;
    return MatchRules.fromJson(
      elixir,
      hand: json['hand'] as Map<String, dynamic>?,
      deploy: json['deploy'] as Map<String, dynamic>?,
      buildings: json['buildings'] as Map<String, dynamic>?,
    );
  }
}

/// How a match ended.
class MatchResult {
  const MatchResult({
    required this.coverage,
    required this.playerTeam,
    required this.reason,
    required this.trophyChange,
  });

  final Coverage coverage;
  final Team playerTeam;
  final EndReason reason;
  final int trophyChange;

  double get playerShare => coverage.forTeam(playerTeam);
  double get opponentShare => coverage.forTeam(playerTeam.opponent);

  MatchOutcome get outcome {
    if (playerShare > opponentShare) return MatchOutcome.win;
    if (playerShare < opponentShare) return MatchOutcome.loss;
    return MatchOutcome.draw;
  }

  bool get won => outcome == MatchOutcome.win;

  /// The winning side, or null on an exact draw.
  Team? get winner => switch (outcome) {
    MatchOutcome.win => playerTeam,
    MatchOutcome.loss => playerTeam.opponent,
    MatchOutcome.draw => null,
  };

  /// A win earns a chest. Chests themselves land in Phase 7.
  bool get chestEarned => won;

  String get headline => switch (outcome) {
    MatchOutcome.win => 'VICTORY',
    MatchOutcome.loss => 'DEFEAT',
    MatchOutcome.draw => 'DRAW',
  };

  String get subtitle => switch (reason) {
    EndReason.instantWin => 'Wipeout',
    EndReason.suddenDeath => 'Sudden death',
    EndReason.timeUp => 'Time up',
  };
}
