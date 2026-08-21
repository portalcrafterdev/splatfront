import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../cards/card_registry.dart';

enum BotTier { easy, normal, hard }

extension BotTierX on BotTier {
  String get label => switch (this) {
    BotTier.easy => 'Easy',
    BotTier.normal => 'Normal',
    BotTier.hard => 'Hard',
  };
}

/// One difficulty tier. The same brain runs all three; only these numbers
/// change, which is what keeps the three from drifting apart in behaviour.
class BotDifficulty {
  const BotDifficulty({
    required this.tier,
    required this.reactionDelay,
    required this.elixirWasteRate,
    required this.countersThreats,
    required this.playsSpells,
    this.lanePrecision = 1.0,
    this.cardPrecision = 1.0,
  });

  final BotTier tier;

  /// Seconds between deciding to do something and actually doing it.
  final double reactionDelay;

  /// Chance of skipping a decision it could have acted on, which is how
  /// elixir gets wasted.
  final double elixirWasteRate;

  /// Whether it answers a push, or only ever builds its own.
  final bool countersThreats;

  final bool playsSpells;

  /// How often it plays into the third of the arena it is losing, rather
  /// than a lane picked at random.
  ///
  /// This is the knob that actually separates the tiers. Reinforcing ground
  /// you already hold wins nothing in a game scored on coverage, and a bot
  /// that always answers where it is weakest plays the board better than
  /// most people will. 1.0 is the old behaviour, shared by all three tiers.
  final double lanePrecision;

  /// How often it plays the best card in its hand rather than any card it
  /// can afford.
  ///
  /// The hand lockout gives every side one play per turn no matter what it
  /// picks, so card choice is not capped the way tempo is: it is the other
  /// half of what separates the tiers. 1.0 is the old behaviour.
  final double cardPrecision;

  factory BotDifficulty.fromJson(BotTier tier, Map<String, dynamic> json) =>
      BotDifficulty(
        tier: tier,
        reactionDelay: (json['reactionDelay'] as num).toDouble(),
        elixirWasteRate: (json['elixirWasteRate'] as num).toDouble(),
        countersThreats: json['countersThreats'] as bool,
        playsSpells: json['playsSpells'] as bool,
        lanePrecision: (json['lanePrecision'] as num?)?.toDouble() ?? 1.0,
        cardPrecision: (json['cardPrecision'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Everything in `assets/data/bot_decks.json`: the three tiers and one deck
/// per trophy arena.
class BotConfig {
  const BotConfig({required this.difficulties, required this.decksByArena});

  final Map<BotTier, BotDifficulty> difficulties;

  /// Keyed by [ArenaLayout.id].
  final Map<String, Deck> decksByArena;

  BotDifficulty operator [](BotTier tier) => difficulties[tier]!;

  /// The deck for [arenaId], falling back to the first one so a new arena
  /// without its own deck still plays.
  Deck deckFor(String arenaId) =>
      decksByArena[arenaId] ?? decksByArena.values.first;

  static BotConfig fromJson(Map<String, dynamic> json) {
    final rawTiers = json['difficulties'] as Map<String, dynamic>;
    final difficulties = <BotTier, BotDifficulty>{
      for (final tier in BotTier.values)
        tier: BotDifficulty.fromJson(
          tier,
          rawTiers[tier.name] as Map<String, dynamic>,
        ),
    };

    final decks = <String, Deck>{
      for (final raw in json['decks'] as List<dynamic>)
        (raw as Map<String, dynamic>)['arena'] as String: Deck(
          List<String>.from(raw['cards'] as List),
        ),
    };

    return BotConfig(difficulties: difficulties, decksByArena: decks);
  }

  static Future<BotConfig> load() async {
    final raw = await rootBundle.loadString('assets/data/bot_decks.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
