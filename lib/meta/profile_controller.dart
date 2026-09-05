import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/game_data.dart';
import '../core/save/hive_boxes.dart';
import '../core/save/player_profile.dart';
import '../game/cards/card_model.dart';
import '../game/cards/card_registry.dart';
import 'campaign.dart';
import 'chests.dart';
import 'quests.dart';
import 'upgrades.dart';

/// The player's saved state, and every rule that changes it.
///
/// Every mutation goes through here and writes straight to Hive, so there is
/// no "unsaved" window where closing the app loses a chest.
class ProfileController extends StateNotifier<PlayerProfile> {
  ProfileController({
    required this.data,
    required PlayerProfile initial,
    math.Random? random,
  }) : _random = random ?? math.Random(),
       super(initial);

  final GameData data;
  final math.Random _random;

  ChestConfig get chests => data.chests;
  UpgradeCosts get upgrades => data.upgrades;
  QuestConfig get questConfig => data.quests;
  CampaignConfig get campaign => data.campaign;

  void _save(PlayerProfile next) {
    state = next;
    saveToDisk(next);
  }

  /// Where a change is persisted. Overridable so tests can run the whole
  /// meta layer without Hive.
  @protected
  void saveToDisk(PlayerProfile profile) {
    HiveBoxes.write(profile.toJson());
  }

  // --- Deck ---------------------------------------------------------------

  /// The deck the player battles with, falling back to the starter.
  Deck get deck {
    final saved = state.deck;
    if (saved.length == Deck.size) {
      try {
        final deck = Deck(saved);
        deck.validateAgainst(data.cards);
        return deck;
      } on ArgumentError {
        // A saved deck naming a card this build no longer has. Fall through
        // to the starter rather than refusing to start a match.
      }
    }
    return data.defaultDeck;
  }

  // --- What the player owns -----------------------------------------------

  /// Whether [cardId] has been unlocked yet.
  ///
  /// Cards arrive as the campaign is cleared rather than all at once: a
  /// twenty-one card collection handed over on the first launch is twenty-one
  /// cards nobody reads, and it leaves the deck builder with nothing to give
  /// later. The six in the starter deck are never locked.
  bool isCardUnlocked(String cardId) =>
      campaign.isCardUnlocked(cardId, state.campaignCleared);

  /// The cards the player may actually build with, in roster order.
  Iterable<CardModel> get unlockedCards =>
      data.cards.playable.where((c) => isCardUnlocked(c.id));

  /// The level [cardId] unlocks at, or null if it is already available.
  int? unlockLevelFor(String cardId) =>
      isCardUnlocked(cardId) ? null : campaign.unlockLevelFor(cardId);

  /// Swaps [outId] for [inId]. Returns false if that would break the deck.
  bool swapCard({required String outId, required String inId}) {
    final current = List<String>.of(deck.cardIds);
    final index = current.indexOf(outId);
    if (index < 0) return false;
    if (current.contains(inId)) return false; // no duplicates
    if (!data.cards.playable.any((c) => c.id == inId)) return false;
    // A locked card cannot be built with, however it was reached.
    if (!isCardUnlocked(inId)) return false;

    current[index] = inId;
    _save(state.copyWith(deck: current));
    return true;
  }

  // --- Trophies and the end of a match ------------------------------------

  /// Applies a finished free-play match: trophies, the chest a win earns, and
  /// quest progress. One call so nothing can be applied twice or half-applied.
  ///
  /// **No screen calls this any more.** Home's battle button plays the next
  /// campaign level, so [applyCampaignLevel] is the live path. This is kept,
  /// with its tests, because it is the whole of the rated-ladder rule —
  /// including the trophy adjustment for the gap between two sides, which
  /// the campaign has no use for — and rebuilding that from scratch would be
  /// the expensive half of bringing free play back.
  ///
  /// Returns whether a chest was actually stored. A win with every slot full
  /// forfeits its chest, and the end screen has to be able to say so rather
  /// than promising one that never arrives.
  bool applyMatch({
    required int trophyChange,
    required bool won,
    required MatchTally tally,
  }) {
    var next = state.copyWith(
      trophies: math.max(0, state.trophies + trophyChange),
    );
    next = _withQuestProgress(next, tally);

    final before = next.chests.length;
    if (won) next = _withEarnedChest(next);
    final kept = next.chests.length > before;

    _save(next);
    return kept;
  }

  // --- Campaign -----------------------------------------------------------

