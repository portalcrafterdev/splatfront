import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/bot/bot_difficulty.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';
import 'package:splatfront/ui/widgets/match_header.dart';

/// The roster rules from CLAUDE.md section 17.
///
/// Every one of these exists because the reference game shipped without it
/// and its reviews say so. They are checks rather than review-time judgement
/// calls precisely because the failure mode is gradual: no single card breaks
/// a roster, but nobody notices the twelfth ground troop with no role.
void main() {
  late CardRegistry cards;
  late List<Deck> playerDecks;
  late BotConfig bots;
  late MatchRules rules;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    playerDecks = await Deck.loadStarterDecks();
    bots = await BotConfig.load();
    rules = await MatchRules.load();
  });

  group('rule 1: a third of the roster answers air', () {
    test('the floor is met with room to add a ground card', () {
      final roster = cards.playable.toList();
      final air = roster
          .where((c) => c.isUnit && c.unit!.targets.canHit(flying: true))
          .map((c) => c.id)
          .toList();

      // Their failure: about three cards in the whole set could target air,
      // so flyers had no answer and reviews called them overpowered.
      final floor = (roster.length / 3).ceil();
      expect(
        air.length,
        greaterThanOrEqualTo(floor),
        reason:
            'roster is ${roster.length}, so at least $floor cards must hit '
            'air; only ${air.length} do (${air.join(", ")})',
      );
    });

    test('anti-air is not all locked behind one cost or one class', () {
      final air = cards.playable
          .where((c) => c.isUnit && c.unit!.targets.canHit(flying: true))
          .toList();

      expect(
        air.where((c) => c.isTroop), isNotEmpty,
        reason: 'a deck without a building still has to answer a flyer',
      );
      expect(
        air.where((c) => c.isBuilding), isNotEmpty,
        reason: 'and a static answer has to exist too',
      );
      expect(
        air.map((c) => c.cost).toSet().length,
        greaterThan(1),
        reason: 'anti-air at a single price point is a tax, not a choice',
      );
    });

    test('every shipped deck can answer a flyer', () {
      // The roster-wide floor is worthless if a deck can still be built with
      // no answer in it at all.
      for (final deck in [
        ...playerDecks,
        ...bots.decksByArena.values,
      ]) {
        final air = deck.cardIds
            .map((id) => cards[id])
            .where((c) => c.isUnit && c.unit!.targets.canHit(flying: true));
        expect(
          air,
          isNotEmpty,
          reason: 'deck ${deck.cardIds} has nothing that can hit air',
        );
      }
    });
  });

  group('rule 2: no ground troop is only a cheap body', () {
    test('every ground troop has a role an air unit could not fill', () {
      // Roles that justify a ground card: it paints a lot, it soaks damage,
      // it arrives in numbers, it reaches, or it does something none of the
      // others do. A card that is none of these is the filler the reference
      // game is full of.
      final flyers = cards.playable
          .where((c) => c.isTroop && c.unit!.flying)
          .toList();
      final topAirPaint = flyers.isEmpty
          ? 0.0
          : flyers.map((c) => c.unit!.paint).reduce((a, b) => a > b ? a : b);
      final topAirHp = flyers.isEmpty
          ? 0.0
          : flyers.map((c) => c.unit!.hp).reduce((a, b) => a > b ? a : b);

      for (final card in cards.playable.where((c) => c.isTroop)) {
        final u = card.unit!;
        if (u.flying) continue;

        final paints = u.paint > topAirPaint;
        final tanks = u.hp > topAirHp;
        final swarms = u.count > 1;
        final reaches = u.range > cards.units.tuning.meleeRange;
        final special =
            u.splashRadius > 0 || u.auraRadius > 0 || u.targets.canHit(flying: true);

        expect(
          paints || tanks || swarms || reaches || special,
          isTrue,
          reason:
              '${card.id} is a ground body with no role: paint ${u.paint}, '
              'hp ${u.hp}, count ${u.count}, range ${u.range}. Give it one '
              'or cut it.',
        );
      }
    });
  });

  group('rule 3: live buildings are capped', () {
    test('the cap is set, and set low', () {
      expect(rules.maxLiveBuildings, greaterThan(0));
      expect(
        rules.maxLiveBuildings,
        lessThanOrEqualTo(3),
        reason: 'section 17 says two to three; more is the turret spam',
      );
    });

    test('every building still expires on its own clock', () {
      // The cap and the timer answer different halves of the problem.
      for (final card in cards.buildings) {
        expect(
          card.unit!.isTemporary,
          isTrue,
          reason: '${card.id} would stand forever',
        );
      }
    });

    testWidgets('the deploy is refused once the cap is reached', (
      tester,
    ) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        economy: rules,
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      // The deploy map is all-neutral until a real readback has run, and with
      // the own-colour rule back on that would refuse every drop.
      await tester.runAsync(() => game.arena.resampleNow());

      final spot = Vector2(8, 20);
      final card = cards['turret'];
      expect(game.canDeployFor(Team.red, card, spot), isTrue);

      for (var i = 0; i < rules.maxLiveBuildings; i++) {
        game.spawnCard('turret', team: Team.red, position: Vector2(4.0 + i, 20));
      }
      game.updateTree(0);

      expect(game.buildingsStandingFor(Team.red), rules.maxLiveBuildings);
      expect(game.atBuildingCap(Team.red), isTrue);
      expect(
        game.canDeployFor(Team.red, card, spot),
        isFalse,
        reason: 'the cap rejects the drop before it costs elixir',
      );

      // The other side is unaffected: the cap is per side, not per board.
      expect(game.atBuildingCap(Team.blue), isFalse);
      expect(game.canDeployFor(Team.blue, card, Vector2(8, 4)), isTrue);

      // A troop is still fine — the cap is on buildings only.
      expect(
        game.canDeployFor(Team.red, cards['brusher'], spot),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('the first match is a fair fight', () {
    // The deck a player is handed and the deck the arena 1 bot brings have to
    // be the same shape, because a card advantage does not read as one from
    // the player's side — it reads as "the AI is stronger than me", which is
    // exactly how it was reported.
    //
    // Measured before this was fixed: the bot deck ran Dab where the player
    // ran Paint Bomb, three extra bodies for one less elixir. With the same
    // brain driving both sides, that deck alone took the match 17 times in 20
    // at Hard, and the player held 29% of the board. Matching the shapes put
    // it back to 48%.
    int bodiesIn(Deck deck) =>
        deck.cardIds.map((id) => cards[id].bodyCount).reduce((a, b) => a + b);
    int costOf(Deck deck) =>
        deck.cardIds.map((id) => cards[id].cost).reduce((a, b) => a + b);

    test('the starter deck and the first bot deck put out the same', () {
      final player = playerDecks.first;
      final bot = bots.deckFor('arena_1');

      expect(
        bodiesIn(bot),
        closeTo(bodiesIn(player), 1),
        reason:
            'bot fields ${bodiesIn(bot)} bodies against the player '
            '${bodiesIn(player)}',
      );
      expect(
        costOf(bot),
        closeTo(costOf(player), 2),
        reason:
            'bot deck costs ${costOf(bot)} against the player '
            '${costOf(player)}, so it cycles faster for free',
      );
    });

    test('both first decks carry a building and a spell', () {
      for (final deck in [playerDecks.first, bots.deckFor('arena_1')]) {
        final kinds = deck.cardIds.map((id) => cards[id]);
        expect(
          kinds.where((c) => c.isBuilding),
          isNotEmpty,
          reason: 'one side having the only building is a card advantage',
        );
        expect(kinds.where((c) => c.isSpell), isNotEmpty);
      }
    });
  });

  group('which side you play', () {
    test('the player is blue and the bot is red', () {
      // Every other test passes a team explicitly, which is what keeps the
      // code symmetric — and also means none of them would notice if the
      // shipped default flipped back.
      final game = SplatfrontGame(layout: ArenaLayout.fallback, cards: cards);
      expect(game.playerTeam, Team.blue);
      expect(game.playerTeam.opponent, Team.red);
      expect(
        game.player.team,
        Team.blue,
        reason: 'the side that owns your hand is the side you play',
      );
      expect(game.opponent.team, Team.red);
    });
  });

  group('rule 6: single player, and honest about it', () {
    test('every opponent plate says it is a bot', () {
      // Not a naming preference. "Novice" and "Veteran" alone read as the
      // handles of real people, and implying an opponent who is not there is
      // the thing the reference game's reviews punish — not the absence of
      // multiplayer, which nobody minded.
      for (final tier in BotTier.values) {
        expect(
          tier.opponentName.toLowerCase(),
          contains('bot'),
          reason: 'the ${tier.name} plate hides that it is a bot',
        );
      }
    });
  });

  group('rules 4 and 5: format and deploy', () {
    test('the deck is six cards', () {
      expect(Deck.size, 6);
      for (final deck in [...playerDecks, ...bots.decksByArena.values]) {
        expect(deck.cardIds, hasLength(6));
      }
    });

    test('a card may only be deployed on ground its own side holds', () {
      // Section 17 rule 5, in full. Both halves of it now stand: paint is
      // persistent, and a body lands only on ground its side already holds.
      // The flag was flipped to anywhere=true for a session and flipped back,
      // which is why this asserts the value rather than trusting the default.
      expect(rules.deployAnywhere, isFalse);
      expect(
        rules.deployClaimRadius,
        greaterThan(0),
        reason: 'kept so flipping the one flag restores that rule whole',
      );
    });
  });
}
