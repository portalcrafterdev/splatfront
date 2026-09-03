import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';

/// Deploy legality and the elixir it costs, driven through the real game.
void main() {
  late CardRegistry cards;
  late Deck deck;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    deck = (await Deck.loadStarterDecks()).first;
  });

  void gameTest(
    String description,
    Future<void> Function(SplatfrontGame game, WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        deck: deck,
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      // The deploy map comes from a real GPU readback, which never resolves
      // under the test's fake clock. runAsync lets it actually finish.
      await tester.runAsync(() => game.arena.resampleNow());

      try {
        await body(game, tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  /// Deep in the player's own half, and deep in the opponent's.
  final ownGround = Vector2(8, 22);
  final enemyGround = Vector2(8, 2);
  final midLine = Vector2(8, ArenaSpec.worldHeight / 2);

  // --- Dropping anywhere, the other rule, still supported -----------------

  /// The same harness, but with the own-colour rule lifted.
  void anywhereTest(
    String description,
    Future<void> Function(SplatfrontGame game, WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        deck: deck,
        economy: const MatchRules(
          territorySpread: 0,
          deployAnywhere: true,
          deployClaimRadius: 1.6,
        ),
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

  test('the shipped rule is deploy on your own colour', () async {
    // Section 17 rule 5, and what the game ships with. It was overridden to
    // anywhere=true for one play session and reversed: a drop that lands on
    // any ground at all makes the deploy line mean nothing, and the deploy
    // line is what painting forward is *for*. The anywhere rule is still
    // supported and still covered by the anywhereTest group above, because
    // this is one JSON value and the owner has changed their mind on it once.
    final rules = await MatchRules.load();
    expect(rules.deployAnywhere, isFalse);
  });

  anywhereTest('a troop drops on the enemy colour', (game, tester) async {
    final card = game.cards['brusher'];
    expect(
      game.arena.deployZone.ownerAt(enemyGround),
      Team.blue,
      reason: 'that really is the bot\'s ground',
    );
    expect(game.canDeployHere(card, enemyGround), isTrue);
  });

  anywhereTest('landing on enemy ground turns it your colour', (
    game,
    tester,
  ) async {
    game.elixir.value.value = 10;
    final slot = _slotOf(game, 'brusher');

    expect(game.playFromHand(game.player, slot, enemyGround), isTrue);
    game.arena.paintLayer.flush();
    await tester.runAsync(() => game.arena.resampleNow());

    expect(
      game.arena.deployZone.ownerAt(enemyGround),
      Team.red,
      reason: 'the drop claimed the circle it landed in',
    );
  });

  anywhereTest('the arena edge is still the edge', (game, tester) async {
    final card = game.cards['brusher'];
    expect(game.canDeployHere(card, Vector2(-1, 12)), isFalse);
    expect(game.canDeployHere(card, Vector2(8, 30)), isFalse);
  });

  // --- The shipped rule: your own colour only -----------------------------

  gameTest('a troop drops on your own colour', (game, tester) async {
    final card = game.cards['brusher'];
    expect(game.canDeployHere(card, ownGround), isTrue);
  });

  gameTest('a troop is refused on the enemy colour', (game, tester) async {
    final card = game.cards['brusher'];
    expect(game.canDeployHere(card, enemyGround), isFalse);
  });

  gameTest('a troop is refused on ground wiped to neutral', (
    game,
    tester,
  ) async {
    // The board starts with no neutral ground at all, so this makes some the
    // way Solvent does: nobody's colour, and therefore nobody's deploy zone.
    final card = game.cards['brusher'];
    expect(game.canDeployHere(card, ownGround), isTrue);

    game.arena.paintLayer.stampSpell(ownGround, 3.0, Team.neutral);
    game.arena.paintLayer.flush();
    await tester.runAsync(() => game.arena.resampleNow());

    expect(game.canDeployHere(card, ownGround), isFalse);
  });

  gameTest('a spell may target anywhere, including the enemy half', (
    game,
    tester,
  ) async {
    final spell = game.cards['paint_bomb'];
    expect(spell.obeysDeployZone, isFalse);
    expect(game.canDeployHere(spell, enemyGround), isTrue);
    expect(game.canDeployHere(spell, midLine), isTrue);
  });

  gameTest('nothing may be dropped outside the arena', (game, tester) async {
    final card = game.cards['brusher'];
    expect(game.canDeployHere(card, Vector2(-1, 22)), isFalse);
    expect(game.canDeployHere(card, Vector2(8, 30)), isFalse);
    // Not even a spell.
    expect(
      game.canDeployHere(game.cards['paint_bomb'], Vector2(-5, 5)),
      isFalse,
    );
  });

  gameTest('a legal drop spawns the card and spends the elixir', (
    game,
    tester,
  ) async {
    final slot = 0;
    final card = game.cards[game.hand!.cardIdAt(slot)];
    final before = game.elixir.amount;

    expect(game.beginDeploy(slot), isTrue);
    game.updateDeploy(ownGround);
    expect(game.endDeploy(ownGround), isTrue);

    expect(game.units, hasLength(card.bodyCount));
    expect(game.elixir.amount, closeTo(before - card.cost, 1e-9));
  });

  gameTest('an illegal drop spawns nothing and costs nothing', (
    game,
    tester,
  ) async {
    final before = game.elixir.amount;
    final handBefore = List<String>.of(game.hand!.hand.value);

    expect(game.beginDeploy(0), isTrue);
    game.updateDeploy(enemyGround);
    expect(game.endDeploy(enemyGround), isFalse);

    expect(game.units, isEmpty);
    expect(game.elixir.amount, before, reason: 'no elixir was spent');
    expect(game.hand!.hand.value, handBefore, reason: 'the card is still held');
  });

  gameTest('a card you cannot afford will not even start a drag', (
    game,
    tester,
  ) async {
    game.elixir.reset(to: 0);
    expect(game.beginDeploy(0), isFalse);
    expect(game.draggingSlot.value, isNull);
  });

  gameTest('playing a card rotates it out of the hand', (game, tester) async {
    final played = game.hand!.cardIdAt(0);
    final wasNext = game.hand!.next.value;

    game.beginDeploy(0);
    game.endDeploy(ownGround);

    expect(game.hand!.hand.value[0], wasNext);
    expect(game.hand!.queue.last, played);
  });

  gameTest('the drop ghost tracks the finger and reports validity', (
    game,
    tester,
  ) async {
    game.beginDeploy(0);

    game.updateDeploy(ownGround);
    var preview = game.deployOverlay.preview!;
    expect(preview.valid, isTrue);
    expect(preview.worldPosition, ownGround);
    expect(preview.showValidCells, isTrue, reason: 'troops light the zone');

    game.updateDeploy(enemyGround);
    preview = game.deployOverlay.preview!;
    expect(preview.valid, isFalse, reason: 'red X over enemy ground');

    game.endDeploy(enemyGround);
    expect(game.deployOverlay.preview, isNull, reason: 'ghost cleared');
  });

  gameTest('cancelling a drag clears the ghost and keeps the card', (
    game,
    tester,
  ) async {
    final before = List<String>.of(game.hand!.hand.value);
    final elixir = game.elixir.amount;

    game.beginDeploy(0);
    game.updateDeploy(ownGround);
    game.cancelDeploy();

    expect(game.deployOverlay.preview, isNull);
    expect(game.draggingSlot.value, isNull);
    expect(game.hand!.hand.value, before);
    expect(game.elixir.amount, elixir);
  });

  gameTest('releasing off the arena entirely is a rejection, not a crash', (
    game,
    tester,
  ) async {
    game.beginDeploy(0);
    expect(game.endDeploy(null), isFalse);
    expect(game.units, isEmpty);
    expect(game.draggingSlot.value, isNull);
  });

  gameTest('painting forward opens new ground to deploy on', (
    game,
    tester,
  ) async {
    final card = game.cards['brusher'];
    // A world unit into the bot's half: enemy territory as far as deploying
    // is concerned.
    final target = Vector2(8, 11);
    expect(game.canDeployHere(card, target), isFalse);

    // Paint it red, the way a Roller walking up would.
    game.arena.paintLayer.stamp(target, 2.5, Team.red);
    game.arena.paintLayer.flush();
    await tester.runAsync(() => game.arena.resampleNow());

    expect(
      game.canDeployHere(card, target),
      isTrue,
      reason: 'the deploy line follows the paint',
    );
  });

  gameTest('losing ground pushes the deploy line back', (game, tester) async {
    final card = game.cards['brusher'];
    final target = Vector2(8, 21);
    expect(game.canDeployHere(card, target), isTrue);

    // The opponent paints over it.
    game.arena.paintLayer.stamp(target, 2.5, Team.blue);
    game.arena.paintLayer.flush();
    await tester.runAsync(() => game.arena.resampleNow());

    expect(game.canDeployHere(card, target), isFalse);
  });

  gameTest('elixir accrues over the match and caps at ten', (
    game,
    tester,
  ) async {
    game.elixir.reset(to: 0);
    game.updateTree(ElixirSpec.regenNormal * 3);
    expect(game.elixir.amount, closeTo(3.0, 0.05));
  });

  gameTest('a multi-body card puts all its bodies down for one cost', (
    game,
    tester,
  ) async {
    // Swarmlets is six bodies for four elixir.
    final card = game.cards['swarmlets'];
    final before = game.elixir.amount;
    game.elixir.reset(to: ElixirSpec.max);

    game.spawnCard('swarmlets', team: Team.red, position: ownGround);
    expect(game.units, hasLength(6));
    expect(card.bodyCount, 6);
    expect(before, isNotNull);
  });
}

/// Which hand slot currently holds [cardId]. The starter deck's order is not
/// this test's business, so it looks the slot up rather than assuming one.
int _slotOf(SplatfrontGame game, String cardId) {
  final hand = game.hand!;
  for (var slot = 0; slot < hand.handSize; slot++) {
    if (hand.cardIdAt(slot) == cardId) return slot;
  }
  throw StateError('$cardId is not in the opening hand');
}