  /// Banks the result of a campaign level.
  ///
  /// Levels are the only way to fight now — the battle button on Home plays
  /// whichever one you are up to — so this call carries the whole meta loop:
  /// stars, coins, quests, the chest, and the trophies that unlock arenas and
  /// the third and fourth chest slot.
  ///
  /// **Everything except the star improvement is paid on a first clear only.**
  /// That is what stops the one thing a single progression could go wrong on:
  /// replaying level 1 forever would otherwise be an unlimited supply of
  /// trophies and chests, and would carry a player to Arena 4 without ever
  /// meeting a harder opponent. Replay to improve your stars; the coins for
  /// the stars you gain are the reward for that, and nothing else repeats.
  CampaignReward applyCampaignLevel({
    required int level,
    required int stars,
    required MatchTally tally,
  }) {
    final before = state.starsOnLevel(level);
    final firstClear = before == 0 && stars > 0;

    var next = _withQuestProgress(state, tally);

    // Only an improvement is recorded, so replaying a level you already
    // three-starred can never take those stars away.
    final coins = campaign.coinsFor(before: before, after: stars);
    var purse = coins;
    if (firstClear) purse += campaign.milestoneCoinsOn(level);

    if (stars > before) {
      next = next.copyWith(
        campaignStars: {...next.campaignStars, level: stars},
      );
    }
    if (purse > 0) next = next.copyWith(coins: next.coins + purse);

    // Trophies. The campaign has no opponent rating to measure against, so
    // this is the flat win figure from progression.json rather than the
    // adjusted one — a level's difficulty is already expressed by being
    // further up the ladder.
    final trophies = firstClear ? data.trophies.win : 0;
    if (trophies > 0) {
      next = next.copyWith(trophies: next.trophies + trophies);
    }

    // A chest on every first clear, not only the marked levels. Quick Battle
    // used to hand one out per win and it was where upgrade copies came from;
    // with it gone, one chest per ten levels would starve card levels
    // entirely. The marked levels still exist — they are what the level list
    // advertises — but every new level now pays one.
    final chestsBefore = next.chests.length;
    if (firstClear) next = _withEarnedChest(next);
    final chestKept = next.chests.length > chestsBefore;

    _save(next);

    return CampaignReward(
      starsBefore: before,
      starsAfter: math.max(before, stars),
      coins: purse,
      trophies: trophies,
      chestKept: chestKept,
      chestForfeited: firstClear && !chestKept,
    );
  }

  // --- Chests -------------------------------------------------------------

  int get chestSlots => chests.slotsFor(state.trophies);

  bool get hasFreeChestSlot => state.chests.length < chestSlots;

  /// Only one chest may be unlocking at a time.
  bool get isAnyChestUnlocking => state.chests.any((c) => c.isUnlocking);

  PlayerProfile _withEarnedChest(PlayerProfile profile) {
    if (profile.chests.length >= chests.slotsFor(profile.trophies)) {
      // Slots full: the chest is forfeited, which is what makes opening them
      // worth doing.
      return profile;
    }
    final type = chests.roll(_random);
    return profile.copyWith(
      chests: [
        ...profile.chests,
        ChestSlot(typeId: type.id),
      ],
    );
  }

  /// Starts the timer on the chest in [index]. Only one may unlock at a time.
  bool startUnlocking(int index, {DateTime? now}) {
    if (index < 0 || index >= state.chests.length) return false;
    if (state.chests.any((c) => c.isUnlocking)) return false;

    final updated = List<ChestSlot>.of(state.chests);
    updated[index] = updated[index].startUnlocking(now ?? DateTime.now());
    _save(state.copyWith(chests: updated));
    return true;
  }

  /// Takes [by] off the chest in [index], as a rewarded ad does.
  ///
  /// Implemented by moving the start time *backwards* rather than storing a
  /// separate credit. The remaining time is already derived from that one
  /// timestamp, so there is nothing to keep in step and nothing new to save —
  /// and a chest sped up before the app closed is still sped up after it,
  /// for free.
  ///
  /// Returns whether anything changed: a chest that has not been started, or
  /// one already finished, is not something to spend an ad on.
  bool speedUpChest(int index, Duration by, {DateTime? now}) {
    if (index < 0 || index >= state.chests.length) return false;
    if (by <= Duration.zero) return false;
    final slot = state.chests[index];
    final started = slot.unlockStartedAt;
    if (started == null) return false;
    if (isReady(slot, now: now)) return false;

    final updated = List<ChestSlot>.of(state.chests);
    updated[index] = ChestSlot(
      typeId: slot.typeId,
      unlockStartedAt: started.subtract(by),
    );
    _save(state.copyWith(chests: updated));
    return true;
  }

