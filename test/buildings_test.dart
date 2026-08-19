import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_model.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/cards/elixir_bar.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';
import 'package:splatfront/game/units/building.dart';
import 'package:splatfront/game/units/projectile.dart';
import 'package:splatfront/game/units/unit_art.dart';

/// Buildings, and elixir income scaling with territory.
///
/// The two mechanics that make paint the whole game rather than just the
/// scoreboard: a building holds ground it cannot walk to, and holding ground
/// is what pays for the next card.
void main() {
  late CardRegistry cards;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
  });

  void gameTest(
    String description,
    Future<void> Function(SplatfrontGame game, WidgetTester tester) body, {
    MatchRules economy = MatchRules.flat,
  }) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        economy: economy,
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      try {
        await body(game, tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  void tick(SplatfrontGame game, {double seconds = 1.0}) {
    const step = 1 / 60;
    for (var t = 0.0; t < seconds; t += step) {
      game.updateTree(step);
    }
  }

  // --- Buildings ---------------------------------------------------------

  test('every building is a unit with a body and a lifetime', () {
    expect(cards.buildings, isNotEmpty);
    for (final card in cards.buildings) {
      expect(card.kind, CardKind.building);
      expect(card.isUnit, isTrue);
      expect(card.isTroop, isFalse);
      expect(card.unit, isNotNull);
      expect(
        card.unit!.speed,
        0,
        reason: '${card.id} must be static, not slow',
      );
      expect(
        card.unit!.isTemporary,
        isTrue,
        reason: '${card.id} needs a clock, or the board silts up',
      );
      expect(
        unitArt.containsKey(card.id),
        isTrue,
        reason: '${card.id} has no art',
      );
    }
  });

  gameTest('a building stands exactly where it is dropped', (
    game,
    tester,
  ) async {
    final turret = game.spawnUnit(
      'turret',
      team: Team.red,
      position: Vector2(5, 18),
    );
    // Something to shoot at, so it is not idle for want of a target.
    game.spawnUnit('brusher', team: Team.blue, position: Vector2(5, 14));

    tick(game, seconds: 3);

    expect(turret.position.x, closeTo(5, 0.001));
    expect(turret.position.y, closeTo(18, 0.001));
  });

  gameTest('a building expires on its own clock', (game, tester) async {
    final barricade =
        game.spawnUnit(
              'barricade',
              team: Team.red,
              position: Vector2(8, 18),
            )
            as Building;

    final lifetime = barricade.stats.lifetime;
    expect(lifetime, greaterThan(0));

    tick(game, seconds: lifetime - 1);
    expect(barricade.isAlive, isTrue, reason: 'still standing before time');
    expect(barricade.wear, greaterThan(0.9));

    tick(game, seconds: 2);
    expect(barricade.isAlive, isFalse, reason: 'and gone after it');
  });

  gameTest('an expiring building still leaves its ground painted', (
    game,
    tester,
  ) async {
    final sprinkler = game.spawnUnit(
      'sprinkler',
      team: Team.red,
      position: Vector2(8, 18),
    );
    tick(game, seconds: sprinkler.stats.lifetime + 0.5);

    expect(sprinkler.isAlive, isFalse);
    expect(
      game.arena.paintLayer.hasPendingStamps,
      isTrue,
      reason: 'the death splash is queued',
    );
  });

  gameTest('a Turret with nothing to shoot fires all round itself', (
    game,
    tester,
  ) async {
    final turret = game.spawnUnit(
      'turret',
      team: Team.red,
      position: Vector2(8, 12),
    );
    expect(
      turret.stats.volley,
      greaterThan(0),
      reason: 'the sweep length has to come from cards.json',
    );

    // Nothing on the board but the gun, so every shell is an idle one.
    final bearings = <double>[];
    final seen = <Projectile>{};
    for (var i = 0; i < 60 * 25; i++) {
      game.updateTree(1 / 60);
      for (final shell in game.world.children.whereType<Projectile>()) {
        if (!seen.add(shell)) continue;
        bearings.add(
          math.atan2(
            shell.destination.y - turret.position.y,
            shell.destination.x - turret.position.x,
          ),
        );
      }
    }

    expect(
      bearings.length,
      greaterThan(4),
      reason: 'an idle gun keeps firing instead of standing there',
    );

    // Every quadrant, not a spread within one arc: "360 degrees" is the
    // whole claim, and a gun that sprayed a 90 degree fan would pass a
    // simple "the bearings differ" check.
    final quadrants = bearings
        .map((a) => ((a / (math.pi / 2)).floor() % 4 + 4) % 4)
        .toSet();
    expect(
      quadrants,
      hasLength(4),
      reason: 'shells went out in all four quadrants, not just one fan',
    );
  });

  gameTest('a Turret shells its target rather than painting its own feet', (
    game,
    tester,
  ) async {
    final turret = game.spawnUnit(
      'turret',
      team: Team.red,
      position: Vector2(8, 18),
    );
    expect(turret.stats.paint, 0, reason: 'no trail under a static gun');
    expect(turret.stats.shellPaint, greaterThan(0));

    // A Barricade, so nothing walks away or paints a trail of its own.
    game.spawnUnit('barricade', team: Team.blue, position: Vector2(8, 14));

    // Step until a shell is actually in the air, rather than asserting on
    // whatever happens to be true after a fixed run. The earlier version of
    // this test accepted "or some paint got queued", which every unit on the
    // board can satisfy — it would have passed with the gun jammed.
    Projectile? shell;
    for (var i = 0; i < 60 * 4 && shell == null; i++) {
      game.updateTree(1 / 60);
      shell = game.world.children.whereType<Projectile>().firstOrNull;
    }

    expect(shell, isNotNull, reason: 'the cannon fired a visible shell');
    expect(shell!.paintRadius, turret.stats.shellPaint);
    expect(
      shell.arcHeight,
      greaterThan(0),
      reason: 'a mortar lobs; a flat shot reads as a bullet',
    );
  });

  gameTest('a lobbed shell rises off the ground and comes back to it', (
    game,
    tester,
  ) async {
    final shell = game.fireProjectile(
      from: Vector2(8, 20),
      at: Vector2(8, 12),
      team: Team.red,
      paintRadius: 1.5,
      speed: 8,
      arcHeight: 2.0,
    );
    game.updateTree(0);

    expect(shell.progress, closeTo(0, 0.01));

    // Halfway along, it should be at the top of its arc.
    var peak = 0.0;
    while (shell.progress < 0.98) {
      game.updateTree(1 / 60);
      final t = shell.progress;
      final lift = 4 * shell.arcHeight * t * (1 - t);
      if (lift > peak) peak = lift;
    }

    expect(peak, closeTo(shell.arcHeight, 0.1), reason: 'it really lofts');
    expect(shell.progress, closeTo(1, 0.02), reason: 'and lands where aimed');
  });

  gameTest('a Sprinkler paints without ever attacking', (game, tester) async {
    final sprinkler = game.spawnUnit(
      'sprinkler',
      team: Team.red,
      position: Vector2(8, 18),
    );
    final victim = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 18.3),
    );

    expect(sprinkler.stats.damage, 0);
    final hpBefore = victim.hp;
    game.arena.paintLayer.flush();

    tick(game, seconds: 1.5);

    expect(victim.hp, hpBefore, reason: 'it has no attack at all');
    expect(game.arena.paintLayer.hasPendingStamps, isTrue);
  });

  gameTest('an enemy walks up and attacks a building', (game, tester) async {
    final barricade = game.spawnUnit(
      'barricade',
      team: Team.red,
      position: Vector2(8, 16),
    );
    game.spawnUnit('brusher', team: Team.blue, position: Vector2(8, 14));

    tick(game, seconds: 4);

    expect(
      barricade.hp,
      lessThan(barricade.stats.hp),
      reason: 'buildings are targeted like anything else',
    );
  });

  gameTest('a Beamer paints the whole line it burns, not just the far end', (
    game,
    tester,
  ) async {
    // Just inside its own half, shooting across the middle.
    final beamer = game.spawnUnit(
      'beamer',
      team: Team.red,
      position: Vector2(8, 13),
    );
    expect(beamer.stats.paint, 0, reason: 'no puddle under the post');
    expect(beamer.stats.shellPaint, greaterThan(0));

    // A Barricade as the target: static and near-silent, so anything that
    // turns red along the way was turned by the beam and not by an enemy
    // walking over it painting its own trail.
    game.spawnUnit('barricade', team: Team.blue, position: Vector2(8, 8));

    final midway = Vector2(8, 10.5);
    await tester.runAsync(() => game.arena.resampleNow());
    expect(
      game.arena.deployZone.ownerAt(midway),
      Team.blue,
      reason: 'it starts as the bot\'s ground',
    );

    tick(game, seconds: 2.0);
    game.arena.paintLayer.flush();
    await tester.runAsync(() => game.arena.resampleNow());

    expect(
      game.arena.deployZone.ownerAt(midway),
      Team.red,
      reason: 'the stripe runs the length of the shot, not just its end',
    );
  });

  gameTest('a Whirl carves a circle around itself, not around its target', (
    game,
    tester,
  ) async {
    final whirl = game.spawnUnit(
      'whirl',
      team: Team.red,
      position: Vector2(8, 16),
    );
    expect(whirl.stats.hasSplash, isTrue);

    // One in front, one behind. A normal melee unit would only ever hit the
    // one it targeted.
    final front = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 15.2),
    );
    final behind = game.spawnUnit(
      'brusher',
      team: Team.blue,
      position: Vector2(8, 16.8),
    );

    tick(game, seconds: 2.0);

    expect(front.hp, lessThan(front.stats.hp));
    expect(
      behind.hp,
      lessThan(behind.stats.hp),
      reason: 'standing behind a spinning blade is no safer',
    );
  });

  gameTest('every card can fire mid-frame without breaking the tree walk', (
    game,
    tester,
  ) async {
    // The crash this guards against: effects spawned from inside `update` —
    // a Beamer's beam, a spell's burst — went straight into `world.add`,
    // which mutates the child set Flame is part-way through walking. That
    // throws a ConcurrentModificationError and takes the match down. Every
    // such spawn has to go through the queue instead.
    //
    // Runs one of everything, both sides, and lets them all fight.
    const ours = ['beamer', 'turret', 'scatter', 'sprinkler', 'whirl',
        'nozzle', 'sprayer', 'pin', 'sniper_nib', 'warden'];
    for (var i = 0; i < ours.length; i++) {
      game.spawnUnit(
        ours[i],
        team: Team.red,
        position: Vector2(2.0 + i * 1.2, 15),
      );
      game.spawnUnit(
        ours[i],
        team: Team.blue,
        position: Vector2(2.0 + i * 1.2, 11),
      );
    }
    for (final spell in ['paint_bomb', 'freeze', 'solvent', 'surge']) {
      game.castSpell(cards[spell], Team.red, Vector2(8, 12));
    }

    expect(
      () => tick(game, seconds: 8),
      returnsNormally,
      reason: 'nothing may add to the world from inside the walk',
    );
  });

  // --- Elixir tied to territory -----------------------------------------

  test('income is even at an even split and swings at the extremes', () {
    const economy = MatchRules(territorySpread: 0.45);
    expect(economy.multiplierFor(0.5), closeTo(1.0, 1e-9));
    expect(economy.multiplierFor(1.0), closeTo(1.45, 1e-9));
    expect(economy.multiplierFor(0.0), closeTo(0.55, 1e-9));
    // A side pinned at nothing still earns something, or it can never
    // play its way back out.
    expect(economy.multiplierFor(0.0), greaterThan(0));
  });

  test('a flat economy leaves income exactly as it was', () {
    expect(MatchRules.flat.multiplierFor(0.0), 1.0);
    expect(MatchRules.flat.multiplierFor(1.0), 1.0);
  });

  test('the shipped economy comes from progression.json, not from Dart', () async {
    final loaded = await MatchRules.load();
    expect(
      loaded.territorySpread,
      greaterThan(0),
      reason: 'the real game scales income with territory',
    );

    // Territory income is a positive feedback loop, so the shipped spread has
    // to stay gentle: the side that is losing must keep enough income to play
    // its way back, or one early mistake decides the match.
    expect(
      loaded.multiplierFor(0),
      greaterThanOrEqualTo(0.7),
      reason: 'a side pinned at zero coverage can still afford cards',
    );
    expect(
      loaded.multiplierFor(1) / loaded.multiplierFor(0),
      lessThanOrEqualTo(1.8),
      reason: 'the gap between winning and losing income stays recoverable',
    );
  });

  gameTest(
    'holding more ground fills the bar faster',
    (game, tester) async {
      // Red owns the bottom half at the start, so both sides sit at an
      // even split until the sampler says otherwise.
      game.player.elixir.value.value = 0;
      game.opponent.elixir.value.value = 0;

      // Pretend red has painted almost everything.
      game.player.elixir.rateMultiplier = game.economy.multiplierFor(0.9);
      game.opponent.elixir.rateMultiplier = game.economy.multiplierFor(0.1);

      game.player.elixir.update(1.0);
      game.opponent.elixir.update(1.0);

      expect(
        game.player.elixir.amount,
        greaterThan(game.opponent.elixir.amount),
        reason: 'the side holding the board earns faster',
      );
    },
    economy: const MatchRules(territorySpread: 0.45),
  );

  gameTest(
    'the arena drives income without anyone asking it to',
    (game, tester) async {
      await tester.runAsync(() => game.arena.resampleNow());
      game.updateTree(1 / 60);

      // A 50/50 board: both sides land on the same multiplier, and it is 1.
      expect(game.player.elixir.rateMultiplier, closeTo(1.0, 0.06));
      expect(game.opponent.elixir.rateMultiplier, closeTo(1.0, 0.06));
    },
    economy: const MatchRules(territorySpread: 0.45),
  );

  test('the bar clamps a runaway multiplier instead of trusting it', () {
    // A bad number in progression.json should cost a wonky regen rate, not a
    // divide that hands one side ten elixir in a single frame.
    final bar = ElixirBar(start: 0)..rateMultiplier = 10000;
    expect(bar.secondsPerElixir, greaterThan(0));
    bar.update(1 / 60);
    expect(bar.amount, lessThan(ElixirSpec.max));

    // And the other way: a multiplier of zero must not divide by zero.
    final stalled = ElixirBar(start: 0)..rateMultiplier = 0;
    expect(stalled.secondsPerElixir.isFinite, isTrue);
    expect(() => stalled.update(1 / 60), returnsNormally);
  });
}
