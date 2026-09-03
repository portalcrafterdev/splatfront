import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../game/bot/bot_difficulty.dart';

/// One level of the campaign.
///
/// Levels are **derived, not authored.** A thousand hand-written entries
/// would be a thousand chances to typo a number, and no balance pass could
/// ever touch them all — so `campaign.json` holds a curve and a handful of
/// rules, and [CampaignConfig.levelAt] turns a level number into an
/// opponent. Changing how the whole ladder feels is still a JSON edit, which
/// is the rule the rest of the game's numbers follow.
class CampaignLevel {
  const CampaignLevel({
    required this.number,
    required this.difficulty,
    required this.botCardLevel,
    required this.arenaIndex,
  });

  /// 1-based, as the player sees it.
  final int number;

  /// The brain this level's opponent runs.
  final BotDifficulty difficulty;

  /// What level the bot's cards are played at. This is the lever that keeps
  /// the back half of the campaign getting harder after the brain has run
  /// out of room to improve: a level 9 card has +64% HP and damage, and the
  /// player's own upgrades are the answer to it.
  final int botCardLevel;

  /// Which arena to fight in, as an index into the loaded arena list.
  final int arenaIndex;

  /// The tier badge shown on the level tile. Cosmetic — the numbers above
  /// are what actually plays — but it gives the list a readable shape.
  BotTier get tier => difficulty.tier;
}

/// Everything in `assets/data/campaign.json`.
class CampaignConfig {
  const CampaignConfig({
    required this.levelCount,
    required this.twoStarCoverage,
    required this.threeStarCoverage,
    required this.rampLevels,
    required this.exponent,
    required this.reactionDelay,
    required this.elixirWasteRate,
    required this.lanePrecision,
    required this.cardPrecision,
    required this.countersThreatsFrom,
    required this.playsSpellsFrom,
    required this.botCardLevelFrom,
    required this.botCardLevelTo,
    required this.botMaxCardLevel,
    required this.arenaEveryLevels,
    required this.cardUnlocks,
    required this.coinsPerStar,
    required this.chestEveryLevels,
    required this.milestoneEveryLevels,
    required this.milestoneCoins,
  });

  final int levelCount;

  /// Coverage needed for the second and third star. The first is the win
  /// itself.
  ///
  /// Coverage is the one number the match already computes twice a second,
  /// and it is the thing the game is actually about — so the stars ask for
  /// more of it rather than for some side task the arena would have to grow
  /// new tracking code to notice.
  final double twoStarCoverage;
  final double threeStarCoverage;

  /// How many levels the brain takes to go from blunt to its best, and the
  /// curve it follows getting there.
  ///
  /// The exponent is above 1 on purpose: a straight line makes level 20
  /// meaningfully harder than level 10, which is far too steep while
  /// somebody is still learning what the cards do. Easing keeps the first
  /// couple of dozen levels gentle and spends the difficulty later.
  final int rampLevels;
  final double exponent;

  /// Each pair is [start, end] of the ramp.
  final List<double> reactionDelay;
  final List<double> elixirWasteRate;
  final List<double> lanePrecision;
  final List<double> cardPrecision;

  /// The level each behaviour switches on at. Below these the bot never
  /// answers a push and never plays a spell, which is what makes the opening
  /// levels a place to learn rather than a wall.
  final int countersThreatsFrom;
  final int playsSpellsFrom;

  final int botCardLevelFrom;
  final int botCardLevelTo;
  final int botMaxCardLevel;

  /// The arena changes every this many levels, cycling through all of them.
  final int arenaEveryLevels;

  /// Which level hands over which card, keyed by card id.
  ///
  /// A card absent from this map is unlocked from the start — that is how the
  /// starter deck stays playable at level 1, and it means adding a card to
  /// `cards.json` without touching this file leaves it available rather than
  /// silently unreachable.
  final Map<String, int> cardUnlocks;

  /// The level [cardId] arrives at, or null if it was never locked.
  int? unlockLevelFor(String cardId) => cardUnlocks[cardId];

  /// Whether [cardId] is in hand for a player who has cleared [cleared]
  /// levels. Level 0 is a fresh profile.
  bool isCardUnlocked(String cardId, int cleared) =>
      cleared >= (cardUnlocks[cardId] ?? 0);

  /// The card [level] hands over on a first clear, if any.
  String? cardUnlockedAt(int level) {
    for (final entry in cardUnlocks.entries) {
      if (entry.value == level) return entry.key;
    }
    return null;
  }

  final int coinsPerStar;
  final int chestEveryLevels;
  final int milestoneEveryLevels;
  final int milestoneCoins;

  /// Where [level] sits on the difficulty ramp, 0 at the first level and 1
  /// once it has run out.
  double rampAt(int level) {
    if (rampLevels <= 1) return 1;
    final raw = ((level - 1) / (rampLevels - 1)).clamp(0.0, 1.0);
    return math.pow(raw, exponent).toDouble();
  }

  static double _lerp(List<double> pair, double t) =>
      pair.first + (pair.last - pair.first) * t;

  /// The tier badge. Thirds of the ramp, so the label tracks the numbers
  /// instead of being a second thing to keep in step.
  BotTier _tierAt(double t) {
    if (t < 1 / 3) return BotTier.easy;
    if (t < 2 / 3) return BotTier.normal;
    return BotTier.hard;
  }

  int botCardLevelAt(int level) {
    if (level < botCardLevelFrom) return 1;
    final span = botCardLevelTo - botCardLevelFrom;
    final t = span <= 0
        ? 1.0
        : ((level - botCardLevelFrom) / span).clamp(0.0, 1.0);
    return 1 + (t * (botMaxCardLevel - 1)).round();
  }