  /// How long is left on [slot], or null if it is not unlocking.
  Duration? remainingOn(ChestSlot slot, {DateTime? now}) {
    final started = slot.unlockStartedAt;
    if (started == null) return null;
    final done = started.add(chests.byId(slot.typeId).duration);
    final left = done.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool isReady(ChestSlot slot, {DateTime? now}) =>
      remainingOn(slot, now: now) == Duration.zero;

  /// Opens the chest in [index] if its timer has run out.
  ChestReward? openChest(int index, {DateTime? now}) {
    if (index < 0 || index >= state.chests.length) return null;
    final slot = state.chests[index];
    if (!isReady(slot, now: now)) return null;

    // A chest can only hand over copies of cards you have actually unlocked.
    // Otherwise it quietly banks duplicates of a card you cannot play for
    // another eighty levels, and the level that unlocks it arrives already
    // half spent — which makes both the chest and the unlock feel cheaper.
    final reward = chests.open(chests.byId(slot.typeId), [
      for (final card in unlockedCards) card.id,
    ], _random);

    final copies = Map<String, int>.of(state.cardCopies);
    reward.cards.forEach((id, count) {
      copies[id] = (copies[id] ?? 0) + count;
    });

    final remaining = List<ChestSlot>.of(state.chests)..removeAt(index);
    _save(
      state.copyWith(
        coins: state.coins + reward.coins,
        cardCopies: copies,
        chests: remaining,
      ),
    );
    return reward;
  }

  // --- Card levels --------------------------------------------------------

  bool canUpgrade(String cardId) => upgrades.canAfford(
    level: state.levelOf(cardId),
    copies: state.copiesOf(cardId),
    coins: state.coins,
  );

  /// Spends duplicates and coins to take [cardId] up one level.
  bool upgradeCard(String cardId) {
    if (!canUpgrade(cardId)) return false;
    final step = upgrades.stepFrom(state.levelOf(cardId))!;

    final levels = Map<String, int>.of(state.cardLevels)..[cardId] = step.level;
    final copies = Map<String, int>.of(state.cardCopies)
      ..[cardId] = state.copiesOf(cardId) - step.copies;

    _save(
      state.copyWith(
        cardLevels: levels,
        cardCopies: copies,
        coins: state.coins - step.coins,
      ),
    );
    return true;
  }

  // --- Shop ---------------------------------------------------------------

  /// Buys [copies] of [cardId] at the flat coin rate.
  bool buyCopies(String cardId, int copies) {
    final int cost = copies * data.shopCoinsPerCopy;
    if (copies <= 0 || state.coins < cost) return false;

    final owned = Map<String, int>.of(state.cardCopies)
      ..[cardId] = state.copiesOf(cardId) + copies;
    _save(state.copyWith(coins: state.coins - cost, cardCopies: owned));
    return true;
  }

  // --- Quests -------------------------------------------------------------

  /// Today's quests, rolling the set over at local midnight.
  List<Quest> get todaysQuests =>
      questConfig.forDay(QuestConfig.dayKey(DateTime.now()));

  /// Makes sure [state] holds progress rows for today, clearing yesterday's.
  void refreshQuests({DateTime? now}) {
    final day = QuestConfig.dayKey(now ?? DateTime.now());
    if (state.questDay == day && state.quests.isNotEmpty) return;

    _save(
      state.copyWith(
        questDay: day,
        quests: [
          for (final quest in questConfig.forDay(day))
            QuestProgress(questId: quest.id),
        ],
      ),
    );
  }

  QuestProgress progressFor(String questId) => state.quests.firstWhere(
    (q) => q.questId == questId,
    orElse: () => QuestProgress(questId: questId),
  );

  bool isComplete(Quest quest) =>
      progressFor(quest.id).progress >= quest.target;

  PlayerProfile _withQuestProgress(PlayerProfile profile, MatchTally tally) {
    if (profile.quests.isEmpty) return profile;

    final updated = <QuestProgress>[];
    for (final row in profile.quests) {
      final quest = questConfig.byId(row.questId);
      if (quest == null || row.claimed) {
        updated.add(row);
        continue;
      }

      final contribution = tally.contributionTo(quest.type);
      // A personal-best quest takes the highest single match, not a total.
      final next = quest.type.isBest
          ? math.max(row.progress, contribution)
          : row.progress + contribution;

      updated.add(row.copyWith(progress: math.min(next, quest.target)));
    }
    return profile.copyWith(quests: updated);
  }

  /// Claims a finished quest's coins.
  bool claimQuest(String questId) {
    final quest = questConfig.byId(questId);
    if (quest == null) return false;

    final row = progressFor(questId);
    if (row.claimed || row.progress < quest.target) return false;

    final updated = [
      for (final q in state.quests)
        q.questId == questId ? q.copyWith(claimed: true) : q,
    ];
    _save(state.copyWith(coins: state.coins + quest.coins, quests: updated));
    return true;
  }

  // --- Settings -----------------------------------------------------------

  void updateSettings(Settings settings) =>
      _save(state.copyWith(settings: settings));

  /// Wipes the save. Used by the settings screen's reset.
  void resetProgress() => _save(const PlayerProfile());
}

/// Overridden in `main()` once Hive has been read.
final profileProvider = StateNotifierProvider<ProfileController, PlayerProfile>(
  (ref) => throw StateError('profileProvider must be overridden in main()'),
);
