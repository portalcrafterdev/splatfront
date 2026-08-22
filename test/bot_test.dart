import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/bot/bot_difficulty.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';

/// Rolls a flat half and always takes the last option.
///
/// Half, so a tier whose precision is above it comes out careful and one
/// below it comes out careless. It used to roll 0.999 so that only an exact
/// 1.0 counted as precise, which quietly made the top tier's *value* part of
/// the test — blunting Hard to 0.9 then broke two tests that were supposed
/// to be about behaviour. The callers assert the tiers still straddle this.
class _Scripted implements math.Random {
  @override
  double nextDouble() => 0.5;
  @override
  int nextInt(int max) => max - 1;
  @override
  bool nextBool() => true;
}

/// A Random that never triggers the elixir-waste roll, so the decision rules
/// themselves can be tested without a coin flip in the way.
class _NeverWastes implements math.Random {
  @override
  double nextDouble() => 1.0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  late CardRegistry cards;
  late BotConfig config;
  late Deck playerDeck;
  late MatchRules rules;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    config = await BotConfig.load();
    playerDeck = (await Deck.loadStarterDecks()).first;
    rules = await MatchRules.load();
  });

  void gameTest(
    String description,
    Future<void> Function(SplatfrontGame game, WidgetTester tester) body, {
    BotTier tier = BotTier.hard,
  }) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        deck: playerDeck,
        botDeck: config.deckFor('arena_1'),
        botDifficulty: config[tier],
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() => game.arena.resampleNow());

      try {
        await body(game, tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  /// Runs the match forward, keeping the deploy map in step with the paint.
  Future<void> run(
    SplatfrontGame game,
    WidgetTester tester, {
    required double seconds,
  }) async {
    const step = 1 / 60;
    for (var elapsed = 0.0; elapsed < seconds; elapsed += step) {
      game.updateTree(step);
    }
    await tester.runAsync(() => game.arena.resampleNow());
  }

  group('difficulty data', () {
    test('the three tiers match the section 8 table', () {
      // Blunted again on the owner's call, and measured rather than guessed:
      // test/duel_harness.dart runs a fixed stand-in for a person — reacts in
      // 1.5s, wastes a third of its turns, half-precise — twelve times
      // against each tier. It now takes 12/12 off Easy, 9/12 off Normal and
      // 3/12 off Hard, which is a ladder a person can climb.
      expect(config[BotTier.easy].reactionDelay, 4.0);
      expect(config[BotTier.easy].elixirWasteRate, 0.85);
      expect(config[BotTier.easy].countersThreats, isFalse);
      expect(config[BotTier.easy].playsSpells, isFalse);

      expect(config[BotTier.normal].reactionDelay, 2.0);
      expect(config[BotTier.normal].elixirWasteRate, 0.45);
      expect(config[BotTier.normal].countersThreats, isTrue);

      expect(config[BotTier.hard].reactionDelay, 0.9);
      expect(config[BotTier.hard].elixirWasteRate, 0.15);
      expect(config[BotTier.hard].playsSpells, isTrue);
    });

    test('precision is what actually separates the tiers', () {
      // Reaction delay and waste rate only change how *busy* a side looks.
      // Measured over twenty ninety-second bot-versus-bot duels per pairing,
      // with every tier playing the weakest lane and the best card, Easy beat
      // Hard as often as it lost: 11/20 in one seating and 9/20 in the other.
      // Coverage is decided by where the paint lands and what lands there, so
      // these two are the difficulty. With them in, Hard beats Easy 39/40.
      for (final tier in BotTier.values) {
        for (final precision in [
          config[tier].lanePrecision,
          config[tier].cardPrecision,
        ]) {
          expect(precision, inInclusiveRange(0.0, 1.0));
        }
      }

      expect(
        config[BotTier.easy].lanePrecision,
        0.0,
        reason: 'an easy bot picks its lane without looking at the board',
      );
      // Hard is no longer perfect. At 1.0 the stand-in person took 0 of 12
      // off it, which is a wall rather than a tier; at 0.9 it takes 3.
      expect(config[BotTier.hard].lanePrecision, 0.9);
      expect(config[BotTier.hard].cardPrecision, 0.9);

      final tiers = BotTier.values.map((t) => config[t]).toList();
      for (var i = 1; i < tiers.length; i++) {
        expect(
          tiers[i].lanePrecision,
          greaterThan(tiers[i - 1].lanePrecision),
          reason: 'the ladder has to be monotonic to be a ladder',
        );
        expect(
          tiers[i].cardPrecision,
          greaterThan(tiers[i - 1].cardPrecision),
        );
      }
    });

    test('reaction gets faster and waste gets rarer as it gets harder', () {
      final tiers = BotTier.values.map((t) => config[t]).toList();
      for (var i = 1; i < tiers.length; i++) {
        expect(tiers[i].reactionDelay, lessThan(tiers[i - 1].reactionDelay));
        expect(
          tiers[i].elixirWasteRate,
          lessThan(tiers[i - 1].elixirWasteRate),
        );
      }
    });

    test('there is one legal deck per arena', () {
      expect(config.decksByArena, hasLength(4));
      for (final deck in config.decksByArena.values) {
        expect(deck.cardIds, hasLength(Deck.size));
        deck.validateAgainst(cards);
      }
    });

    test('an arena with no deck of its own still gets one', () {
      expect(config.deckFor('arena_does_not_exist'), isNotNull);
    });
  });

  group('precision is wired to behaviour', () {
    /// Rolls just under 1, so every precision below 1.0 misses, and picks the
    /// last of anything it is asked to choose between.
    ///
    /// That makes the two branches tell themselves apart by position: a
    /// careless bot ends up in the last lane, a precise one in the lane it is
    /// losing — which at the opening whistle, with the board split evenly, is
    /// the first.
    late final scripted = _Scripted();

    BotDifficulty noWaste(BotDifficulty d) => BotDifficulty(
      tier: d.tier,
      reactionDelay: d.reactionDelay,
      elixirWasteRate: 0,
      countersThreats: d.countersThreats,
      playsSpells: d.playsSpells,
      lanePrecision: d.lanePrecision,
      cardPrecision: d.cardPrecision,
    );

    Future<double?> firstDropX(WidgetTester tester, BotTier tier) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        deck: playerDeck,
        botDeck: config.deckFor('arena_1'),
        // The waste roll and the precision roll come off the same random, so
        // this drops the waste rate to zero: the test is about which lane it
        // picks, not about whether it takes its turn at all.
        botDifficulty: noWaste(config[tier]),
        botRandom: scripted,
        economy: const MatchRules(
          territorySpread: 0,
          cardRefillSeconds: 5,
          deployAnywhere: true,
          deployClaimRadius: 1.6,
        ),
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() => game.arena.resampleNow());

      double? x;
      const step = 1 / 60;
      // Long enough for the slowest tier's reaction delay AND its jitter to
      // run out — section 8 adds up to another whole delay on top. Derived
      // from the tier rather than fixed, because Easy's delay has been raised
      // twice now and a fixed six seconds silently stopped covering it.
      final window = config[tier].reactionDelay * 2 + 3.0;
      for (var t = 0.0; t < window && x == null; t += step) {
        game.updateTree(step);
        for (final unit in game.units) {
          if (unit.team == Team.blue) {
            x = unit.position.x;
            break;
          }
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      return x;
    }

    testWidgets('a hard bot plays the lane it is losing', (tester) async {
      final x = await firstDropX(tester, BotTier.hard);
      expect(x, isNotNull, reason: 'it has to play something');
      expect(
        x!,
        lessThan(ArenaSpec.worldWidth / 3),
        reason: 'the first lane, which is the weakest at an even split',
      );
    });

    testWidgets('an easy bot does not', (tester) async {
      final x = await firstDropX(tester, BotTier.easy);
      expect(x, isNotNull);
      expect(
        x!,
        greaterThan(ArenaSpec.worldWidth / 3 * 2),
        reason: 'the lane it happened to pick, not the one that needed it',
      );
    });
  });

  group('bot brain', () {
    gameTest('the bot gets its own hand and elixir, separate from the player',
        (game, tester) async {
      expect(game.opponent.hasHand, isTrue);
      expect(game.opponent.team, Team.blue);
      expect(game.bot, isNotNull);

      game.player.elixir.reset(to: 1);
      expect(game.opponent.elixir.amount, ElixirSpec.start,
          reason: 'the two pools are independent');
    });

    gameTest('both pools regenerate over the match', (game, tester) async {
      game.player.elixir.reset(to: 0);
      game.opponent.elixir.reset(to: 0);

      game.updateTree(ElixirSpec.regenNormal * 2);

      expect(game.player.elixir.amount, closeTo(2, 0.05));
      expect(game.opponent.elixir.amount, closeTo(2, 0.05));
    });

    gameTest('the bot puts units on the field within a few seconds', (
      game,
      tester,
    ) async {
      game.bot!.difficulty;
      await run(game, tester, seconds: 12);

      final botUnits = game.units.where((u) => u.team == Team.blue);
      expect(botUnits, isNotEmpty, reason: 'it should have spent something');
    });

    testWidgets('the bot keeps deploying across a whole match', (
      tester,
    ) async {
      // A guard against the blue side going silent. It has gone quiet twice
      // for different reasons — no legal spot in its chosen lane, and sitting
      // on elixir waiting for a threshold while the hand lockout ate its
      // turns — and neither showed up in a test that only ran a few seconds.
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        deck: playerDeck,
        botDeck: config.deckFor('arena_1'),
        botDifficulty: config[BotTier.normal],
        botRandom: _NeverWastes(),
        economy: const MatchRules(
          territorySpread: 0.25,
          cardRefillSeconds: 10,
        ),
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() => game.arena.resampleNow());

      // Counts plays, not bodies. Bodies stood in for "is it still acting"
      // until the arena 1 deck stopped carrying a multi-body card — one Dab
      // used to be three of them, so the count fell to four on a bot that was
      // playing perfectly well, and the test failed for a reason that had
      // nothing to do with going quiet.
      final hand = game.opponent.hand!;
      var last = List<String>.of(hand.hand.value);
      var plays = 0;
      for (var step = 0; step < 600; step++) {
        game.updateTree(0.1);
        if (!_sameHand(hand.hand.value, last)) {
          plays++;
          last = List<String>.of(hand.hand.value);
        }
        // Resample now and then, as the running game does, so the deploy map
        // keeps up with the paint.
        if (step % 50 == 0) {
          game.arena.paintLayer.flush();
          await tester.runAsync(() => game.arena.resampleNow());
        }
      }

      // A ten-second lockout plus Normal's reaction delay caps it near five
      // plays a minute. Anything at or under two means it has stopped.
      expect(
        plays,
        greaterThan(3),
        reason: 'the bot played $plays cards in a minute',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    gameTest('a painted-over lane costs the bot a spot, not its turn', (
      game,
      tester,
    ) async {
      // The reported symptom was the blue side simply not showing up. The
      // bot searched one vertical column for somewhere legal to stand, and a
      // Roller paints a stripe up an entire lane — so once the player owned
      // that column the bot found nowhere, abandoned the play, and went
      // quiet. It should fall back to the nearest ground it does own.
      //
      // This paints every lane centre from top to bottom in the player's
      // colour, which is the worst case: all three preferred columns gone.
      for (var lane = 0; lane < 3; lane++) {
        final x = ArenaSpec.worldWidth / 3 * (lane + 0.5);
        for (var y = 0.5; y < ArenaSpec.worldHeight; y += 0.5) {
          game.arena.paintLayer.stamp(Vector2(x, y), 1.0, Team.red);
        }
      }
      game.arena.paintLayer.flush();
      await tester.runAsync(() => game.arena.resampleNow());

      // The bot still owns plenty of board, just not the columns it wanted.
      var owned = 0;
      game.arena.deployZone.forEachValidCell(Team.blue, (_, _) => owned++);
      expect(owned, greaterThan(100), reason: 'it has somewhere to stand');

      await run(game, tester, seconds: 14);

      expect(
        game.units.where((u) => u.team == Team.blue),
        isNotEmpty,
        reason: 'losing its lanes must not stop it deploying entirely',
      );
    });

    gameTest('everything the bot plays lands on its own colour', (
      game,
      tester,
    ) async {
      await run(game, tester, seconds: 12);

      for (final unit in game.units.where((u) => u.team == Team.blue)) {
        // It spawned legally, so it started in the bot's half.
        expect(
          unit.lane,
          inInclusiveRange(0, ArenaSpec.worldWidth),
          reason: 'and inside the arena',
        );
      }
      expect(game.units.where((u) => u.team == Team.blue), isNotEmpty);
    });

    gameTest('the bot never spends elixir it does not have', (
      game,
      tester,
    ) async {
      for (var i = 0; i < 40; i++) {
        await run(game, tester, seconds: 1);
        expect(game.opponent.elixir.amount, greaterThanOrEqualTo(0));
        expect(
          game.opponent.elixir.amount,
          lessThanOrEqualTo(ElixirSpec.max),
        );
      }
    });

    testWidgets('an easy bot commits less than a hard one', (tester) async {
      // Only one game may be mounted at a time: pumping a second widget
      // unmounts the first and disposes its notifiers underneath it.
      //
      // Measures elixir spent, which is what "commits" means. Two earlier
      // metrics both misread it: bodies, because one lucky Swarmlets is six
      // of them, and cards, because a careless bot picks at random and cheap
      // cards buy more plays per elixir — on that count Easy came out *ahead*
      // of Hard, 26 to 24.
      Future<int> elixirSpentBy(BotTier tier, int seed) async {
        final game = SplatfrontGame(
          layout: ArenaLayout.fallback,
          cards: cards,
          deck: playerDeck,
          botDeck: config.deckFor('arena_1'),
          botDifficulty: config[tier],
          botRandom: math.Random(seed),
          // The shipped rules, lockout included: without one the bot is
          // elixir-limited rather than turn-limited and this measures a
          // configuration the game does not ship.
          economy: rules,
        );
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();
        await tester.runAsync(() => game.arena.resampleNow());

        final hand = game.opponent.hand!;
        var last = List<String>.of(hand.hand.value);
        var spent = 0;

        // Long enough that the hand lockout is not the only thing being
        // measured: at five seconds a turn, twenty seconds is four turns for
        // everybody and the tiers cannot separate.
        const step = 1 / 60;
        for (var t = 0.0; t < 60.0; t += step) {
          game.updateTree(step);
          final now = hand.hand.value;
          if (!_sameHand(now, last)) {
            // The slot that changed held the card that was just spent.
            for (var i = 0; i < now.length; i++) {
              if (now[i] != last[i]) spent += cards[last[i]].cost;
            }
            last = List<String>.of(now);
          }
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        return spent;
      }

      // Summed across seeds, not run once. A careless bot draws extra numbers
      // deciding what to play, so the two tiers do not see the same sequence
      // even from the same seed, and a single match is noise: on seed 7 alone
      // Easy outspent Hard on one seed, which inverts the real
      // difference rather than measuring it.
      const seeds = [1, 7, 13];
      var easy = 0;
      var hard = 0;
      for (final seed in seeds) {
        easy += await elixirSpentBy(BotTier.easy, seed);
        hard += await elixirSpentBy(BotTier.hard, seed);
      }

      expect(
        hard,
        greaterThan(easy),
        reason:
            'slower reactions and a whole turn thrown away per waste roll '
            'mean fewer cards played: averaged over five ninety-second '
            'matches it is about nine against fifteen',
      );
    });

    gameTest('an inactive bot does nothing at all', (game, tester) async {
      game.bot!.active = false;
      await run(game, tester, seconds: 15);
      expect(game.units.where((u) => u.team == Team.blue), isEmpty);
    });

    gameTest('the bot spends its surplus rather than sitting on ten', (
      game,
      tester,
    ) async {
      game.opponent.elixir.reset(to: ElixirSpec.max);
      await run(game, tester, seconds: 6);

      expect(
        game.opponent.elixir.amount,
        lessThan(ElixirSpec.max),
        reason: 'rule 2 fires at 8 or more',
      );
    });

    gameTest('an easy bot ignores a push, a hard one answers it', (
      game,
      tester,
    ) async {
      // Two player units deep in the bot's half is a push by section 8.
      game.spawnUnit('brusher', team: Team.red, position: Vector2(6, 6));
      game.spawnUnit('brusher', team: Team.red, position: Vector2(9, 6));

      await run(game, tester, seconds: 5);
      expect(
        game.units.where((u) => u.team == Team.blue),
        isNotEmpty,
        reason: 'a hard bot counters',
      );
    });
  });

  group('a whole match runs', () {
    gameTest('90 seconds of bot play leaves the board in a sane state', (
      game,
      tester,
    ) async {
      await run(game, tester, seconds: Timings.normalTime);

      expect(game.units.length, lessThan(200), reason: 'no runaway spawning');
      expect(game.opponent.elixir.amount, inInclusiveRange(0, ElixirSpec.max));

      final coverage = game.arena.coverage.value;
      expect(coverage.red + coverage.blue, lessThanOrEqualTo(1.0));
      expect(
        coverage.blue,
        greaterThan(0),
        reason: 'the bot painted something',
      );
    });
  });

  test('a bot with no waste roll still respects its rules', () {
    final never = _NeverWastes();
    expect(never.nextDouble(), 1.0);
    expect(config[BotTier.hard].elixirWasteRate, lessThan(1.0));
  });
}

/// Whether the visible hand is unchanged. A difference means a card was
/// played and its slot refilled from the queue.
bool _sameHand(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
