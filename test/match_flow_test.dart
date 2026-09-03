import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/audio.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/arena/paint_sampler.dart';
import 'package:splatfront/game/bot/bot_difficulty.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/match/match_controller.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';

void main() {
  late CardRegistry cards;
  late BotConfig botConfig;
  late TrophyRules trophies;
  late Deck deck;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    botConfig = await BotConfig.load();
    trophies = await TrophyRules.load();
    deck = (await Deck.loadStarterDecks()).first;
  });

  void gameTest(
    String description,
    Future<void> Function(SplatfrontGame game, WidgetTester tester) body, {
    bool withBot = false,
  }) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        deck: deck,
        botDeck: withBot ? botConfig.deckFor('arena_1') : null,
        botDifficulty: withBot ? botConfig[BotTier.normal] : null,
        trophyRules: trophies,
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

  void run(SplatfrontGame game, double seconds) {
    const step = 1 / 60;
    for (var elapsed = 0.0; elapsed < seconds; elapsed += step) {
      game.updateTree(step);
    }
  }

  /// Paints the whole arena for [team] and refreshes the coverage reading.
  Future<void> paintEverything(
    SplatfrontGame game,
    WidgetTester tester,
    Team team,
  ) async {
    for (var y = 0.0; y < ArenaSpec.worldHeight; y += 1.0) {
      for (var x = 0.0; x < ArenaSpec.worldWidth; x += 1.0) {
        game.arena.paintLayer.stamp(Vector2(x, y), 1.6, team);
      }
    }
    game.arena.paintLayer.flush();
    await tester.runAsync(() => game.arena.resampleNow());
  }

  group('countdown', () {
    gameTest('a match opens on the countdown, not on play', (
      game,
      tester,
    ) async {
      expect(game.match!.phase.value, MatchPhase.countdown);
      expect(game.match!.timeRemaining.value, closeTo(Timings.countdown, 0.1));
    });

    gameTest('nothing may be deployed before Splat', (game, tester) async {
      expect(game.acceptsInput, isFalse);
      expect(game.beginDeploy(0), isFalse);
      expect(game.playFromHand(game.player, 0, Vector2(8, 22)), isFalse);
      expect(game.units, isEmpty);
    });

    gameTest('no elixir accrues during the countdown', (game, tester) async {
      game.player.elixir.reset(to: 5);
      run(game, 2);
      expect(game.player.elixir.amount, 5);
    });

    gameTest('play starts, and elixir with it, once the countdown ends', (
      game,
      tester,
    ) async {
      run(game, Timings.countdown + 0.1);

      expect(game.match!.phase.value, MatchPhase.playing);
      expect(game.acceptsInput, isTrue);
      expect(game.match!.timeRemaining.value, closeTo(Timings.normalTime, 0.5));

      final before = game.player.elixir.amount;
      run(game, ElixirSpec.regenNormal);
      expect(game.player.elixir.amount, greaterThan(before));
    });

    gameTest('the countdown counts 3, 2, 1, Splat', (game, tester) async {
      expect(game.match!.countdownNumber, 3);
      // A hair over a second each time: 60 steps of 1/60 sums to just under
      // 1.0, which leaves ceil() reading the second that just passed.
      run(game, 1.05);
      expect(game.match!.countdownNumber, 2);
      run(game, 1.05);
      expect(game.match!.countdownNumber, 1);
      run(game, 1.05);
      expect(game.match!.countdownNumber, isNull, reason: 'play has begun');
    });
  });

  group('the whistle', () {
    gameTest('silences the fight but not the outcome', (game, tester) async {
      // The arena does not stop when the clock does. Units already swinging
      // keep fighting, dying and painting under the result overlay, and every
      // one of those made a noise right up until the player pressed a button
      // to leave the screen.
      Audio.gameplayMuted = false;
      run(game, Timings.countdown + 0.1);
      expect(Audio.gameplayMuted, isFalse, reason: 'a live match is audible');

      await paintEverything(game, tester, Team.red);
      run(game, Timings.normalTime + 0.1);

      expect(game.match!.phase.value, MatchPhase.finished);
      expect(
        Audio.gameplayMuted,
        isTrue,
        reason: 'the fight goes quiet the moment the clock does',
      );
      // The mute is deliberately narrow: it must not take the result screen
      // with it.
      expect(Sfx.victory.isGameplay, isFalse);
      expect(Sfx.defeat.isGameplay, isFalse);

      Audio.gameplayMuted = false;
    });
  });

  group('the clock', () {
    gameTest('a clear lead at zero ends the match', (game, tester) async {
      run(game, Timings.countdown + 0.1);
      await paintEverything(game, tester, Team.red);

      run(game, Timings.normalTime + 0.1);

      expect(game.match!.phase.value, MatchPhase.finished);
      expect(game.match!.result.value, isNotNull);
      expect(game.match!.result.value!.reason, EndReason.instantWin);
    });

    gameTest('a close score at zero goes to sudden death', (
      game,
      tester,
    ) async {
      run(game, Timings.countdown + 0.1);
      // The start state is 42/42, which is inside the 5% threshold.
      run(game, Timings.normalTime + 0.1);

      expect(game.match!.phase.value, MatchPhase.suddenDeath);
      expect(
        game.match!.timeRemaining.value,
        closeTo(Timings.suddenDeathTime, 0.5),
      );
    });

    gameTest('sudden death doubles the elixir rate and nothing else', (
      game,
      tester,
    ) async {
      run(game, Timings.countdown + Timings.normalTime + 0.2);
      expect(game.match!.phase.value, MatchPhase.suddenDeath);

      expect(game.player.elixir.suddenDeath, isTrue);
      expect(game.opponent.elixir.suddenDeath, isTrue);
      expect(game.player.elixir.secondsPerElixir, ElixirSpec.regenSuddenDeath);
    });

    gameTest('sudden death running out finishes the match', (
      game,
      tester,
    ) async {
      run(
        game,
        Timings.countdown + Timings.normalTime + Timings.suddenDeathTime + 0.3,
      );

      expect(game.match!.phase.value, MatchPhase.finished);
      expect(game.match!.result.value!.reason, EndReason.suddenDeath);
    });

    gameTest('a finished match refuses further input', (game, tester) async {
      run(
        game,
        Timings.countdown + Timings.normalTime + Timings.suddenDeathTime + 0.3,
      );
      expect(game.acceptsInput, isFalse);
      expect(game.beginDeploy(0), isFalse);
    });
  });

  group('instant win', () {
    gameTest('95% held for three seconds ends it immediately', (
      game,
      tester,
    ) async {
      run(game, Timings.countdown + 0.1);
      await paintEverything(game, tester, Team.red);

      expect(
        game.arena.coverage.value.red,
        greaterThanOrEqualTo(Timings.instantWinCoverage),
      );

      // Not yet: the hold has to be continuous for three seconds.
      run(game, Timings.instantWinHold - 0.5);
      expect(game.match!.phase.value, MatchPhase.playing);

      run(game, 0.7);
      expect(game.match!.phase.value, MatchPhase.finished);
      expect(game.match!.result.value!.reason, EndReason.instantWin);
      expect(game.match!.result.value!.won, isTrue);
    });

    gameTest('losing the lead resets the hold', (game, tester) async {
      run(game, Timings.countdown + 0.1);
      await paintEverything(game, tester, Team.red);

      run(game, Timings.instantWinHold - 0.5);
      expect(game.match!.phase.value, MatchPhase.playing);

      // The other side takes it all back.
      await paintEverything(game, tester, Team.blue);
      run(game, 0.7);
      expect(
        game.match!.phase.value,
        MatchPhase.playing,
        reason: 'the hold restarted for the other side',
      );
    });

    gameTest('the wipe animation plays on a wipeout', (game, tester) async {
      run(game, Timings.countdown + 0.1);
      await paintEverything(game, tester, Team.red);
      run(game, Timings.instantWinHold + 0.2);

      expect(game.match!.result.value!.reason, EndReason.instantWin);
      run(game, 1.5);
      expect(game.match!.wipeProgress.value, 1.0);
    });

    gameTest('a normal finish plays no wipe', (game, tester) async {
      run(
        game,
        Timings.countdown + Timings.normalTime + Timings.suddenDeathTime + 0.3,
      );
      expect(game.match!.wipeProgress.value, 0);
    });
  });

  group('the result', () {
    test('more coverage wins, less loses, equal draws', () {
      MatchResult of(double red, double blue) => MatchResult(
        coverage: Coverage(red, blue),
        playerTeam: Team.red,
        reason: EndReason.timeUp,
        trophyChange: 0,
      );

      expect(of(0.6, 0.3).outcome, MatchOutcome.win);
      expect(of(0.3, 0.6).outcome, MatchOutcome.loss);
      expect(of(0.45, 0.45).outcome, MatchOutcome.draw);
      expect(of(0.6, 0.3).winner, Team.red);
      expect(of(0.45, 0.45).winner, isNull);
    });

    test('a win earns a chest, a loss does not', () {
      MatchResult of(double red, double blue) => MatchResult(
        coverage: Coverage(red, blue),
        playerTeam: Team.red,
        reason: EndReason.timeUp,
        trophyChange: 0,
      );
      expect(of(0.6, 0.3).chestEarned, isTrue);
      expect(of(0.3, 0.6).chestEarned, isFalse);
    });

    test('trophies are +30 and -25 against an even opponent', () {
      expect(
        trophies.change(
          outcome: MatchOutcome.win,
          playerTrophies: 500,
          opponentTrophies: 500,
        ),
        30,
      );
      expect(
        trophies.change(
          outcome: MatchOutcome.loss,
          playerTrophies: 500,
          opponentTrophies: 500,
        ),
        -25,
      );
      expect(
        trophies.change(
          outcome: MatchOutcome.draw,
          playerTrophies: 500,
          opponentTrophies: 900,
        ),
        0,
      );
    });

    test(
      'beating someone above you is worth more, losing to them costs less',
      () {
        final bigWin = trophies.change(
          outcome: MatchOutcome.win,
          playerTrophies: 500,
          opponentTrophies: 800,
        );
        final softLoss = trophies.change(
          outcome: MatchOutcome.loss,
          playerTrophies: 500,
          opponentTrophies: 800,
        );

        expect(bigWin, greaterThan(30));
        expect(softLoss, greaterThan(-25), reason: 'it hurts less');
      },
    );

    test('the adjustment is capped, and can never flip the sign', () {
      final absurdWin = trophies.change(
        outcome: MatchOutcome.win,
        playerTrophies: 0,
        opponentTrophies: 100000,
      );
      final absurdLoss = trophies.change(
        outcome: MatchOutcome.loss,
        playerTrophies: 100000,
        opponentTrophies: 0,
      );

      expect(absurdWin, lessThanOrEqualTo(30 + trophies.maxAdjustment));
      expect(absurdWin, greaterThan(0), reason: 'a win always gains');
      expect(absurdLoss, lessThan(0), reason: 'a loss always costs');
    });

    test('a harder bot counts as a stronger opponent', () {
      final easy = trophies.trophiesForBot(500, BotTier.easy);
      final normal = trophies.trophiesForBot(500, BotTier.normal);
      final hard = trophies.trophiesForBot(500, BotTier.hard);

      expect(easy, lessThan(normal));
      expect(normal, lessThan(hard));
      expect(
        trophies.trophiesForBot(0, BotTier.easy),
        0,
        reason: 'never negative',
      );
    });

    gameTest('a drawn match pays out nothing', (game, tester) async {
      // Neither side ever plays, so the 42/42 start state holds all the way
      // through sudden death.
      run(
        game,
        Timings.countdown + Timings.normalTime + Timings.suddenDeathTime + 0.3,
      );
      final result = game.match!.result.value!;
      expect(result.outcome, MatchOutcome.draw);
      expect(result.trophyChange, 0);
      expect(result.headline, 'DRAW');
      expect(result.subtitle, 'Sudden death');
    });

    gameTest('a win on the clock pays out trophies and a chest', (
      game,
      tester,
    ) async {
      run(game, Timings.countdown + 0.1);

      // Claim the neutral strip: a clear lead, but well short of a wipeout.
      for (var y = 10.0; y < 14.0; y += 0.5) {
        for (var x = 0.0; x < ArenaSpec.worldWidth; x += 1.0) {
          game.arena.paintLayer.stamp(Vector2(x, y), 1.2, Team.red);
        }
      }
      game.arena.paintLayer.flush();
      await tester.runAsync(() => game.arena.resampleNow());

      run(game, Timings.normalTime + 0.2);

      final result = game.match!.result.value!;
      expect(
        result.reason,
        EndReason.timeUp,
        reason: 'a clear gap skips sudden death',
      );
      expect(result.won, isTrue);
      expect(result.trophyChange, greaterThan(0));
      expect(result.chestEarned, isTrue);
    });
  });

  group('a full match against the bot', () {
    gameTest('runs from countdown to result without intervention', (
      game,
      tester,
    ) async {
      // Countdown, 90 seconds, and sudden death if it is close.
      run(game, Timings.countdown + Timings.normalTime + 1);
      await tester.runAsync(() => game.arena.resampleNow());

      if (game.match!.phase.value == MatchPhase.suddenDeath) {
        run(game, Timings.suddenDeathTime + 1);
      }

      expect(game.match!.phase.value, MatchPhase.finished);
      final result = game.match!.result.value!;
      expect(
        result.coverage.red + result.coverage.blue,
        lessThanOrEqualTo(1.0),
      );
      expect(game.acceptsInput, isFalse);
    }, withBot: true);
  });
}
