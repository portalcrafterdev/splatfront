import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/paint_layer.dart';
import 'package:splatfront/game/arena/paint_sampler.dart';

/// End-to-end through the real rasteriser: stamp, flush, read back, score.
Future<Coverage> _score(PaintLayer layer) async {
  final bytes = await layer.readPixels();
  return samplePaint(
    SampleRequest(
      pixels: bytes!.buffer.asUint8List(),
      imageWidth: layer.width,
      imageHeight: layer.height,
      blockedCells: Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows),
    ),
  ).coverage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PaintLayer layer;

  setUp(() => layer = PaintLayer());
  tearDown(() => layer.dispose());

  test('reset lays down the 10 / 4 / 10 start state', () async {
    await layer.reset(playerTeam: Team.red);
    final coverage = await _score(layer);

    const band = ArenaSpec.startBandPlayer / ArenaSpec.worldHeight;
    expect(coverage.red, closeTo(band, 0.02));
    expect(coverage.blue, closeTo(band, 0.02));
    expect(coverage.neutral, closeTo(1 - 2 * band, 0.02));
  });

  test('the player band is at the bottom of the arena', () async {
    await layer.reset(playerTeam: Team.red);
    final bytes = await layer.readPixels();
    final owners = samplePaint(
      SampleRequest(
        pixels: bytes!.buffer.asUint8List(),
        imageWidth: layer.width,
        imageHeight: layer.height,
        blockedCells: Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows),
      ),
    ).owners;

    expect(owners.last, Team.red.index, reason: 'bottom row is the player');
    expect(owners.first, Team.blue.index, reason: 'top row is the bot');
  });

  test('a stamp overwrites enemy paint absolutely', () async {
    await layer.reset(playerTeam: Team.red);
    final before = await _score(layer);

    // Drop a big red blob deep in blue territory.
    layer.stamp(Vector2(8, 4), 3.0, Team.red);
    expect(layer.hasPendingStamps, isTrue);
    layer.flush();
    expect(layer.hasPendingStamps, isFalse);

    final after = await _score(layer);
    expect(after.red, greaterThan(before.red));
    expect(after.blue, lessThan(before.blue));
  });

  test('solvent wipes to neutral, scoring for nobody', () async {
    await layer.reset(playerTeam: Team.red);
    final before = await _score(layer);

    layer.stamp(Vector2(8, 22), 3.0, Team.neutral);
    layer.flush();

    final after = await _score(layer);
    expect(after.red, lessThan(before.red));
    expect(after.blue, closeTo(before.blue, 0.01));
    expect(after.neutral, greaterThan(before.neutral));
  });

  test('a batch of stamps costs one image, not one per stamp', () async {
    await layer.reset();
    final first = layer.image;

    for (var i = 0; i < 40; i++) {
      layer.stamp(Vector2(i % 16 + 0.5, i / 40 * 24), 1.0, Team.red);
    }
    layer.flush();

    expect(layer.image, isNot(same(first)));
    expect(layer.hasPendingStamps, isFalse);
  });

  test('flush with nothing queued is a no-op', () async {
    await layer.reset();
    final before = layer.image;
    layer.flush();
    expect(layer.image, same(before));
  });

  test('a zero-radius stamp is never queued', () async {
    await layer.reset();
    layer.stamp(Vector2(8, 12), 0, Team.red);
    expect(layer.hasPendingStamps, isFalse);
  });

  test('painting the whole arena reaches 100%', () async {
    await layer.reset();
    for (var y = 0.0; y < ArenaSpec.worldHeight; y += 1.0) {
      for (var x = 0.0; x < ArenaSpec.worldWidth; x += 1.0) {
        layer.stamp(Vector2(x, y), 1.6, Team.blue);
      }
    }
    layer.flush();

    final coverage = await _score(layer);
    expect(coverage.blue, closeTo(1.0, 0.01));
    expect(coverage.red, 0.0);
  });
}
