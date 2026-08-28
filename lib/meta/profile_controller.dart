import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/game_data.dart';
import '../core/save/hive_boxes.dart';
import '../core/save/player_profile.dart';
import '../game/cards/card_registry.dart';
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

  /// Swaps [outId] for [inId]. Returns false if that would break the deck.
  bool swapCard({required String outId, required String inId}) {
    final current = List<String>.of(deck.cardIds);
    final index = current.indexOf(outId);
    if (index < 0) return false;
    if (current.contains(inId)) return false; // no duplicates
    if (!data.cards.playable.any((c) => c.id == inId)) return false;

    current[index] = inId;
    _save(state.copyWith(deck: current));
    return true;
  }

  // --- Trophies and the end of a match ------------------------------------

  /// Applies a finished match: trophies, the chest a win earns, and quest
  /// progress. One call so nothing can be applied twice or half-applied.
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
      chests: [...profile.chests, ChestSlot(typeId: type.id)],
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

    final reward = chests.open(
      chests.byId(slot.typeId),
      [for (final card in data.cards.playable) card.id],
      _random,
    );

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

    final levels = Map<String, int>.of(state.cardLevels)
      ..[cardId] = step.level;
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
    _save(
      state.copyWith(coins: state.coins + quest.coins, quests: updated),
    );
    return true;
  }

  // --- Settings -----------------------------------------------------------

  void updateSettings(Settings settings) =>
      _save(state.copyWith(settings: settings));

  /// Wipes the save. Used by the settings screen's reset.
  void resetProgress() => _save(const PlayerProfile());
}

/// Overridden in `main()` once Hive has been read.
final profileProvider =
    StateNotifierProvider<ProfileController, PlayerProfile>(
      (ref) => throw StateError('profileProvider must be overridden in main()'),
    );
