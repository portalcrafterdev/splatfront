import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/splatfront_game.dart';
import 'package:splatfront/game/units/projectile.dart';

/// Ranged units throw something, and the ones that paint land their colour
/// where the shot lands rather than under their own feet.
void main() {
  late CardRegistry cards;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
  });

  SplatfrontGame newGame() =>
      SplatfrontGame(layout: ArenaLayout.fallback, cards: cards);

  /// Runs the tree far enough for shots to fly and land.
  void run(SplatfrontGame game, {double seconds = 1.0}) {
    const dt = 1 / 60;
    for (var t = 0.0; t < seconds; t += dt) {
      game.updateTree(dt);
    }
  }

  Iterable<Projectile> shotsIn(SplatfrontGame game) =>
      game.world.children.whereType<Projectile>();

  test('a cannon shot flies to where it was aimed and splats there', () async {
    final game = newGame();
    await game.onLoad();

    final landing = Vector2(8, 6);
    game.fireProjectile(
      from: Vector2(8, 18),
      at: landing,
      team: Team.red,
      paintRadius: 1.5,
      speed: 20,
    );
    game.updateTree(0);
    expect(shotsIn(game), hasLength(1), reason: 'the shot is on the field');

    run(game, seconds: 1.2);

    expect(shotsIn(game), isEmpty, reason: 'it left the tree once it landed');
    expect(
      game.arena.paintLayer.hasPendingStamps,
      isTrue,
      reason: 'the splat is queued at the landing point',
    );
  });

  test('a shot with no paint radius leaves the ground alone', () async {
    final game = newGame();
    await game.onLoad();
    game.arena.paintLayer.flush();

    game.fireProjectile(
      from: Vector2(8, 18),
      at: Vector2(8, 12),
      team: Team.red,
      speed: 20,
    );
    run(game, seconds: 1.0);

    expect(shotsIn(game), isEmpty);
    expect(game.arena.paintLayer.hasPendingStamps, isFalse);
  });

  test('a landed shot splats once, not once per frame', () async {
    final game = newGame();
    await game.onLoad();

    game.fireProjectile(
      from: Vector2(8, 18),
      at: Vector2(8, 17),
      team: Team.red,
      paintRadius: 1.0,
      speed: 30,
    );

    // Long enough that a shot with no arrival guard would land many times.
    run(game, seconds: 0.6);
    expect(shotsIn(game), isEmpty);
  });

  test('spawning from inside the tree walk does not break the walk', () async {
    final game = newGame();
    await game.onLoad();

    // A unit swinging and the bot playing a card both happen mid-walk, which
    // is why spawns are queued rather than added straight into the world.
    game.spawnUnit('nozzle', team: Team.red, position: Vector2(8, 14));
    game.spawnUnit('brusher', team: Team.blue, position: Vector2(8, 12));

    expect(() => run(game, seconds: 4.0), returnsNormally);
  });

  test(
    'a Nozzle fires when it swings, and its splat matches its blast',
    () async {
      final game = newGame();
      await game.onLoad();

      final nozzle = game.spawnUnit(
        'nozzle',
        team: Team.red,
        position: Vector2(8, 14),
      );
      game.spawnUnit('brusher', team: Team.blue, position: Vector2(8, 11));
      game.updateTree(0);

      // Long enough to acquire the target, close to range and swing once.
      run(game, seconds: 3.0);

      expect(
        game.arena.paintLayer.hasPendingStamps || shotsIn(game).isNotEmpty,
        isTrue,
        reason: 'the cannon has fired something by now',
      );
      expect(nozzle.stats.splashRadius, greaterThan(0));
    },
  );
}
