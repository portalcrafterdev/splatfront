import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/game_data.dart';
import 'package:splatfront/core/save/player_profile.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/meta/profile_controller.dart';
import 'package:splatfront/meta/quests.dart';

/// A controller that keeps its save in memory, so the whole meta layer can be
/// exercised without Hive.
class _TestProfile extends ProfileController {
  _TestProfile({required super.data, super.initial = const PlayerProfile()})
    : super(random: math.Random(1));

  Map<String, dynamic>? lastSaved;

  @override
  void saveToDisk(PlayerProfile profile) => lastSaved = profile.toJson();
}

void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await GameData.load();
  });

  _TestProfile fresh([PlayerProfile initial = const PlayerProfile()]) =>
      _TestProfile(data: data, initial: initial);

  group('save round trip', () {
    test('a profile survives being written and read back', () {
      final profile = PlayerProfile(
        trophies: 640,
        coins: 1234,
        cardLevels: const {'brusher': 4},
        cardCopies: const {'roller': 17},
        deck: const [
          'dab',
          'roller',
          'brusher',
          'pin',
          'sprayer',
          'paint_bomb',
        ],
        chests: [
          const ChestSlot(typeId: 'gold'),
          ChestSlot(
            typeId: 'wood',
            unlockStartedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          ),
        ],
        quests: const [QuestProgress(questId: 'win_two', progress: 1)],
        questDay: '2026-08-31',
        settings: const Settings(musicVolume: 0.2, haptics: false),
      );

      final restored = PlayerProfile.fromJson(profile.toJson());

      expect(restored.trophies, 640);
      expect(restored.coins, 1234);
      expect(restored.levelOf('brusher'), 4);
      expect(restored.copiesOf('roller'), 17);
      expect(restored.deck, profile.deck);
      expect(restored.chests, hasLength(2));
      expect(restored.chests[0].isUnlocking, isFalse);
      expect(restored.chests[1].unlockStartedAt, isNotNull);
      expect(restored.quests.single.progress, 1);
      expect(restored.questDay, '2026-08-31');
      expect(restored.settings.musicVolume, 0.2);
      expect(restored.settings.haptics, isFalse);
    });

    test('a brand new profile has sane defaults', () {
      const profile = PlayerProfile();
      expect(profile.trophies, 0);
      expect(profile.coins, 0);
      expect(profile.levelOf('brusher'), 1);
      expect(profile.settings.haptics, isTrue);
    });

    test('every change writes through immediately', () {
      final controller = fresh();
      expect(controller.lastSaved, isNull);

      controller.updateSettings(const Settings(musicVolume: 0.1));
      expect(controller.lastSaved, isNotNull);
      expect((controller.lastSaved!['settings'] as Map)['musicVolume'], 0.1);
    });
  });

  group('deck building', () {
    test('a new player battles with the starter deck', () {
      expect(fresh().deck.cardIds, data.defaultDeck.cardIds);
    });

    // Far enough into the campaign to own something outside the starter six.
    // A brand new profile owns exactly its deck and has nothing to swap in,
    // which is the point of unlocking cards as you go.
    PlayerProfile withProgress([int levels = 40]) =>
        PlayerProfile(campaignStars: {for (var i = 1; i <= levels; i++) i: 3});

    test('swapping a card keeps the deck six long and distinct', () {
      final controller = fresh(withProgress());
      final out = controller.deck.cardIds.first;
      final inCard = controller.unlockedCards.firstWhere(
        (c) => !controller.deck.cardIds.contains(c.id),
      );

      expect(controller.swapCard(outId: out, inId: inCard.id), isTrue);
      expect(controller.deck.cardIds, hasLength(Deck.size));
      expect(controller.deck.cardIds, contains(inCard.id));
      expect(controller.deck.cardIds, isNot(contains(out)));
      expect(controller.deck.cardIds.toSet(), hasLength(Deck.size));
    });

    test('a fresh player owns the starter deck and nothing else', () {
      final controller = fresh();
      expect(
        controller.unlockedCards.map((c) => c.id).toSet(),
        controller.deck.cardIds.toSet(),
      );
    });

    test('a locked card cannot be built with', () {
      final controller = fresh();
      final locked = data.cards.playable.firstWhere(
        (c) => !controller.isCardUnlocked(c.id),
      );
      final out = controller.deck.cardIds.first;

      expect(controller.swapCard(outId: out, inId: locked.id), isFalse);
      expect(controller.deck.cardIds, contains(out));
    });

    test('clearing its level unlocks a card', () {
      final entry = data.campaign.cardUnlocks.entries.first;
      final before = fresh(withProgress(entry.value - 1));
      final after = fresh(withProgress(entry.value));

      expect(before.isCardUnlocked(entry.key), isFalse);
      expect(after.isCardUnlocked(entry.key), isTrue);
    });

    // A chest that banks copies of a card you cannot play for another eighty
    // levels spends itself on nothing, and arrives at the unlock already half
    // used up.
    test('a chest only ever gives copies of unlocked cards', () {
      final controller = fresh(
        withProgress(3).copyWith(chests: [const ChestSlot(typeId: 'wood')]),
      );
      controller.startUnlocking(0, now: DateTime(2026));
      final reward = controller.openChest(0, now: DateTime(2027));

      expect(reward, isNotNull);
      for (final id in reward!.cards.keys) {
        expect(
          controller.isCardUnlocked(id),
          isTrue,
          reason: '$id is not unlocked yet',
        );
      }
    });

    test('a card already in the deck cannot be added twice', () {
      final controller = fresh();
      final ids = controller.deck.cardIds;
      expect(controller.swapCard(outId: ids[0], inId: ids[1]), isFalse);
    });

    test('a saved deck naming a missing card falls back to the starter', () {
      final controller = fresh(
        const PlayerProfile(
          deck: [
            'ghost_card',
            'dab',
            'roller',
            'brusher',
            'pin',
            'sprayer',
            'swarmlets',
            'bucket_bot',
          ],
        ),
      );
      expect(controller.deck.cardIds, data.defaultDeck.cardIds);
    });
  });

  group('chests', () {
    test('watching an ad takes time off a running chest', () {
      // The rewarded placement. Implemented by moving the start time back
      // rather than storing a credit, so what is actually asserted is that
      // the *remaining* time drops and that it survives being derived from
      // one timestamp.
      final controller = fresh(
        PlayerProfile(chests: [const ChestSlot(typeId: 'magic')]),
      );
      final started = DateTime(2026, 9, 5, 12);
      controller.startUnlocking(0, now: started);

      final full = controller.remainingOn(
        controller.state.chests.first,
        now: started,
      );
      expect(full, isNotNull);

      expect(controller.speedUpChest(0, const Duration(hours: 4)), isTrue);
      expect(
        controller.remainingOn(controller.state.chests.first, now: started),
        full! - const Duration(hours: 4),
      );

      // A second watch finishes an eight hour chest, which is the owner's
      // worked example.
      expect(controller.speedUpChest(0, const Duration(hours: 4)), isTrue);
      expect(controller.isReady(controller.state.chests.first, now: started),
          isTrue);
    });

    test('there is nothing to speed up on a sealed or finished chest', () {
      // A sealed chest has no timer to shorten, and a finished one is already
      // there to open — spending a watched ad on either would be taking
      // something for nothing, which is the one thing a rewarded placement
      // must never do.
      final controller = fresh(
        PlayerProfile(chests: [const ChestSlot(typeId: 'wood')]),
      );
      expect(
        controller.speedUpChest(0, const Duration(hours: 4)),
        isFalse,
        reason: 'sealed, so no timer exists yet',
      );

      final started = DateTime(2026, 9, 5, 12);
      controller.startUnlocking(0, now: started);
      controller.speedUpChest(0, const Duration(hours: 4));
      expect(
        controller.speedUpChest(0, const Duration(hours: 4)),
        isFalse,
        reason: 'already finished',
      );

      // And nothing off the end of the list.
      expect(controller.speedUpChest(9, const Duration(hours: 4)), isFalse);
    });

    test('two slots to start, four from Arena 2', () {
      expect(fresh().chestSlots, 2);
      expect(fresh(const PlayerProfile(trophies: 400)).chestSlots, 4);
    });

    test('a win earns a chest, a loss does not', () {
      final controller = fresh();
      controller.applyMatch(
        trophyChange: 30,
        won: true,
        tally: const MatchTally(
          won: true,
          cardsPlayed: 0,
          spellsPlayed: 0,
          paintSharePercent: 55,
        ),
      );
      expect(controller.state.chests, hasLength(1));

      controller.applyMatch(
        trophyChange: -25,
        won: false,
        tally: const MatchTally(
          won: false,
          cardsPlayed: 0,
          spellsPlayed: 0,
          paintSharePercent: 30,
        ),
      );
      expect(controller.state.chests, hasLength(1), reason: 'no chest');
    });

    test('a win with every slot full earns nothing', () {
      final controller = fresh(
        const PlayerProfile(
          chests: [
            ChestSlot(typeId: 'wood'),
            ChestSlot(typeId: 'wood'),
          ],
        ),
      );
      controller.applyMatch(
        trophyChange: 30,
        won: true,
        tally: const MatchTally(
          won: true,
          cardsPlayed: 0,
          spellsPlayed: 0,
          paintSharePercent: 55,
        ),
      );
      expect(controller.state.chests, hasLength(2));
    });

    test('only one chest may unlock at a time', () {
      final controller = fresh(
        const PlayerProfile(
          chests: [
            ChestSlot(typeId: 'wood'),
            ChestSlot(typeId: 'silver'),
          ],
        ),
      );
      final now = DateTime(2026, 8, 31, 12);

      expect(controller.startUnlocking(0, now: now), isTrue);
      expect(
        controller.startUnlocking(1, now: now),
        isFalse,
        reason: 'the first one is still running',
      );
    });

    test('a chest opens only once its timer has run out', () {
      final controller = fresh(
        const PlayerProfile(chests: [ChestSlot(typeId: 'wood')]),
      );
      final start = DateTime(2026, 8, 31, 12);
      controller.startUnlocking(0, now: start);

      // Wood takes three minutes.
      expect(
        controller.openChest(0, now: start.add(const Duration(minutes: 2))),
        isNull,
      );
      final reward = controller.openChest(
        0,
        now: start.add(const Duration(minutes: 4)),
      );

      expect(reward, isNotNull);
      expect(reward!.coins, greaterThan(0));
      expect(reward.totalCards, greaterThan(0));
      expect(controller.state.chests, isEmpty, reason: 'the slot freed up');
      expect(controller.state.coins, reward.coins);
    });

    test('opening a chest banks its card copies', () {
      final controller = fresh(
        const PlayerProfile(chests: [ChestSlot(typeId: 'gold')]),
      );
      final start = DateTime(2026, 8, 31, 12);
      controller.startUnlocking(0, now: start);
      final reward = controller.openChest(
        0,
        now: start.add(const Duration(hours: 4)),
      )!;

      reward.cards.forEach((id, count) {
        expect(controller.state.copiesOf(id), count);
      });
    });

    test('a sealed chest reports no time remaining', () {
      final controller = fresh(
        const PlayerProfile(chests: [ChestSlot(typeId: 'wood')]),
      );
      expect(controller.remainingOn(controller.state.chests.first), isNull);
      expect(controller.isReady(controller.state.chests.first), isFalse);
    });
  });

  group('card levels', () {
    test('a level 1 card needs copies and coins to reach level 2', () {
      final step = data.upgrades.stepFrom(1)!;
      expect(step.level, 2);
      expect(step.copies, greaterThan(0));

      final controller = fresh(
        PlayerProfile(coins: step.coins, cardCopies: {'brusher': step.copies}),
      );
      expect(controller.canUpgrade('brusher'), isTrue);
      expect(controller.upgradeCard('brusher'), isTrue);

      expect(controller.state.levelOf('brusher'), 2);
      expect(controller.state.copiesOf('brusher'), 0);
      expect(controller.state.coins, 0);
    });

    test('an upgrade you cannot pay for changes nothing', () {
      final controller = fresh(const PlayerProfile(coins: 0));
      expect(controller.canUpgrade('brusher'), isFalse);
      expect(controller.upgradeCard('brusher'), isFalse);
      expect(controller.state.levelOf('brusher'), 1);
    });

    test('the curve rises and stops at level 9', () {
      var lastCoins = 0;
      for (var level = 1; level < 9; level++) {
        final step = data.upgrades.stepFrom(level)!;
        expect(step.coins, greaterThan(lastCoins));
        lastCoins = step.coins;
      }
      expect(data.upgrades.stepFrom(9), isNull);
      expect(data.upgrades.isMaxed(9), isTrue);
      expect(data.upgrades.maxLevel, 9);
    });

    test('a levelled card actually hits harder in the arena', () {
      final controller = fresh(const PlayerProfile(cardLevels: {'brusher': 5}));
      final base = data.cards.at('brusher', 1);
      final levelled = data.cards.at(
        'brusher',
        controller.state.levelOf('brusher'),
      );

      expect(levelled.unit!.hp, greaterThan(base.unit!.hp));
      expect(levelled.unit!.damage, greaterThan(base.unit!.damage));
      expect(levelled.cost, base.cost, reason: 'cost never changes');
    });
  });

  group('shop', () {
    test('buying copies costs coins and adds cards', () {
      final rate = data.shopCoinsPerCopy;
      final controller = fresh(PlayerProfile(coins: rate * 5));

      expect(controller.buyCopies('roller', 5), isTrue);
      expect(controller.state.copiesOf('roller'), 5);
      expect(controller.state.coins, 0);
    });

    test('you cannot buy what you cannot afford', () {
      final controller = fresh(const PlayerProfile(coins: 1));
      expect(controller.buyCopies('roller', 5), isFalse);
      expect(controller.state.copiesOf('roller'), 0);
      expect(controller.state.coins, 1);
    });
  });

  group('daily quests', () {
    test('three are drawn, and the same day always gives the same three', () {
      final monday = data.quests.forDay('2026-08-31');
      expect(monday, hasLength(3));
      expect(
        data.quests.forDay('2026-08-31').map((q) => q.id),
        monday.map((q) => q.id),
      );
    });

    test('a different day gives a different draw', () {
      final a = data.quests.forDay('2026-08-31').map((q) => q.id).toList();
      final b = data.quests.forDay('2026-09-01').map((q) => q.id).toList();
      // Not guaranteed to differ, but the pool is large enough that an
      // identical draw would mean the seed is not being used at all.
      expect(a == b, isFalse);
    });

    test('the same quest is never drawn twice in a day', () {
      for (final day in ['2026-01-01', '2026-06-15', '2026-12-31']) {
        final ids = data.quests.forDay(day).map((q) => q.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: day);
      }
    });

    test('quests roll over when the day changes', () {
      final controller = fresh();
      controller.refreshQuests(now: DateTime(2026, 8, 31));
      final first = controller.state.quests.map((q) => q.questId).toList();
      expect(controller.state.questDay, '2026-08-31');

      controller.refreshQuests(now: DateTime(2026, 9, 1));
      expect(controller.state.questDay, '2026-09-01');
      expect(
        controller.state.quests.map((q) => q.questId).toList(),
        isNot(first),
      );
    });

    test('a match feeds progress into the quests it matches', () {
      final controller = fresh();
      controller.refreshQuests(now: DateTime(2026, 8, 31));

      controller.applyMatch(
        trophyChange: 30,
        won: true,
        tally: const MatchTally(
          won: true,
          cardsPlayed: 12,
          spellsPlayed: 3,
          paintSharePercent: 58,
        ),
      );

      for (final row in controller.state.quests) {
        final quest = data.quests.byId(row.questId)!;
        final expected = switch (quest.type) {
          QuestType.winMatches => 1,
          QuestType.playMatches => 1,
          QuestType.playCards => 12,
          QuestType.playSpells => 3,
          QuestType.paintShare => 58,
          QuestType.unknown => 0,
        };
        expect(
          row.progress,
          math.min(expected, quest.target),
          reason: quest.id,
        );
      }
    });

    test('paint share takes the best match, not the sum', () {
      final quest = data.quests.pool.firstWhere(
        (q) => q.type == QuestType.paintShare,
      );
      final controller = fresh(
        PlayerProfile(
          questDay: '2026-08-31',
          quests: [QuestProgress(questId: quest.id)],
        ),
      );

      MatchTally at(int percent) => MatchTally(
        won: false,
        cardsPlayed: 0,
        spellsPlayed: 0,
        paintSharePercent: percent,
      );

      controller.applyMatch(trophyChange: 0, won: false, tally: at(30));
      controller.applyMatch(trophyChange: 0, won: false, tally: at(20));

      expect(
        controller.progressFor(quest.id).progress,
        30,
        reason: 'painting 30 then 20 is not painting 50',
      );
    });

    test('a finished quest pays out once', () {
      final quest = data.quests.pool.firstWhere(
        (q) => q.type == QuestType.winMatches && q.target == 1,
      );
      final controller = fresh(
        PlayerProfile(
          questDay: '2026-08-31',
          quests: [QuestProgress(questId: quest.id, progress: quest.target)],
        ),
      );

      expect(controller.claimQuest(quest.id), isTrue);
      expect(controller.state.coins, quest.coins);

      expect(controller.claimQuest(quest.id), isFalse, reason: 'already paid');
      expect(controller.state.coins, quest.coins);
    });

    test('an unfinished quest pays nothing', () {
      final quest = data.quests.pool.firstWhere(
        (q) => q.type == QuestType.winMatches && q.target == 2,
      );
      final controller = fresh(
        PlayerProfile(
          questDay: '2026-08-31',
          quests: [QuestProgress(questId: quest.id, progress: 1)],
        ),
      );
      expect(controller.claimQuest(quest.id), isFalse);
      expect(controller.state.coins, 0);
    });

    test('a claimed quest stops accruing', () {
      final quest = data.quests.pool.firstWhere(
        (q) => q.type == QuestType.playMatches,
      );
      final controller = fresh(
        PlayerProfile(
          questDay: '2026-08-31',
          quests: [
            QuestProgress(
              questId: quest.id,
              progress: quest.target,
              claimed: true,
            ),
          ],
        ),
      );

      controller.applyMatch(
        trophyChange: 0,
        won: false,
        tally: const MatchTally(
          won: false,
          cardsPlayed: 5,
          spellsPlayed: 0,
          paintSharePercent: 10,
        ),
      );
      expect(controller.progressFor(quest.id).progress, quest.target);
    });
  });

  group('trophies', () {
    test('a match moves trophies and they never go below zero', () {
      final controller = fresh(const PlayerProfile(trophies: 10));
      controller.applyMatch(
        trophyChange: -25,
        won: false,
        tally: const MatchTally(
          won: false,
          cardsPlayed: 0,
          spellsPlayed: 0,
          paintSharePercent: 20,
        ),
      );
      expect(controller.state.trophies, 0);
    });

    test('trophies pick the arena', () {
      expect(data.arenaFor(0).id, 'arena_1');
      expect(data.arenaFor(500).id, 'arena_2');
      expect(data.arenaFor(1600).id, 'arena_4');
    });
  });

  group('settings', () {
    test('a change persists and the rest is untouched', () {
      final controller = fresh(const PlayerProfile(coins: 99));
      controller.updateSettings(
        const Settings(musicVolume: 0.25, sfxVolume: 0.5, haptics: false),
      );

      expect(controller.state.settings.musicVolume, 0.25);
      expect(controller.state.settings.haptics, isFalse);
      expect(controller.state.coins, 99);
    });

    test('resetting wipes everything back to a fresh start', () {
      final controller = fresh(
        const PlayerProfile(
          trophies: 900,
          coins: 5000,
          cardLevels: {'brusher': 7},
        ),
      );
      controller.resetProgress();

      expect(controller.state.trophies, 0);
      expect(controller.state.coins, 0);
      expect(controller.state.levelOf('brusher'), 1);
      expect(controller.lastSaved, isNotNull, reason: 'the wipe is saved too');
    });
  });
}
