import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/cards/hand_controller.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';

/// The slot cooldown: after a card is played, the one that rotates in behind
/// it is visible but unplayable for a few seconds.
void main() {
  late CardRegistry cards;
  late Deck deck;
  late List<Deck> starters;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    // Loaded once here, never inside a testWidgets body: a rootBundle read
    // under the fake clock does not reliably complete.
    starters = await Deck.loadStarterDecks();
    deck = starters.first;
  });

  HandController hand({double refill = 10}) =>
      HandController(deck: deck, levels: const CardLevels(), refillSeconds: refill);

  test('a played slot goes cold and comes back on time', () {
    final h = hand();
    expect(h.isReady(0), isTrue);

    final played = h.play(0);
    expect(played, isNotNull);
    expect(h.isReady(0), isFalse, reason: 'the refilled slot is cooling');
    expect(h.secondsLeft(0), closeTo(10, 1e-9));
    expect(h.cooldownFraction(0), closeTo(1, 1e-9));

    h.update(4);
    expect(h.secondsLeft(0), closeTo(6, 1e-9));
    expect(h.cooldownFraction(0), closeTo(0.6, 1e-9));
    expect(h.isReady(0), isFalse);

    h.update(6.01);
    expect(h.isReady(0), isTrue, reason: 'ten seconds later it is back');
    expect(h.secondsLeft(0), 0);
  });

  test('the card behind is visible immediately, just not playable', () {
    final h = hand();
    final incoming = h.queue[h.handSize]; // front of the pending queue
    h.play(0);

    expect(
      h.cardIdAt(0),
      incoming,
      reason: 'you can see what you are waiting for',
    );
    expect(h.isReady(0), isFalse);
  });

  test('playing one card locks the whole hand', () {
    final h = hand();
    h.play(1);

    for (var slot = 0; slot < h.handSize; slot++) {
      expect(
        h.isReady(slot),
        isFalse,
        reason: 'slot $slot is locked too, not just the one played',
      );
      expect(h.play(slot), isNull);
    }

    h.update(10.01);
    for (var slot = 0; slot < h.handSize; slot++) {
      expect(h.isReady(slot), isTrue, reason: 'and they all come back at once');
    }
  });

  test('a locked hand refuses to be played again', () {
    final h = hand();
    final before = h.queue;
    h.play(0);
    final afterFirst = h.queue;

    expect(h.play(0), isNull, reason: 'refused while cooling');
    expect(h.queue, afterFirst, reason: 'and the rotation did not move');
    expect(afterFirst, isNot(before));
  });

  test('zero seconds keeps the old instant behaviour', () {
    final h = hand(refill: 0);
    h.play(0);
    expect(h.isReady(0), isTrue);
    expect(h.cooldownFraction(0), 0);
    expect(h.play(0), isNotNull, reason: 'straight back into rotation');
  });

  test('a reset clears every cooldown', () {
    final h = hand();
    h..play(0)..play(2);
    expect(h.hasCooldowns, isTrue);

    h.reset();
    expect(h.hasCooldowns, isFalse);
    for (var slot = 0; slot < h.handSize; slot++) {
      expect(h.isReady(slot), isTrue);
    }
  });

  test('the shipped lockout comes from progression.json', () async {
    final economy = await MatchRules.load();
    expect(economy.cardRefillSeconds, 5);

    // Measured: past about five seconds the lockout rather than elixir
    // becomes the constraint, and both sides run out of turns while sitting
    // on a full bar. Ten seconds roughly halved what reached the field.
    expect(
      economy.cardRefillSeconds,
      lessThanOrEqualTo(6),
      reason: 'a longer lockout empties the board',
    );
  });

  testWidgets('the game refuses a drag from a cooling slot', (tester) async {
    final game = SplatfrontGame(
      layout: ArenaLayout.fallback,
      cards: cards,
      deck: deck,
      economy: const MatchRules(territorySpread: 0, cardRefillSeconds: 10),
      playerTeam: Team.red,
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    // The deploy map is all neutral until the first readback lands, and a
    // deploy onto neutral ground is refused for reasons nothing to do with
    // cooldowns.
    await tester.runAsync(() => game.arena.resampleNow());

    // Enough elixir that affordability is never the reason for a refusal.
    game.elixir.value.value = 10;

    expect(game.beginDeploy(0), isTrue);
    game.cancelDeploy();

    // Play it for real, which puts the slot on cooldown.
    expect(
      game.playFromHand(game.player, 0, Vector2(8, 20)),
      isTrue,
    );
    expect(game.hand!.isReady(0), isFalse);

    game.elixir.value.value = 10;
    expect(
      game.beginDeploy(0),
      isFalse,
      reason: 'the hand is locked, however much elixir you have',
    );
    expect(game.draggingSlot.value, isNull);

    // Every other slot is locked too.
    expect(game.beginDeploy(1), isFalse);
    expect(game.beginDeploy(2), isFalse);

    // And it comes back once the game has ticked the clock forward.
    //
    // Eleven one-second steps rather than 660 frames: every frame bakes the
    // paint layer and walks the whole tree, and at real frame rate this test
    // took minutes. The cooldown only cares about elapsed time.
    for (var i = 0; i < 11; i++) {
      game.updateTree(1.0);
    }
    expect(game.hand!.isReady(0), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the bot is under the same brake', (tester) async {
    final game = SplatfrontGame(
      layout: ArenaLayout.fallback,
      cards: cards,
      deck: starters[0],
      botDeck: starters[1],
      economy: const MatchRules(territorySpread: 0, cardRefillSeconds: 10),
      playerTeam: Team.red,
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.runAsync(() => game.arena.resampleNow());

    game.opponent.elixir.value.value = 10;
    expect(
      game.playFromHand(game.opponent, 0, Vector2(8, 4)),
      isTrue,
    );
    expect(
      game.opponent.hand!.isReady(0),
      isFalse,
      reason: 'the bot gets no discount on the cooldown either',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
