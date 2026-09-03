import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/bot/bot_brain.dart';
import 'package:splatfront/game/bot/bot_difficulty.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';

/// A fixed stand-in for a person, so tuning a tier never moves the yardstick.
///
/// Reacts in about a second and a half, wastes a third of its turns, answers
/// pushes, plays spells, and picks the right lane and card about half the
/// time. Deliberately mediocre: this is who the tiers are for.
const _casual = BotDifficulty(
  tier: BotTier.normal,
  reactionDelay: 1.5,
  elixirWasteRate: 0.35,
  countersThreats: true,
  playsSpells: true,
  lanePrecision: 0.5,
  cardPrecision: 0.5,
);

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

  Future<double> duel(
    WidgetTester tester, {
    required BotDifficulty player,
    required BotDifficulty bot,
    required int seed,
  }) async {
    final game = SplatfrontGame(
      layout: ArenaLayout.fallback,
      cards: cards,
      deck: playerDeck,
      botDeck: config.deckFor('arena_1'),
      economy: rules,
      playerTeam: Team.blue,
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.runAsync(() => game.arena.resampleNow());

    await game.add(
      BotBrain(side: game.opponent, difficulty: bot, random: math.Random(seed)),
    );
    await game.add(
      BotBrain(
        side: game.player,
        difficulty: player,
        random: math.Random(seed + 7777),
      ),
    );
    game.updateTree(0);

    for (var half = 0; half < 180; half++) {
      for (var f = 0; f < 30; f++) {
        game.updateTree(1 / 60);
      }
      game.arena.paintLayer.flush();
      await tester.runAsync(() => game.arena.resampleNow());
    }

    final share = game.arena.coverage.value.forTeam(Team.blue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    return share;
  }

  for (final tier in BotTier.values) {
    testWidgets('casual person vs ${tier.name}', (tester) async {
      var wins = 0;
      var total = 0.0;
      const runs = 12;
      for (var i = 0; i < runs; i++) {
        final share = await duel(
          tester,
          player: _casual,
          bot: config[tier],
          seed: 1000 + i * 13,
        );
        total += share;
        if (share > 0.5) wins++;
      }
      // ignore: avoid_print
      print(
        'RESULT vs=${tier.name} wins=$wins/$runs '
        'coverage=${(total / runs * 100).toStringAsFixed(1)}%',
      );
    });
  }
}
