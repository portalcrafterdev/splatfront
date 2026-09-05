import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../cards/card_registry.dart';

/// How hard the opponent plays.
///
/// **There are no difficulty tiers.** There was an Easy / Medium / Hard split
/// once, both as a control the player picked and later as a badge on each
/// campaign level; both are gone on the owner's call. The campaign is one
/// unbroken ramp — every level 0.1% stronger than the one before it, level 1
/// to level 1000 — and a label that lumps three hundred of those together
/// says less than the level number already does.
///
/// One brain reads these numbers, so a level is nothing but a set of them.
class BotDifficulty {
  const BotDifficulty({
    required this.reactionDelay,
    required this.elixirWasteRate,
    required this.countersThreats,
    required this.playsSpells,
    this.lanePrecision = 1.0,
    this.cardPrecision = 1.0,
  });

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
  /// This is the knob that actually decides a match. Reinforcing ground
  /// you already hold wins nothing in a game scored on coverage, and a bot
  /// that always answers where it is weakest plays the board better than
  /// most people will. 1.0 is always playing the lane it is losing.
  final double lanePrecision;

  /// How often it plays the best card in its hand rather than any card it
  /// can afford.
  ///
  /// The hand lockout gives every side one play per turn no matter what it
  /// picks, so card choice is not capped the way tempo is: it is the other
  /// half of what decides a match. 1.0 is perfect play.
  final double cardPrecision;

  factory BotDifficulty.fromJson(Map<String, dynamic> json) => BotDifficulty(
    reactionDelay: (json['reactionDelay'] as num).toDouble(),
    elixirWasteRate: (json['elixirWasteRate'] as num).toDouble(),
    countersThreats: json['countersThreats'] as bool,
    playsSpells: json['playsSpells'] as bool,
    lanePrecision: (json['lanePrecision'] as num?)?.toDouble() ?? 1.0,
    cardPrecision: (json['cardPrecision'] as num?)?.toDouble() ?? 1.0,
  );
}

/// Everything in `assets/data/bot_decks.json`: one deck per trophy arena.
///
/// It used to carry three hand-tuned difficulties as well. They went with the
/// tiers: every opponent the game builds now comes off the campaign ramp in
/// `campaign.json`, so a second set of numbers here would be a second source
/// of truth that nothing read.
class BotConfig {
  const BotConfig({required this.decksByArena});

  /// Keyed by [ArenaLayout.id].
  final Map<String, Deck> decksByArena;

  /// The deck for [arenaId], falling back to the first one so a new arena
  /// without its own deck still plays.
  Deck deckFor(String arenaId) =>
      decksByArena[arenaId] ?? decksByArena.values.first;

  static BotConfig fromJson(Map<String, dynamic> json) {
    final decks = <String, Deck>{
      for (final raw in json['decks'] as List<dynamic>)
        (raw as Map<String, dynamic>)['arena'] as String: Deck(
          List<String>.from(raw['cards'] as List),
        ),
    };

    return BotConfig(decksByArena: decks);
  }

  static Future<BotConfig> load() async {
    final raw = await rootBundle.loadString('assets/data/bot_decks.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