  /// The opponent for [number], which is clamped into range so a saved
  /// profile from a build with more levels cannot crash this one.
  CampaignLevel levelAt(int number) {
    final n = number.clamp(1, levelCount);
    final t = rampAt(n);

    return CampaignLevel(
      number: n,
      difficulty: BotDifficulty(
        tier: _tierAt(t),
        reactionDelay: _lerp(reactionDelay, t),
        elixirWasteRate: _lerp(elixirWasteRate, t),
        countersThreats: n >= countersThreatsFrom,
        playsSpells: n >= playsSpellsFrom,
        lanePrecision: _lerp(lanePrecision, t),
        cardPrecision: _lerp(cardPrecision, t),
      ),
      botCardLevel: botCardLevelAt(n),
      arenaIndex: (n - 1) ~/ arenaEveryLevels,
    );
  }

  /// Stars earned by a finished match. A loss or a draw is worth nothing —
  /// the first star is the win itself.
  int starsFor({required bool won, required double playerShare}) {
    if (!won) return 0;
    if (playerShare >= threeStarCoverage) return 3;
    if (playerShare >= twoStarCoverage) return 2;
    return 1;
  }

  /// Coverage needed for the next star up from [stars], or null at three.
  double? nextStarAt(int stars) => switch (stars) {
    0 => null,
    1 => twoStarCoverage,
    2 => threeStarCoverage,
    _ => null,
  };

  /// Coins for improving a level from [before] stars to [after].
  ///
  /// Only the difference pays, so replaying a cleared level to farm coins
  /// earns nothing unless you actually play it better.
  int coinsFor({required int before, required int after}) =>
      after <= before ? 0 : (after - before) * coinsPerStar;

  /// Whether clearing [level] for the first time hands over a chest.
  bool chestOn(int level) =>
      chestEveryLevels > 0 && level % chestEveryLevels == 0;

  /// A bonus purse on the round hundreds and fifties.
  int milestoneCoinsOn(int level) =>
      milestoneEveryLevels > 0 && level % milestoneEveryLevels == 0
      ? milestoneCoins
      : 0;

  static CampaignConfig fromJson(Map<String, dynamic> json) {
    final stars = json['stars'] as Map<String, dynamic>;
    final brain = json['brain'] as Map<String, dynamic>;
    final botCards = json['botCardLevel'] as Map<String, dynamic>;
    final rewards = json['rewards'] as Map<String, dynamic>;

    List<double> pair(String key) => [
      for (final v in brain[key] as List<dynamic>) (v as num).toDouble(),
    ];

    return CampaignConfig(
      levelCount: (json['levelCount'] as num).toInt(),
      twoStarCoverage: (stars['twoStarCoverage'] as num).toDouble(),
      threeStarCoverage: (stars['threeStarCoverage'] as num).toDouble(),
      rampLevels: (brain['rampLevels'] as num).toInt(),
      exponent: (brain['exponent'] as num?)?.toDouble() ?? 1.0,
      reactionDelay: pair('reactionDelay'),
      elixirWasteRate: pair('elixirWasteRate'),
      lanePrecision: pair('lanePrecision'),
      cardPrecision: pair('cardPrecision'),
      countersThreatsFrom: (brain['countersThreatsFrom'] as num).toInt(),
      playsSpellsFrom: (brain['playsSpellsFrom'] as num).toInt(),
      botCardLevelFrom: (botCards['from'] as num).toInt(),
      botCardLevelTo: (botCards['to'] as num).toInt(),
      botMaxCardLevel: (botCards['maxLevel'] as num).toInt(),
      arenaEveryLevels: (json['arenaEveryLevels'] as num).toInt(),
      cardUnlocks: {
        for (final raw in json['cardUnlocks'] as List<dynamic>? ?? const [])
          (raw as Map<String, dynamic>)['card'] as String: (raw['level'] as num)
              .toInt(),
      },
      coinsPerStar: (rewards['coinsPerStar'] as num).toInt(),
      chestEveryLevels: (rewards['chestEveryLevels'] as num).toInt(),
      milestoneEveryLevels: (rewards['milestoneEveryLevels'] as num).toInt(),
      milestoneCoins: (rewards['milestoneCoins'] as num).toInt(),
    );
  }

  static Future<CampaignConfig> load() async {
    final raw = await rootBundle.loadString('assets/data/campaign.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// What clearing a campaign level actually handed over.
///
/// The end screen has to be able to tell the truth about this: a level whose
/// chest was forfeited because every slot was full should say so rather than
/// promising one that never arrives.
class CampaignReward {
  const CampaignReward({
    required this.starsBefore,
    required this.starsAfter,
    required this.coins,
    required this.chestKept,
    required this.chestForfeited,
  });

  final int starsBefore;
  final int starsAfter;
  final int coins;
  final bool chestKept;
  final bool chestForfeited;

  bool get improved => starsAfter > starsBefore;
  bool get firstClear => starsBefore == 0 && starsAfter > 0;
}

/// What the battle screen needs to know to run a campaign level: which level
/// it is, and the rules that turn its result into stars.
///
/// Passing this rather than a bare level number keeps the star thresholds in
/// exactly one place — the JSON — so the end screen and the meta layer can
/// never disagree about what the player just earned.
class CampaignBattle {
  const CampaignBattle({required this.level, required this.config});

  final int level;
  final CampaignConfig config;

  int starsFor({required bool won, required double playerShare}) =>
      config.starsFor(won: won, playerShare: playerShare);

  /// The coverage the next star up would have needed, or null at three.
  double? nextStarAt(int stars) => config.nextStarAt(stars);
}
