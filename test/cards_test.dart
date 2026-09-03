import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/game/cards/card_model.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/cards/elixir_bar.dart';
import 'package:splatfront/game/cards/hand_controller.dart';

void main() {
  late CardRegistry cards;
  late List<Deck> decks;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    decks = await Deck.loadStarterDecks();
  });

  group('card registry', () {
    test('holds the whole set: troops, buildings and spells', () {
      expect(cards.all, hasLength(21));
      expect(cards.troops, hasLength(12));
      expect(cards.buildings, hasLength(5));
      expect(cards.spells, hasLength(4));
      // A building is a unit with a body, not a third thing the rest of the
      // game has to special-case.
      for (final card in cards.buildings) {
        expect(card.isUnit, isTrue);
        expect(card.unit, isNotNull);
        expect(card.obeysDeployZone, isTrue);
      }
    });

    test('spell stats survive the round trip', () {
      final bomb = cards['paint_bomb'];
      expect(bomb.isSpell, isTrue);
      expect(bomb.cost, 3);
      expect(bomb.spell!.effect, SpellEffect.damageAndPaint);
      expect(bomb.spell!.radius, 3.5);
      expect(bomb.spell!.damage, 150);
      expect(bomb.spell!.paints, isTrue);

      final solvent = cards['solvent'];
      expect(solvent.spell!.effect, SpellEffect.wipeToNeutral);
      expect(solvent.spell!.damage, 0);
      expect(
        solvent.spell!.paints,
        isTrue,
        reason: 'wiping to neutral is still a repaint',
      );

      final freeze = cards['freeze'];
      expect(freeze.spell!.effect, SpellEffect.stun);
      expect(freeze.spell!.duration, 2.5);
      expect(freeze.spell!.paints, isFalse, reason: 'Freeze does not paint');

      final surge = cards['surge'];
      expect(surge.spell!.friendlyOnly, isTrue);
      expect(surge.spell!.speedMultiplier, 1.5);
    });

    test('spells ignore the deploy zone, troops obey it', () {
      expect(cards['paint_bomb'].obeysDeployZone, isFalse);
      expect(cards['brusher'].obeysDeployZone, isTrue);
    });

    test('levelling a card raises its stats but never its cost', () {
      final base = cards['brusher'];
      final maxed = cards.at('brusher', 9);
      expect(maxed.cost, base.cost);
      expect(maxed.unit!.hp, greaterThan(base.unit!.hp));
      expect(maxed.level, 9);
    });

    test('an unknown card fails loudly', () {
      expect(() => cards['nope'], throwsArgumentError);
    });
  });

  group('deck', () {
    test('the starter decks are legal and playable', () {
      expect(decks, isNotEmpty);
      for (final deck in decks) {
        expect(deck.cardIds, hasLength(Deck.size));
        deck.validateAgainst(cards);
      }
    });

    test('a deck must hold exactly six cards', () {
      expect(() => Deck(const ['dab', 'roller']), throwsArgumentError);
    });

    test('a deck may not repeat a card', () {
      expect(
        () => Deck(const ['dab', 'dab', 'roller', 'brusher', 'pin', 'sprayer']),
        throwsArgumentError,
      );
    });

    test('every card in the set is deck-legal', () {
      // Twelve troops, five buildings, four spells.
      expect(cards.playable, hasLength(21));
    });

    test('a deck naming a card that does not exist is rejected up front', () {
      final deck = Deck(const [
        'dab',
        'roller',
        'brusher',
        'pin',
        'sprayer',
        'not_a_real_card',
      ]);
      expect(() => deck.validateAgainst(cards), throwsArgumentError);
    });
  });

  group('hand rotation', () {
    late HandController hand;

    setUp(() {
      hand = HandController(deck: decks.first, levels: const CardLevels());
    });

    test('the hand is the first four and the preview is the fifth', () {
      expect(hand.hand.value, decks.first.cardIds.take(4));
      expect(hand.next.value, decks.first.cardIds[4]);
    });

    test('playing a card sends it to the back and slides the preview in', () {
      final deck = decks.first.cardIds;

      final played = hand.play(0);

      expect(played, deck[0]);
      expect(
        hand.hand.value[0],
        deck[4],
        reason: 'the preview filled the slot it vacated',
      );
      expect(hand.next.value, deck[5]);
      expect(hand.queue.last, played, reason: 'and it went to the back');
    });

    test('playing from the middle only moves that slot', () {
      final before = List<String>.of(hand.hand.value);
      hand.play(2);

      expect(hand.hand.value[0], before[0]);
      expect(hand.hand.value[1], before[1]);
      expect(hand.hand.value[2], isNot(before[2]));
      expect(hand.hand.value[3], before[3]);
    });

    test('a full pass plays every card in the deck exactly once', () {
      // The old claim here was that Deck.size plays return the hand to its
      // starting order. That held only because eight cards divided evenly
      // into four slots; at six they do not, and the hand comes back rotated.
      // What is true at any deck size is that a round-robin pass of
      // Deck.size plays spends the whole deck and repeats nothing — which is
      // the property the rotation exists to guarantee.
      final played = <String>[];
      for (var i = 0; i < Deck.size; i++) {
        played.add(hand.play(i % ElixirSpec.handSize)!);
      }

      expect(played, hasLength(Deck.size));
      expect(
        played.toSet(),
        decks.first.cardIds.toSet(),
        reason: 'every card came up, and none came up twice',
      );
    });

    test('the rotation does come back round, in its own time', () {
      final start = List<String>.of(hand.hand.value);
      var plays = 0;
      while (plays < 200) {
        hand.play(plays % ElixirSpec.handSize);
        plays++;
        if (_sameOrder(hand.hand.value, start) &&
            _sameOrder(hand.queue, decks.first.cardIds)) {
          break;
        }
      }
      expect(
        plays,
        lessThan(200),
        reason: 'a rotation that never repeats has lost or gained a card',
      );
    });

    test('playing one slot repeatedly never disturbs the others', () {
      final before = List<String>.of(hand.hand.value);
      for (var i = 0; i < 5; i++) {
        hand.play(1);
      }
      expect(hand.hand.value[0], before[0]);
      expect(hand.hand.value[2], before[2]);
      expect(hand.hand.value[3], before[3]);
    });

    test('the rotation never loses or duplicates a card', () {
      for (var i = 0; i < 50; i++) {
        hand.play(i % ElixirSpec.handSize);
        expect(hand.queue.toSet(), hasLength(Deck.size));
      }
    });

    test('an out-of-range slot changes nothing', () {
      final before = List<String>.of(hand.queue);
      expect(hand.play(9), isNull);
      expect(hand.play(-1), isNull);
      expect(hand.queue, before);
    });

    test('reset puts the deck back in its starting order', () {
      hand.play(0);
      hand.play(1);
      hand.reset();
      expect(hand.queue, decks.first.cardIds);
    });
  });

  group('elixir', () {
    test('starts at five and caps at ten', () {
      final elixir = ElixirBar();
      expect(elixir.amount, ElixirSpec.start);

      elixir.update(1000);
      expect(elixir.amount, ElixirSpec.max);
    });

    test('regenerates one per two seconds in normal time', () {
      final elixir = ElixirBar(start: 0);
      elixir.update(ElixirSpec.regenNormal);
      expect(elixir.amount, closeTo(1.0, 1e-9));
    });

    test('sudden death doubles the rate and nothing else', () {
      final elixir = ElixirBar(start: 0)..suddenDeath = true;
      elixir.update(ElixirSpec.regenSuddenDeath);
      expect(elixir.amount, closeTo(1.0, 1e-9));
      expect(elixir.secondsPerElixir, ElixirSpec.regenSuddenDeath);
    });

    test('does not accrue while stopped, for the countdown', () {
      final elixir = ElixirBar(start: 5)..running = false;
      elixir.update(10);
      expect(elixir.amount, 5);
    });

    test('spending takes the cost, and never goes negative', () {
      final elixir = ElixirBar(start: 5);

      expect(elixir.spend(3), isTrue);
      expect(elixir.amount, 2);

      expect(elixir.spend(5), isFalse, reason: 'cannot afford it');
      expect(elixir.amount, 2, reason: 'and nothing was taken');
    });

    test('the bar reports whole segments and a partial fill', () {
      final elixir = ElixirBar(start: 0);
      elixir.update(ElixirSpec.regenNormal * 2.5);

      expect(elixir.filledSegments, 2);
      expect(elixir.partialFill, closeTo(0.5, 1e-6));
    });
  });
}

/// Same cards in the same order.
bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
