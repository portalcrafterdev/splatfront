import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/game_data.dart';
import 'package:splatfront/core/save/player_profile.dart';
import 'package:splatfront/game/bot/bot_difficulty.dart';
import 'package:splatfront/meta/campaign.dart';
import 'package:splatfront/meta/profile_controller.dart';
import 'package:splatfront/meta/quests.dart';

class _TestProfile extends ProfileController {
  _TestProfile({required super.data, super.initial = const PlayerProfile()})
    : super(random: math.Random(1));

  @override
  void saveToDisk(PlayerProfile profile) {}
}

const _tally = MatchTally(
  won: true,
  cardsPlayed: 4,
  spellsPlayed: 1,
  paintSharePercent: 70,
);

void main() {
  late GameData data;
  late CampaignConfig campaign;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await GameData.load();
    campaign = data.campaign;
  });


  group('level names', () {
    // The tile used to be titled with its arena, which is the same for
    // twenty-five levels at a stretch: the largest text on the row was the
    // one thing that never changed.
    test('no two levels share a name', () {
      // Names are derived from two word lists whose lengths are coprime, and
      // that is the whole guarantee. Add a word and make the lengths share a
      // factor and names start repeating early — which is what this catches.
      final seen = <String>{};
      for (var n = 1; n <= campaign.levelCount; n++) {
        expect(
          seen.add(campaign.nameFor(n)),
          isTrue,
          reason: 'level $n repeats a name already used',
        );
      }
    });

    test('a level name never collides with an arena name', () {
      // A row titled "Primer Yard" that is played in Drip Works would be a
      // straight lie, so the two vocabularies are kept apart.
      final arenaWords = <String>{
        for (final a in data.arenas) ...a.name.toLowerCase().split(' '),
      };
      for (final pool in [campaign.nameFirst, campaign.nameSecond]) {
        for (final word in pool) {
          expect(
            arenaWords,
            isNot(contains(word.toLowerCase())),
            reason: '"$word" is also part of an arena name',
          );
        }
      }
    });

    test('the arena is named only where it changes', () {
      // Naming the board on all twenty-five levels of a band is the
      // repetition this whole change removed; the boundary is the one place
      // it is news.
      expect(campaign.arenaChangesAt(1), isTrue);
      expect(campaign.arenaChangesAt(2), isFalse);
      expect(campaign.arenaChangesAt(campaign.arenaEveryLevels), isFalse);
      expect(campaign.arenaChangesAt(campaign.arenaEveryLevels + 1), isTrue);
    });
  });
  group('the ladder', () {
    test('runs the full thousand levels', () {
      expect(campaign.levelCount, 1000);
      expect(campaign.levelAt(1).number, 1);
      expect(campaign.levelAt(1000).number, 1000);
    });

    // A saved profile from a build with a longer campaign must not be able to
    // crash this one, and neither must a level number off the front.
    test('a level number outside the ladder clamps instead of throwing', () {
      expect(campaign.levelAt(0).number, 1);
      expect(campaign.levelAt(-5).number, 1);
      expect(campaign.levelAt(99999).number, campaign.levelCount);
    });

    test('every level derives a playable opponent', () {
      for (final n in [1, 2, 15, 30, 99, 250, 500, 1000]) {
        final level = campaign.levelAt(n);
        expect(level.botCardLevel, inInclusiveRange(1, 9));
        expect(level.arenaIndex, greaterThanOrEqualTo(0));
        expect(level.difficulty.lanePrecision, inInclusiveRange(0.0, 1.0));
        expect(level.difficulty.cardPrecision, inInclusiveRange(0.0, 1.0));
        expect(level.difficulty.elixirWasteRate, inInclusiveRange(0.0, 1.0));
        expect(level.difficulty.reactionDelay, greaterThan(0));
      }
    });
  });

  group('the difficulty curve', () {
    // The whole point of a thousand levels is that they get harder. Every
    // knob has to move the same way, or a later level could be easier than an
    // earlier one and the ladder would stop meaning anything.
    test('never gets easier as the level number rises', () {
      var previous = campaign.levelAt(1);
      for (var n = 2; n <= campaign.levelCount; n += 7) {
        final level = campaign.levelAt(n);
        expect(
          level.difficulty.reactionDelay,
          lessThanOrEqualTo(previous.difficulty.reactionDelay + 1e-9),
          reason: 'reaction delay rose at level $n',
        );
        expect(
          level.difficulty.elixirWasteRate,
          lessThanOrEqualTo(previous.difficulty.elixirWasteRate + 1e-9),
          reason: 'waste rate rose at level $n',
        );
        expect(
          level.difficulty.lanePrecision,
          greaterThanOrEqualTo(previous.difficulty.lanePrecision - 1e-9),
          reason: 'lane precision fell at level $n',
        );
        expect(
          level.difficulty.cardPrecision,
          greaterThanOrEqualTo(previous.difficulty.cardPrecision - 1e-9),
          reason: 'card precision fell at level $n',
        );
        expect(
          level.botCardLevel,
          greaterThanOrEqualTo(previous.botCardLevel),
          reason: 'bot card level fell at level $n',
        );
        previous = level;
      }
    });

    test('the opening levels are a place to learn', () {
      final first = campaign.levelAt(1);
      expect(first.difficulty.countersThreats, isFalse);
      expect(first.difficulty.playsSpells, isFalse);
      expect(first.difficulty.lanePrecision, 0);
      expect(first.difficulty.cardPrecision, 0);
      expect(first.botCardLevel, 1);
      expect(first.tier, BotTier.easy);
    });

    test('the last level plays as well as the brain can', () {
      final last = campaign.levelAt(campaign.levelCount);
      expect(last.difficulty.countersThreats, isTrue);
      expect(last.difficulty.playsSpells, isTrue);
      expect(last.difficulty.lanePrecision, closeTo(1.0, 1e-9));
      expect(last.difficulty.cardPrecision, closeTo(1.0, 1e-9));
      expect(last.botCardLevel, 9);
      expect(last.tier, BotTier.hard);
    });

    // Easing is what keeps the first couple of dozen levels gentle. A
    // straight line would put level 20 nearly a tenth of the way up the ramp,
    // which is far too steep while somebody is still learning the cards.
    test('the ramp eases in rather than running straight', () {
      final linear = (20 - 1) / (campaign.rampLevels - 1);
      expect(campaign.rampAt(20), lessThan(linear));
      expect(campaign.rampAt(1), 0);
      expect(campaign.rampAt(campaign.rampLevels), closeTo(1.0, 1e-9));
    });

    test('the arena changes as the ladder climbs', () {
      final seen = {
        for (var n = 1; n <= 100; n++)
          campaign.levelAt(n).arenaIndex % data.arenas.length,
      };
      expect(seen.length, data.arenas.length);
    });
  });

  group('opponent names', () {
    test('the three names split the campaign into three blocks', () {
      expect(campaign.tierAt(1), BotTier.easy);
      expect(campaign.tierAt(300), BotTier.easy);
      expect(campaign.tierAt(301), BotTier.normal);
      expect(campaign.tierAt(600), BotTier.normal);
      expect(campaign.tierAt(601), BotTier.hard);
      expect(campaign.tierAt(1000), BotTier.hard);
    });

    test('every level wears exactly one name, in order', () {
      var seen = BotTier.easy;
      for (var n = 1; n <= campaign.levelCount; n++) {
        final tier = campaign.tierAt(n);
        expect(
          tier.index,
          greaterThanOrEqualTo(seen.index),
          reason: 'level $n went backwards to ${tier.name}',
        );
        seen = tier;
      }
      expect(seen, BotTier.hard);
    });

    // The name has to describe the fight. If the brain finished improving
    // before the last Novice level, a "Novice Bot" near the end of its block
    // would be playing at full strength and the label would be a lie.
    test('the brain is still improving for as long as the names say', () {
      expect(
        campaign.rampLevels,
        greaterThanOrEqualTo(campaign.veteranFrom),
        reason:
            'the brain maxes out at level ${campaign.rampLevels}, before '
            'Veteran begins at ${campaign.veteranFrom}',
      );
    });

    // Same argument for the stats: the whole Novice block should be a fight
    // against level 1 cards, or "Novice" covers an opponent already scaling.
    test('the bot only starts levelling its cards once Novice is over', () {
      expect(campaign.botCardLevelAt(campaign.rivalFrom - 1), 1);
      expect(
        campaign.botCardLevelFrom,
        greaterThanOrEqualTo(campaign.rivalFrom),
      );
    });

    test('each block is a real stretch of the difficulty curve', () {
      // Novice should not be over before it starts, and Veteran should not be
      // the only block with any difficulty in it.
      final atNoviceEnd = campaign.rampAt(campaign.rivalFrom - 1);
      final atRivalEnd = campaign.rampAt(campaign.veteranFrom - 1);

      expect(atNoviceEnd, greaterThan(0.1));
      expect(atNoviceEnd, lessThan(atRivalEnd));
      expect(atRivalEnd, lessThan(1.0));
    });
  });

  group('card unlocks', () {
    test('every unlock names a card that exists', () {
      final ids = data.cards.playable.map((c) => c.id).toSet();
      for (final id in campaign.cardUnlocks.keys) {
        expect(ids, contains(id), reason: '$id is not in the roster');
      }
    });

    // The starter deck has to be playable at level 1, and a card locked
    // behind a level the campaign never reaches would be dead content.
    test('the starter deck is never locked', () {
      for (final id in data.defaultDeck.cardIds) {
        expect(
          campaign.unlockLevelFor(id),
          isNull,
          reason: '$id is in the starter deck but locked',
        );
        expect(campaign.isCardUnlocked(id, 0), isTrue);
      }
    });

    test('every card is reachable, and well before the end', () {
      for (final card in data.cards.playable) {
        final at = campaign.unlockLevelFor(card.id) ?? 0;
        expect(
          at,
          inInclusiveRange(0, campaign.levelCount),
          reason: '${card.id} unlocks at $at, outside the campaign',
        );
      }

      // The last card should land before the bot's own cards start
      // levelling, or the player meets a scaling opponent with a roster
      // they have not finished collecting.
      final last = campaign.cardUnlocks.values.fold(0, math.max);
      expect(
        last,
        lessThanOrEqualTo(campaign.botCardLevelFrom),
        reason: 'the roster completes at $last, after the bot starts scaling',
      );
    });

    test('no two cards unlock on the same level', () {
      final levels = campaign.cardUnlocks.values.toList();
      expect(levels.toSet(), hasLength(levels.length));
    });

    test('unlocks are spread rather than dumped in one stretch', () {
      final sorted = campaign.cardUnlocks.values.toList()..sort();
      expect(
        sorted.first,
        greaterThan(1),
        reason: 'level 1 teaches, not gives',
      );
      // Gaps should widen: cheap variety early, expensive cards later.
      expect(sorted.first, lessThan(10));
      expect(sorted.last, greaterThan(sorted.first * 4));
    });

    test('a level hands over at most one card', () {
      for (final level in campaign.cardUnlocks.values) {
        expect(campaign.cardUnlockedAt(level), isNotNull);
      }
      expect(campaign.cardUnlockedAt(2), isNull);
    });
  });

  group('stars', () {
    test('a loss or a draw is worth nothing', () {
      expect(campaign.starsFor(won: false, playerShare: 0.94), 0);
      expect(campaign.starsFor(won: false, playerShare: 0.5), 0);
    });

    test('the first star is the win itself', () {
      expect(campaign.starsFor(won: true, playerShare: 0.51), 1);
    });

    test('the second and third are coverage', () {
      expect(
        campaign.starsFor(won: true, playerShare: campaign.twoStarCoverage),
        2,
      );
      expect(
        campaign.starsFor(won: true, playerShare: campaign.threeStarCoverage),
        3,
      );
      expect(campaign.starsFor(won: true, playerShare: 1.0), 3);
    });

    test('the next threshold is what a partial clear is missing', () {
      expect(campaign.nextStarAt(1), campaign.twoStarCoverage);
      expect(campaign.nextStarAt(2), campaign.threeStarCoverage);
      expect(campaign.nextStarAt(3), isNull);
      expect(campaign.nextStarAt(0), isNull);
    });
  });

  group('banking a level', () {
    _TestProfile fresh([PlayerProfile initial = const PlayerProfile()]) =>
        _TestProfile(data: data, initial: initial);

    test('a first clear records its stars and pays for them', () {
      final controller = fresh();
      final reward = controller.applyCampaignLevel(
        level: 1,
        stars: 2,
        tally: _tally,
      );

      expect(controller.state.starsOnLevel(1), 2);
      expect(controller.state.campaignCleared, 1);
      expect(controller.state.campaignNextLevel, 2);
      expect(reward.firstClear, isTrue);
      expect(reward.coins, 2 * campaign.coinsPerStar);
      expect(controller.state.coins, reward.coins);
    });

    // Otherwise replaying level 1 forever is a coin faucet.
    test('replaying a level no better pays nothing', () {
      final controller = fresh();
      controller.applyCampaignLevel(level: 1, stars: 3, tally: _tally);
      final coinsAfterFirst = controller.state.coins;

      final again = controller.applyCampaignLevel(
        level: 1,
        stars: 3,
        tally: _tally,
      );

      expect(again.coins, 0);
      expect(again.improved, isFalse);
      expect(controller.state.coins, coinsAfterFirst);
    });

    test('only the improvement pays when a level is replayed better', () {
      final controller = fresh();
      controller.applyCampaignLevel(level: 1, stars: 1, tally: _tally);
      final after = controller.applyCampaignLevel(
        level: 1,
        stars: 3,
        tally: _tally,
      );

      expect(after.coins, 2 * campaign.coinsPerStar);
      expect(controller.state.starsOnLevel(1), 3);
    });

    test('a worse replay never takes stars away', () {
      final controller = fresh();
      controller.applyCampaignLevel(level: 1, stars: 3, tally: _tally);
      controller.applyCampaignLevel(level: 1, stars: 1, tally: _tally);

      expect(controller.state.starsOnLevel(1), 3);
    });

    test('a loss clears nothing', () {
      final controller = fresh();
      controller.applyCampaignLevel(
        level: 1,
        stars: 0,
        tally: const MatchTally(
          won: false,
          cardsPlayed: 3,
          spellsPlayed: 0,
          paintSharePercent: 40,
        ),
      );

      expect(controller.state.campaignCleared, 0);
      expect(controller.state.campaignNextLevel, 1);
      expect(controller.state.coins, 0);
    });

    // Levels are the only way to fight, so a clear has to pay the trophies
    // that unlock arenas and the extra chest slots — nothing else does.
    test('a first clear pays trophies', () {
      final controller = fresh(const PlayerProfile(trophies: 120));
      final reward = controller.applyCampaignLevel(
        level: 5,
        stars: 3,
        tally: _tally,
      );

      expect(reward.trophies, greaterThan(0));
      expect(controller.state.trophies, 120 + reward.trophies);
    });

    // And this is the rule that keeps the single progression honest. Without
    // it, replaying level 1 is unlimited trophies and unlimited chests, and a
    // player reaches Arena 4 without ever meeting a harder opponent.
    test('a replay pays no trophies and no chest, however well it goes', () {
      final controller = fresh(const PlayerProfile(trophies: 120));
      controller.applyCampaignLevel(level: 1, stars: 1, tally: _tally);

      final trophiesAfterFirst = controller.state.trophies;
      final chestsAfterFirst = controller.state.chests.length;

      // Replayed better: the improved stars still pay coins, nothing else.
      final again = controller.applyCampaignLevel(
        level: 1,
        stars: 3,
        tally: _tally,
      );

      expect(again.trophies, 0);
      expect(again.chestKept, isFalse);
      expect(again.coins, greaterThan(0), reason: 'the new stars still pay');
      expect(controller.state.trophies, trophiesAfterFirst);
      expect(controller.state.chests, hasLength(chestsAfterFirst));
    });

    // Quick Battle used to hand out a chest per win and it was where upgrade
    // copies came from. With it gone, one chest per ten levels would starve
    // card levels entirely.
    test('every first clear earns a chest, not only the marked levels', () {
      final controller = fresh();
      final reward = controller.applyCampaignLevel(
        level: 3,
        stars: 1,
        tally: _tally,
      );

      expect(campaign.chestOn(3), isFalse, reason: 'not a marked level');
      expect(reward.chestKept, isTrue);
      expect(controller.state.chests, hasLength(1));
    });

    test('a loss pays nothing at all', () {
      final controller = fresh(const PlayerProfile(trophies: 90));
      final reward = controller.applyCampaignLevel(
        level: 1,
        stars: 0,
        tally: const MatchTally(
          won: false,
          cardsPlayed: 3,
          spellsPlayed: 0,
          paintSharePercent: 40,
        ),
      );

      expect(reward.trophies, 0);
      expect(reward.coins, 0);
      expect(reward.chestKept, isFalse);
      expect(controller.state.trophies, 90);
      expect(controller.state.chests, isEmpty);
    });

    // A campaign level is still a match, so the day's quests have to move.
    // Playing the campaign instead of the ladder should not quietly cost the
    // player their dailies.
    test('quests still count on a campaign level', () {
      final controller = fresh(
        PlayerProfile(
          quests: const [QuestProgress(questId: 'win_two')],
          questDay: QuestConfig.dayKey(DateTime.now()),
        ),
      );

      controller.applyCampaignLevel(level: 1, stars: 3, tally: _tally);

      final quest = controller.state.quests.firstWhere(
        (q) => q.questId == 'win_two',
      );
      expect(quest.progress, 1);
    });

    test('a chest lands on the marked levels only', () {
      final n = campaign.chestEveryLevels;
      expect(campaign.chestOn(n), isTrue);
      expect(campaign.chestOn(n + 1), isFalse);

      final controller = fresh();
      final reward = controller.applyCampaignLevel(
        level: n,
        stars: 1,
        tally: _tally,
      );
      expect(reward.chestKept, isTrue);
      expect(controller.state.chests, hasLength(1));
    });

    test('a milestone pays its bonus once', () {
      final n = campaign.milestoneEveryLevels;
      final controller = fresh();

      final first = controller.applyCampaignLevel(
        level: n,
        stars: 1,
        tally: _tally,
      );
      expect(first.coins, campaign.coinsPerStar + campaign.milestoneCoins);

      final second = controller.applyCampaignLevel(
        level: n,
        stars: 2,
        tally: _tally,
      );
      expect(second.coins, campaign.coinsPerStar);
    });
  });

  group('unlocking', () {
    test('only the next level is playable', () {
      const profile = PlayerProfile(campaignStars: {1: 3, 2: 1});

      expect(profile.isLevelUnlocked(1), isTrue);
      expect(profile.isLevelUnlocked(2), isTrue);
      expect(profile.isLevelUnlocked(3), isTrue);
      expect(profile.isLevelUnlocked(4), isFalse);
      expect(profile.campaignNextLevel, 3);
      expect(profile.campaignTotalStars, 4);
    });

    test('a fresh profile starts at level 1', () {
      const profile = PlayerProfile();

      expect(profile.campaignCleared, 0);
      expect(profile.campaignNextLevel, 1);
      expect(profile.isLevelUnlocked(1), isTrue);
      expect(profile.isLevelUnlocked(2), isFalse);
    });
  });

  group('the save file', () {
    test('stars survive a round trip', () {
      const profile = PlayerProfile(campaignStars: {1: 3, 2: 1, 47: 2});
      final restored = PlayerProfile.fromJson(profile.toJson());

      expect(restored.campaignStars, {1: 3, 2: 1, 47: 2});
      expect(restored.campaignNextLevel, 48);
    });

    // A corrupt save should cost the campaign, not the whole profile.
    test('a junk star map is dropped rather than thrown', () {
      final restored = PlayerProfile.fromJson({
        'coins': 90,
        'campaignStars': {'oops': 2, '5': 3},
      });

      expect(restored.coins, 90);
      expect(restored.campaignStars, {5: 3});
    });

    test('a save from before the campaign still loads', () {
      final restored = PlayerProfile.fromJson({'coins': 12, 'trophies': 300});

      expect(restored.campaignStars, isEmpty);
      expect(restored.campaignNextLevel, 1);
    });
  });
}
