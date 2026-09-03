import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_model.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/spells/spell.dart';
import 'package:splatfront/game/splatfront_game.dart';

void main() {
  late CardRegistry cards;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
  });

  void gameTest(
    String description,
    Future<void> Function(SplatfrontGame game, WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
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

  void tick(SplatfrontGame game, double seconds) {
    const step = 1 / 60;
    for (var elapsed = 0.0; elapsed < seconds; elapsed += step) {
      game.updateTree(step);
    }
  }

  test('every known spell effect has an implementation', () {
    for (final effect in SpellEffect.values) {
      if (effect == SpellEffect.unknown) continue;
      expect(
        spellsByEffect[effect],
        isNotNull,
        reason: '$effect has no Spell behind it',
      );
    }
    // And every spell in the data resolves to a known effect.
    for (final card in cards.spells) {
      expect(card.spell!.effect, isNot(SpellEffect.unknown), reason: card.id);
    }
  });

  group('Paint Bomb', () {
    gameTest('damages enemies and recolours the ground', (game, tester) async {
      final victim = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 6),
      );
      game.arena.paintLayer.flush();

      game.castSpell(cards['paint_bomb'], Team.red, Vector2(8, 6));

      expect(victim.hp, lessThan(victim.stats.hp));
      expect(
        game.arena.paintLayer.hasPendingStamps,
        isTrue,
        reason: 'it repaints where it lands',
      );
    });

    gameTest('spares the caster\'s own units', (game, tester) async {
      final friendly = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 6),
      );

      game.castSpell(cards['paint_bomb'], Team.red, Vector2(8, 6));

      expect(friendly.hp, friendly.stats.hp);
    });

    gameTest('only reaches inside its radius', (game, tester) async {
      final inside = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 6),
      );
      final outside = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 14),
      );

      game.castSpell(cards['paint_bomb'], Team.red, Vector2(8, 6));

      expect(inside.hp, lessThan(inside.stats.hp));
      expect(outside.hp, outside.stats.hp);
    });

    gameTest('opens ground the player could not otherwise deploy on', (
      game,
      tester,
    ) async {
      final troop = cards['brusher'];
      final target = Vector2(8, 6); // deep in blue paint
      expect(game.canDeployFor(Team.red, troop, target), isFalse);

      game.castSpell(cards['paint_bomb'], Team.red, target);
      game.arena.paintLayer.flush();
      await tester.runAsync(() => game.arena.resampleNow());

      expect(
        game.canDeployFor(Team.red, troop, target),
        isTrue,
        reason: 'that is the whole point of the card',
      );
    });
  });

  group('Freeze', () {
    gameTest('stuns enemies without damaging them', (game, tester) async {
      final victim = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 6),
      );

      game.castSpell(cards['freeze'], Team.red, Vector2(8, 6));

      expect(victim.isStunned, isTrue);
      expect(victim.hp, victim.stats.hp, reason: 'Freeze does no damage');
    });

    gameTest('a frozen unit stops moving, then starts again', (
      game,
      tester,
    ) async {
      final victim = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 6),
      );
      game.castSpell(cards['freeze'], Team.red, Vector2(8, 6));

      final frozenAt = victim.position.clone();
      tick(game, 1.0);
      expect(victim.position, frozenAt, reason: 'it did not budge');

      // 2.5 seconds of stun, so it is loose after that.
      tick(game, 2.0);
      expect(victim.isStunned, isFalse);
      tick(game, 0.5);
      expect(victim.position, isNot(frozenAt));
    });

    gameTest('a frozen unit does not paint', (game, tester) async {
      game.spawnUnit('roller', team: Team.blue, position: Vector2(8, 6));
      game.castSpell(cards['freeze'], Team.red, Vector2(8, 6));
      game.arena.paintLayer.flush();

      tick(game, 1.0);
      expect(game.arena.paintLayer.hasPendingStamps, isFalse);
    });

    gameTest('a frozen unit does not swing', (game, tester) async {
      game.spawnUnit('brusher', team: Team.blue, position: Vector2(8, 6));
      final enemy = game.spawnUnit(
        'bucket_bot',
        team: Team.red,
        position: Vector2(8, 6.5),
      );
      game.castSpell(cards['freeze'], Team.red, Vector2(8, 6));

      final before = enemy.hp;
      tick(game, 1.0);
      expect(enemy.hp, before);
    });

    gameTest('freezing again extends rather than shortens', (
      game,
      tester,
    ) async {
      final victim = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 6),
      );

      game.castSpell(cards['freeze'], Team.red, Vector2(8, 6));
      tick(game, 2.0);
      // A second Freeze with most of the first still to run.
      game.castSpell(cards['freeze'], Team.red, Vector2(8, 6));
      tick(game, 1.0);

      expect(victim.isStunned, isTrue);
    });
  });

  group('Solvent', () {
    gameTest('wipes to neutral and damages nobody', (game, tester) async {
      final friendly = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 20),
      );
      final enemy = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 20),
      );

      game.castSpell(cards['solvent'], Team.red, Vector2(8, 20));
      game.arena.paintLayer.flush();
      await tester.runAsync(() => game.arena.resampleNow());

      expect(friendly.hp, friendly.stats.hp);
      expect(enemy.hp, enemy.stats.hp);
      expect(
        game.arena.deployZone.ownerAt(Vector2(8, 20)),
        Team.neutral,
        reason: 'the ground belongs to nobody now',
      );
    });

    gameTest('denies the ground to both sides, the caster included', (
      game,
      tester,
    ) async {
      final troop = cards['brusher'];
      final target = Vector2(8, 20);
      expect(game.canDeployFor(Team.red, troop, target), isTrue);

      game.castSpell(cards['solvent'], Team.red, target);
      game.arena.paintLayer.flush();
      await tester.runAsync(() => game.arena.resampleNow());

      expect(game.canDeployFor(Team.red, troop, target), isFalse);
      expect(game.canDeployFor(Team.blue, troop, target), isFalse);
    });
  });

  group('Surge', () {
    gameTest('speeds up friendly units only', (game, tester) async {
      final friendly = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 20),
      );
      final enemy = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 20),
      );

      game.castSpell(cards['surge'], Team.red, Vector2(8, 20));

      expect(friendly.isBuffed, isTrue);
      expect(enemy.isBuffed, isFalse);
      expect(friendly.effectiveSpeed, greaterThan(friendly.stats.speed));
      expect(enemy.effectiveSpeed, enemy.stats.speed);
    });

    gameTest('a surged unit paints more often', (game, tester) async {
      final unit = game.spawnUnit(
        'roller',
        team: Team.red,
        position: Vector2(8, 20),
      );
      final normalTick = unit.effectiveStampTick;

      game.castSpell(cards['surge'], Team.red, Vector2(8, 20));
      expect(unit.effectiveStampTick, lessThan(normalTick));
    });

    gameTest('the buff wears off after its duration', (game, tester) async {
      final unit = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 20),
      );
      game.castSpell(cards['surge'], Team.red, Vector2(8, 20));
      expect(unit.isBuffed, isTrue);

      // Five seconds of Surge.
      tick(game, 5.2);
      expect(unit.isBuffed, isFalse);
      expect(unit.effectiveSpeed, unit.stats.speed);
    });
  });

  group('Nozzle splash', () {
    gameTest('one shot hits everything near the target', (game, tester) async {
      final primary = game.spawnUnit(
        'dab',
        team: Team.blue,
        position: Vector2(8, 12),
      );
      final beside = game.spawnUnit(
        'dab',
        team: Team.blue,
        position: Vector2(8.8, 12),
      );
      final away = game.spawnUnit(
        'dab',
        team: Team.blue,
        position: Vector2(14, 12),
      );

      final nozzle = game.spawnUnit(
        'nozzle',
        team: Team.red,
        position: Vector2(8, 15),
      );
      nozzle.dealDamage(primary);

      expect(primary.hp, lessThan(primary.stats.hp));
      expect(beside.hp, lessThan(beside.stats.hp), reason: 'caught in splash');
      expect(away.hp, away.stats.hp, reason: 'well outside the blast');
    });

    gameTest('splash never touches its own side', (game, tester) async {
      final enemy = game.spawnUnit(
        'dab',
        team: Team.blue,
        position: Vector2(8, 12),
      );
      final friendly = game.spawnUnit(
        'dab',
        team: Team.red,
        position: Vector2(8.5, 12),
      );

      final nozzle = game.spawnUnit(
        'nozzle',
        team: Team.red,
        position: Vector2(8, 15),
      );
      nozzle.dealDamage(enemy);

      expect(enemy.hp, lessThan(enemy.stats.hp));
      expect(friendly.hp, friendly.stats.hp);
    });

    gameTest('splash deletes a swarm in one shot', (game, tester) async {
      // Swarmlets are 60 hp each; Nozzle hits for 80.
      final swarm = game.spawnCard(
        'swarmlets',
        team: Team.blue,
        position: Vector2(8, 12),
      );
      final nozzle = game.spawnUnit(
        'nozzle',
        team: Team.red,
        position: Vector2(8, 15),
      );

      nozzle.dealDamage(swarm.first);
      expect(swarm.where((u) => u.isAlive), isEmpty);
    });
  });

  group('Warden aura', () {
    gameTest('friendly units nearby take 25% less damage', (
      game,
      tester,
    ) async {
      final protectedUnit = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 20),
      );
      game.spawnUnit('warden', team: Team.red, position: Vector2(8, 21));

      expect(protectedUnit.auraReduction(), 0.25);
      protectedUnit.takeDamage(100);
      expect(protectedUnit.hp, closeTo(protectedUnit.stats.hp - 75, 0.001));
    });

    gameTest('the aura does not reach past its radius', (game, tester) async {
      final far = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 20),
      );
      // Warden's aura is 3.0; put it well outside.
      game.spawnUnit('warden', team: Team.red, position: Vector2(8, 14));

      expect(far.auraReduction(), 0);
      far.takeDamage(100);
      expect(far.hp, closeTo(far.stats.hp - 100, 0.001));
    });

    gameTest('the aura never protects the enemy', (game, tester) async {
      final enemy = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 20),
      );
      game.spawnUnit('warden', team: Team.red, position: Vector2(8, 20.5));

      expect(enemy.auraReduction(), 0);
    });

    gameTest('the aura covers spell damage too', (game, tester) async {
      final protectedUnit = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 6),
      );
      game.spawnUnit('warden', team: Team.blue, position: Vector2(8, 6.5));

      game.castSpell(cards['paint_bomb'], Team.red, Vector2(8, 6));

      // 150 damage reduced by a quarter.
      expect(protectedUnit.hp, closeTo(protectedUnit.stats.hp - 112.5, 0.001));
    });

    gameTest('a dead Warden protects nobody', (game, tester) async {
      final ally = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 20),
      );
      final warden = game.spawnUnit(
        'warden',
        team: Team.red,
        position: Vector2(8, 21),
      );
      expect(ally.auraReduction(), 0.25);

      warden.takeDamage(99999);
      expect(ally.auraReduction(), 0, reason: 'the aura died with it');
    });
  });

  group('spells through the hand', () {
    testWidgets('playing a spell spends elixir and lands the effect', (
      tester,
    ) async {
      final deck = Deck(const [
        'paint_bomb',
        'dab',
        'roller',
        'brusher',
        'pin',
        'sprayer',
      ]);
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        deck: deck,
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() => game.arena.resampleNow());

      final victim = game.spawnUnit(
        'brusher',
        team: Team.blue,
        position: Vector2(8, 4),
      );
      final elixirBefore = game.elixir.amount;

      // Straight into enemy ground, which a troop could never do.
      final played = game.playFromHand(game.player, 0, Vector2(8, 4));

      expect(played, isTrue);
      expect(game.elixir.amount, closeTo(elixirBefore - 3, 1e-9));
      expect(victim.hp, lessThan(victim.stats.hp));
      expect(
        game.hand!.hand.value[0],
        isNot('paint_bomb'),
        reason: 'it rotated out',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  gameTest('a spell leaves a burst where it landed', (game, tester) async {
    final before = game.world.children.length;
    game.castSpell(cards['paint_bomb'], Team.red, Vector2(8, 12));
    game.updateTree(0);
    expect(game.world.children.length, greaterThan(before));
  });

  gameTest('a burst cleans itself up', (game, tester) async {
    game.castSpell(cards['paint_bomb'], Team.red, Vector2(8, 12));
    game.updateTree(0);
    final withBurst = game.world.children.length;

    tick(game, 1.0);
    game.updateTree(0);
    expect(game.world.children.length, lessThan(withBurst));
  });

  gameTest('a stunned unit is skipped by nothing else in the loop', (
    game,
    tester,
  ) async {
    // A stun should not break targeting for anyone else.
    final frozen = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 12),
    );
    final attacker = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 12.5),
    );
    game.castSpell(cards['freeze'], Team.red, Vector2(8, 12));

    tick(game, 1.0);
    expect(attacker.target, same(frozen), reason: 'still a valid target');
    expect(frozen.hp, lessThan(frozen.stats.hp), reason: 'and still hittable');
  });

  test('the card table still matches section 6 after the balance pass', () {
    // Phase 6 says "balance pass on JSON". Nothing has been retuned without
    // playtest evidence, so these must still be the spec's numbers.
    expect(cards['paint_bomb'].cost, 3);
    expect(cards['paint_bomb'].spell!.radius, 3.5);
    expect(cards['paint_bomb'].spell!.damage, 150);

    expect(cards['freeze'].cost, 3);
    expect(cards['freeze'].spell!.duration, 2.5);
    expect(cards['freeze'].spell!.radius, 3.0);

    expect(cards['solvent'].cost, 2);
    expect(cards['solvent'].spell!.radius, 3.0);

    expect(cards['surge'].cost, 4);
    expect(cards['surge'].spell!.duration, 5.0);
    expect(cards['surge'].spell!.radius, 4.0);
    expect(cards['surge'].spell!.speedMultiplier, 1.5);
    expect(cards['surge'].spell!.paintRateMultiplier, 1.5);
  });
}
