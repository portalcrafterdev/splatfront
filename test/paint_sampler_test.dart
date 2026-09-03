import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/paint_sampler.dart';

/// Builds a raw RGBA buffer where every pixel is [colourOf] for its row.
Uint8List _buffer(int w, int h, int Function(int y) colourOf) {
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final argb = colourOf(y);
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = 0xFF;
    }
  }
  return bytes;
}

SampleResult _sample(Uint8List pixels, {Uint8List? blocked}) => samplePaint(
  SampleRequest(
    pixels: pixels,
    imageWidth: ArenaSpec.paintImageWidth,
    imageHeight: ArenaSpec.paintImageHeight,
    blockedCells: blocked ?? Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows),
  ),
);

/// A palette colour as the 0xRRGGBB int [_buffer] wants.
///
/// Read from the palette rather than written out, so a team recolour cannot
/// leave this file quietly asserting against the old game's colours.
int _rgb(Color c) =>
    ((c.r * 255).round() << 16) |
    ((c.g * 255).round() << 8) |
    (c.b * 255).round();

void main() {
  const w = ArenaSpec.paintImageWidth;
  const h = ArenaSpec.paintImageHeight;

  final redPixel = _rgb(Palette.red);
  final bluePixel = _rgb(Palette.blue);
  final neutralPixel = _rgb(Palette.neutral);

  test('a fully red arena scores 100% red', () {
    final result = _sample(_buffer(w, h, (_) => redPixel));
    expect(result.coverage.red, 1.0);
    expect(result.coverage.blue, 0.0);
  });

  test('an even split scores 50/50', () {
    final result = _sample(
      _buffer(w, h, (y) => y < h ~/ 2 ? bluePixel : redPixel),
    );
    expect(result.coverage.blue, closeTo(0.5, 0.001));
    expect(result.coverage.red, closeTo(0.5, 0.001));
  });

  test('the match start state is an even split with no neutral ground', () {
    // Bot band on top, player band at the bottom, meeting in the middle.
    const botEnd = h * ArenaSpec.startBandBot ~/ ArenaSpec.worldHeight;
    final result = _sample(
      _buffer(w, h, (y) => y < botEnd ? bluePixel : redPixel),
    );

    const expected = ArenaSpec.startBandPlayer / ArenaSpec.worldHeight;
    expect(expected, 0.5, reason: 'the halves are equal');
    expect(result.coverage.red, closeTo(expected, 0.01));
    expect(result.coverage.blue, closeTo(expected, 0.01));
    expect(result.coverage.neutral, closeTo(0, 0.01));
  });

  test('neutral ground scores for nobody', () {
    final result = _sample(_buffer(w, h, (_) => neutralPixel));
    expect(result.coverage.red, 0.0);
    expect(result.coverage.blue, 0.0);
    expect(result.coverage.neutral, 1.0);
  });

  test('off-palette pixels classify to the nearest team colour', () {
    // A dark, desaturated red is still red.
    final result = _sample(_buffer(w, h, (_) => 0xB3402F));
    expect(result.coverage.red, 1.0);
  });

  test('blocked cells leave the denominator, they do not dilute the score', () {
    final blocked = Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows);
    // Block the entire bottom half of the grid.
    blocked.fillRange(
      ArenaSpec.gridCols * ArenaSpec.gridRows ~/ 2,
      ArenaSpec.gridCols * ArenaSpec.gridRows,
      1,
    );
    // ...and paint the whole arena red.
    final result = _sample(_buffer(w, h, (_) => redPixel), blocked: blocked);

    expect(result.coverage.red, 1.0, reason: 'blockers are not neutral ground');
    for (
      var i = ArenaSpec.gridCols * ArenaSpec.gridRows ~/ 2;
      i < ArenaSpec.gridCols * ArenaSpec.gridRows;
      i++
    ) {
      expect(result.owners[i], Team.neutral.index);
    }
  });

  test('owner grid drives the deploy map', () {
    final result = _sample(
      _buffer(w, h, (y) => y < h ~/ 2 ? bluePixel : redPixel),
    );
    expect(result.owners.first, Team.blue.index);
    expect(result.owners.last, Team.red.index);
    expect(result.owners.length, ArenaSpec.gridCols * ArenaSpec.gridRows);
  });

  test('lead is reported from each side', () {
    const coverage = Coverage(0.6, 0.3);
    expect(coverage.leadFor(Team.red), closeTo(0.3, 1e-9));
    expect(coverage.leadFor(Team.blue), closeTo(-0.3, 1e-9));
    expect(coverage.neutral, closeTo(0.1, 1e-9));
  });
}
