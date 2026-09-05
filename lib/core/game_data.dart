import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/arena/arena_layout.dart';
import '../game/bot/bot_difficulty.dart';
import '../game/cards/card_registry.dart';
import '../game/match/match_result.dart';
import '../game/units/units_registry.dart';
import '../meta/achievements.dart';
import '../meta/campaign.dart';
import '../meta/leaderboards.dart';
import '../meta/chests.dart';
import '../meta/quests.dart';
import '../meta/upgrades.dart';

/// The shop's terms, from `assets/data/shop.json`.
class ShopConfig {
  const ShopConfig({
    required this.dailyOfferCount,
    required this.copiesMin,
    required this.copiesMax,
    required this.coinsPerCopy,
  });

  final int dailyOfferCount;
  final int copiesMin;
  final int copiesMax;
  final int coinsPerCopy;

  static ShopConfig fromJson(Map<String, dynamic> json) {
    final copies = json['copiesPerOffer'] as Map<String, dynamic>;
    return ShopConfig(
      dailyOfferCount: (json['dailyOfferCount'] as num).toInt(),
      copiesMin: (copies['min'] as num).toInt(),
      copiesMax: (copies['max'] as num).toInt(),
      coinsPerCopy: (json['coinsPerCopy'] as num).toInt(),
    );
  }

  static Future<ShopConfig> load() async {
    final raw = await rootBundle.loadString('assets/data/shop.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// Everything loaded out of `assets/data/` once at startup.
///
/// Balance and level data is JSON on purpose (a balance pass should be a JSON
/// edit and a hot restart, nothing more), but it is read exactly once so no
/// screen ever waits on the asset bundle mid-game.
class GameData {
  const GameData({
    required this.arenas,
    required this.cards,
    required this.decks,
    required this.bot,
    required this.trophies,
    required this.economy,
    required this.chests,
    required this.upgrades,
    required this.quests,
    required this.shop,
    required this.campaign,
    required this.achievements,
    required this.leaderboards,
  });

  final List<ArenaLayout> arenas;
  final CardRegistry cards;

  /// Starter decks, used until the player builds their own.
  final List<Deck> decks;

  /// Bot difficulty tiers and one deck per arena.
  final BotConfig bot;

  /// Trophy maths for the end of a match.
  final TrophyRules trophies;

  /// Elixir income scaling, from the same file as the trophy maths.
  final MatchRules economy;

  // Meta layer.
  final ChestConfig chests;
  final UpgradeCosts upgrades;
  final QuestConfig quests;
  final ShopConfig shop;

  /// The 1000-level campaign: a curve and a few rules, not a level list.
  final CampaignConfig campaign;

  /// What Play Games and Game Center have to hand out.
  ///
  /// Loaded with everything else rather than on demand so the set is a plain
  /// field the profile can be measured against — reporting has to be cheap
  /// enough to do after any change, and an await in that path would make it
  /// something a caller could forget.
  final AchievementSet achievements;

  /// The score boards, ranking numbers the profile already keeps.
  final LeaderboardSet leaderboards;

  UnitsRegistry get units => cards.units;

  Deck get defaultDeck => decks.first;

  int get shopCoinsPerCopy => shop.coinsPerCopy;

  /// The highest arena unlocked at [trophyCount].
  ArenaLayout arenaFor(int trophyCount) =>
      ArenaLayout.forTrophies(arenas, trophyCount);

  /// Trophies needed for the next arena, or null once the last one is open.
  ///
  /// The home screen shows progress toward it, which the trophy road at the
  /// bottom of the quest list was the only place to find before.
  int? nextArenaThreshold(int trophyCount) {
    for (final arena in arenas) {
      if (arena.trophies > trophyCount) return arena.trophies;
    }
    return null;
  }

  static Future<GameData> load() async {
    final arenas = await ArenaLayout.loadAll();
    final cards = await CardRegistry.load();
    final decks = await Deck.loadStarterDecks();
    final bot = await BotConfig.load();
    final trophies = await TrophyRules.load();
    final economy = await MatchRules.load();
    final chests = await ChestConfig.load();
    final upgrades = await UpgradeCosts.load();
    final quests = await QuestConfig.load();
    final shop = await ShopConfig.load();
    final campaign = await CampaignConfig.load();
    final achievements = await AchievementSet.load();
    final leaderboards = await LeaderboardSet.load();

    // Fail at startup, not mid-match, if any deck names something that
    // cannot be played.
    for (final deck in [...decks, ...bot.decksByArena.values]) {
      deck.validateAgainst(cards);
    }

    return GameData(
      arenas: arenas,
      cards: cards,
      decks: decks,
      bot: bot,
      trophies: trophies,
      economy: economy,
      chests: chests,
      upgrades: upgrades,
      quests: quests,
      shop: shop,
      campaign: campaign,
      achievements: achievements,
      leaderboards: leaderboards,
    );
  }
}

/// Overridden in `main()` with the loaded data, so reading it is synchronous
/// everywhere in the widget tree.
final gameDataProvider = Provider<GameData>(
  (ref) => throw StateError('gameDataProvider must be overridden in main()'),
);
