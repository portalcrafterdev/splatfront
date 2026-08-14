import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/splatfront_game.dart';

void main() {
  late CardRegistry cards;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
  });

  /// Boots a game inside a real GameWidget and hands it to [body].
  ///
  /// The default layout has no blockers, so steering never confounds a
  /// movement assertion. [layout] is a callback because the arena data is not
  /// loaded yet when these are declared.
  void gameTest(
    String description,
    Future<void> Function(SplatfrontGame game) body, {
    ArenaLayout Function()? layout,
  }) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: layout?.call() ?? ArenaLayout.fallback,
        cards: cards,
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      try {
        await body(game);
      } finally {
        // A mounted GameWidget keeps a ticker alive, and a live ticker leaking
        // out of one test wedges every test after it.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  /// Runs the game forward in 60fps steps.
  ///
  /// `updateTree`, not `update`: only the tree walk descends into children.
  void tick(SplatfrontGame game, {double seconds = 1.0}) {
    const step = 1 / 60;
    for (var elapsed = 0.0; elapsed < seconds; elapsed += step) {
      game.updateTree(step);
    }
  }

  gameTest('a spawned unit joins the roster and leaves when removed', (
    game,
  ) async {
    final unit = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 20),
    );
    expect(game.units, contains(unit), reason: 'targetable immediately');
    expect(game.units, hasLength(1));

    unit.removeFromParent();
    expect(game.units, isEmpty);
  });

  gameTest(
    'with nothing to fight, a unit walks up its lane to the enemy base',
    (game) async {
      final unit = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(4, 20),
      );

      final startY = unit.position.y;
      tick(game, seconds: 2);

      // Red starts at the bottom, so its enemy base is at the top.
      expect(unit.position.y, lessThan(startY));
      expect(unit.position.x, closeTo(4, 0.2), reason: 'it holds its lane');
    },
  );

  /// Runs a unit to a standstill with the owner grid kept up to date.
  ///
  /// The advance leash is measured off the paint, so a harness that never
  /// samples the paint tests the fallback path rather than the real one.
  Future<double> restingY(
    WidgetTester tester,
    String id, {
    required double dropY,
  }) async {
    final game = SplatfrontGame(
      layout: ArenaLayout.fallback,
      cards: cards,
      playerTeam: Team.red,
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.runAsync(() => game.arena.resampleNow());

    final unit = game.spawnUnit(id, team: Team.red, position: Vector2(8, dropY));

    // Twenty seconds, resampling twice a second the way the real match does.
    for (var i = 0; i < 40; i++) {
      for (var f = 0; f < 30; f++) {
        game.updateTree(1 / 60);
      }
      game.arena.paintLayer.flush();
      await tester.runAsync(() => game.arena.resampleNow());
    }

    final y = unit.position.y;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    return y;
  }

  testWidgets('a unit walks the board until it runs out of ground', (
    tester,
  ) async {
    // advanceRange is set to the full height of the arena, so the leash never
    // binds: the owner asked for units that go all the way rather than
    // halting partway up. Lower advanceRange in cards.json and they hold a
    // post again — the mechanism is still there, the number is what changed.
    final y = await restingY(tester, 'brusher', dropY: 22);
    expect(
      y,
      lessThan(2),
      reason: 'it should have crossed the whole arena, and stopped at $y',
    );
    expect(
      y,
      greaterThanOrEqualTo(0),
      reason: 'but never off the board',
    );
  });

  testWidgets('where a card is dropped does not decide how far it gets', (
    tester,
  ) async {
    // The leash is measured from the frontier, not from the drop point.
    // Charging the walk across your own paint against it meant a card played
    // in the middle of your own half ran out of advance exactly on the
    // halfway line and stood there — and with deploy-on-your-own-colour back
    // on, the middle of your own half is where a card gets played.
    final fromBack = await restingY(tester, 'brusher', dropY: 22);
    final fromMiddle = await restingY(tester, 'brusher', dropY: 18);
    final fromEdge = await restingY(tester, 'brusher', dropY: 13);

    final mid = ArenaSpec.worldHeight / 2;
    for (final entry in {22.0: fromBack, 18.0: fromMiddle, 13.0: fromEdge}
        .entries) {
      expect(
        entry.value,
        lessThan(mid - 1.0),
        reason: 'dropped at ${entry.key} it stopped at ${entry.value}, which '
            'is not a push into enemy ground',
      );
    }

    // All three end up at much the same depth: the drop point buys reach, not
    // the lack of it.
    final deepest = [fromBack, fromMiddle, fromEdge].reduce(math.min);
    final shallowest = [fromBack, fromMiddle, fromEdge].reduce(math.max);
    expect(
      shallowest - deepest,
      lessThan(3.0),
      reason: 'the three drops finished ${shallowest - deepest} apart',
    );
  });

  gameTest('the two sides walk in opposite directions', (game) async {
    final red = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(2, 20),
    );
    final blue = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(14, 4),
    );

    final redStart = red.position.y;
    final blueStart = blue.position.y;
    tick(game, seconds: 1);

    expect(red.position.y, lessThan(redStart));
    expect(blue.position.y, greaterThan(blueStart));
  });

  gameTest('a unit closes on an enemy and kills it', (game) async {
    final attacker = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 14),
    );
    final victim = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 12),
    );

    tick(game, seconds: 1);
    expect(attacker.target, same(victim), reason: 'it acquired the enemy');
    expect(victim.hp, lessThan(victim.stats.hp), reason: 'and started hitting');

    // 340 hp against 70 damage a second is five swings.
    tick(game, seconds: 6);
    expect(victim.isAlive, isFalse);
  });

  gameTest('a dead unit is removed after the death fade', (game) async {
    final victim = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 12),
    );

    victim.takeDamage(9999);
    expect(victim.isDying, isTrue);
    expect(victim.isAlive, isFalse);
    expect(game.units, hasLength(1), reason: 'it lingers while it fades');

    tick(game, seconds: Timings.deathFadeOut + 0.1);
    expect(game.units, isEmpty);
  });

  gameTest('a death leaves a splash, so trades still move the score', (
    game,
  ) async {
    final victim = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 12),
    );
    game.arena.paintLayer.flush(); // drain anything already queued

    victim.takeDamage(9999);
    expect(game.arena.paintLayer.hasPendingStamps, isTrue);
  });

  gameTest('a dying unit stops fighting', (game) async {
    final victim = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 12),
    );
    final enemy = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 12.5),
    );

    victim.takeDamage(9999);
    final hpBefore = enemy.hp;

    tick(game, seconds: 0.3);
    expect(enemy.hp, hpBefore, reason: 'the corpse got no swings in');
    expect(victim.target, isNull);
  });

  gameTest('a walking unit paints a trail behind it', (game) async {
    final roller = game.spawnUnit(
      'roller',
      team: Team.red,
      position: Vector2(8, 20),
    );

    var stampTicks = 0;
    for (var i = 0; i < 120; i++) {
      game.updateTree(1 / 60);
      if (game.arena.paintLayer.hasPendingStamps) {
        stampTicks++;
        game.arena.paintLayer.flush();
      }
    }

    // Two seconds at the 10 Hz stamp tick is about twenty stamps.
    expect(stampTicks, greaterThanOrEqualTo(15));
    expect(roller.position.y, lessThan(20), reason: 'it was moving');
  });

  gameTest('Roller walks straight past an enemy it could have chased', (
    game,
  ) async {
    final roller = game.spawnUnit(
      'roller',
      team: Team.red,
      position: Vector2(8, 20),
    );
    // An enemy off the lane but well inside a normal melee aggro range.
    // It has to be another Roller: a Brusher would charge over and end up in
    // the Roller's reach, which proves nothing about who diverted.
    final enemy = game.spawnUnit(
      'roller',
      team: Team.blue,
      position: Vector2(10.5, 20),
    );

    tick(game, seconds: 1);

    expect(roller.target, isNull, reason: 'aggroRange 0 means never divert');
    expect(enemy.target, isNull);
    expect(roller.position.x, closeTo(8, 0.35), reason: 'it held its lane');
    expect(enemy.position.x, closeTo(10.5, 0.35));
  });

  gameTest('Brusher does divert to chase, so the contrast holds', (game) async {
    final brusher = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 20),
    );
    game.spawnUnit('brusher', team: Team.blue, position: Vector2(10.5, 20));

    tick(game, seconds: 1);
    expect(brusher.target, isNotNull);
    expect(brusher.position.x, greaterThan(8.3));
  });

  gameTest('a ranged unit fires from its range without closing', (game) async {
    final sprayer = game.spawnUnit(
      'sprayer',
      team: Team.red,
      position: Vector2(8, 16),
    );
    final victim = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 12),
    );

    tick(game, seconds: 1);

    // Sprayer reaches 5.0 and the two started 4.0 apart, so it should already
    // be shooting without having taken a step forward.
    expect(sprayer.target, same(victim));
    expect(victim.hp, lessThan(victim.stats.hp));
    expect(sprayer.position.y, closeTo(16, 0.05));
  });

  gameTest('Sprayer paints the ground it is holding while it shoots', (
    game,
  ) async {
    game.spawnUnit('sprayer', team: Team.red, position: Vector2(8, 16));
    game.spawnUnit('brusher', team: Team.blue, position: Vector2(8, 12));
    game.arena.paintLayer.flush();

    var stamps = 0;
    for (var i = 0; i < 120; i++) {
      game.updateTree(1 / 60);
      if (game.arena.paintLayer.hasPendingStamps) {
        stamps++;
        game.arena.paintLayer.flush();
      }
    }
    expect(stamps, greaterThan(0), reason: 'a standing Sprayer still paints');
  });

  gameTest('allies push apart instead of stacking', (game) async {
    final a = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 20),
    );
    final b = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8.05, 20),
    );

    tick(game, seconds: 1);

    expect(
      a.position.distanceTo(b.position),
      greaterThan(0.3),
      reason: 'separation loosened the clump',
    );
  });

  gameTest('a unit never targets its own side', (game) async {
    final a = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 20),
    );
    game.spawnUnit('brusher', team: Team.red, position: Vector2(9, 20));

    tick(game, seconds: 1);
    expect(a.target, isNull);
  });

  gameTest('a ground-only unit cannot target a flyer', (game) async {
    final brusher = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(8, 20),
    );
    expect(brusher.stats.targets.canHit(flying: true), isFalse);
  });

  gameTest('units stay inside the arena', (game) async {
    final unit = game.spawnUnit(
      'brusher',
      team: Team.red,
      position: Vector2(0.5, 1.0),
    );

    tick(game, seconds: 4);

    expect(unit.position.x, inInclusiveRange(0, ArenaSpec.worldWidth));
    expect(unit.position.y, inInclusiveRange(0, ArenaSpec.worldHeight));
  });

  gameTest('clearing the sandbox empties the roster', (game) async {
    game.spawnCard('brusher', team: Team.red, position: Vector2(8, 20));
    game.spawnCard('roller', team: Team.blue, position: Vector2(8, 4));
    expect(game.units, hasLength(2));

    game.clearUnits();
    expect(game.units, isEmpty);
  });

  gameTest('the stress test fills the field for the 40-unit budget', (
    game,
  ) async {
    game.stressTest();
    expect(game.units, hasLength(40));

    // It has to survive a second of everything fighting everything.
    tick(game, seconds: 1);
    expect(game.units, isNotEmpty);
  });

  gameTest(
    'units path around a blocker instead of jamming against it',
    (game) async {
      // No shipped arena has blockers any more, but the steering that gets
      // round one does, so this builds a board with one in the x=8 lane
      // rather than reading a level that no longer has any.
      final blocker = game.layout.blockers.single;

      final unit = game.spawnUnit(
        'brusher',
        team: Team.red,
        position: Vector2(8, 21),
      );

      var everInside = false;
      for (var i = 0; i < 60 * 8; i++) {
        game.updateTree(1 / 60);
        if (blocker.rect.contains(Offset(unit.position.x, unit.position.y))) {
          everInside = true;
          break;
        }
      }

      expect(everInside, isFalse, reason: 'it never entered the blocker');
      expect(
        unit.position.y,
        lessThan(blocker.rect.top),
        reason: 'and it got past instead of jamming underneath',
      );
    },
    layout: () => ArenaLayout(
      id: 'blocked',
      name: 'Blocked',
      trophies: 0,
      floor: Palette.arenaFloor,
      blockers: const [Blocker(Rect.fromLTWH(6.75, 17.8, 2.5, 1.2))],
    ),
  );
}
