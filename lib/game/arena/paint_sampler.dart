import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/palette.dart';

/// The two side percentages, 0..1. Neutral ground counts for nobody.
class Coverage {
  const Coverage(this.red, this.blue);

  const Coverage.zero() : red = 0, blue = 0;

  final double red;
  final double blue;

  double get neutral => (1.0 - red - blue).clamp(0.0, 1.0);

  double forTeam(Team team) => switch (team) {
    Team.red => red,
    Team.blue => blue,
    Team.neutral => neutral,
  };

  /// Positive when [team] is ahead.
  double leadFor(Team team) => forTeam(team) - forTeam(team.opponent);

  @override
  String toString() =>
      'Coverage(red: ${(red * 100).toStringAsFixed(1)}%, '
      'blue: ${(blue * 100).toStringAsFixed(1)}%)';
}

/// Everything the sampler needs to run, in plain data so the whole job can be
/// handed to a compute isolate unchanged if readback ever stalls the frame.
class SampleRequest {
  const SampleRequest({
    required this.pixels,
    required this.imageWidth,
    required this.imageHeight,
    required this.blockedCells,
  });

  final Uint8List pixels; // rawRgba
  final int imageWidth;
  final int imageHeight;

  /// One flag per grid cell: 1 means an obstacle sits here, so the cell is
  /// unpaintable and is excluded from both the numerator and the denominator.
  final Uint8List blockedCells;
}

/// Result of one sampling pass: the percentages plus the owner grid the
/// deploy-zone check reads.
class SampleResult {
  const SampleResult(this.coverage, this.owners);

  final Coverage coverage;

  /// [Team.index] per cell, row-major, [ArenaSpec.gridCols] wide.
  /// Blocked cells hold [Team.neutral].
  final Uint8List owners;
}

/// Walks the [ArenaSpec.gridCols] x [ArenaSpec.gridRows] grid, classifying each
/// cell by the nearest of the three palette colours.
///
/// Top-level and pure so it can be passed straight to `compute()`.
SampleResult samplePaint(SampleRequest req) {
  const cols = ArenaSpec.gridCols;
  const rows = ArenaSpec.gridRows;

  final owners = Uint8List(cols * rows);
  final pixels = req.pixels;
  final stride = req.imageWidth * 4;

  // Sample the pixel at the centre of each cell.
  final cellW = req.imageWidth / cols;
  final cellH = req.imageHeight / rows;

  var redCells = 0;
  var blueCells = 0;
  var scorable = 0;

  for (var row = 0; row < rows; row++) {
    final py = ((row + 0.5) * cellH).floor().clamp(0, req.imageHeight - 1);
    final rowBase = py * stride;
    final gridBase = row * cols;

    for (var col = 0; col < cols; col++) {
      final cell = gridBase + col;
      if (req.blockedCells[cell] != 0) {
        owners[cell] = Team.neutral.index;
        continue;
      }

      final px = ((col + 0.5) * cellW).floor().clamp(0, req.imageWidth - 1);
      final i = rowBase + px * 4;
      final team = _classify(pixels[i], pixels[i + 1], pixels[i + 2]);

      owners[cell] = team.index;
      scorable++;
      if (team == Team.red) {
        redCells++;
      } else if (team == Team.blue) {
        blueCells++;
      }
    }
  }

  if (scorable == 0) return SampleResult(const Coverage.zero(), owners);
  return SampleResult(
    Coverage(redCells / scorable, blueCells / scorable),
    owners,
  );
}

/// Palette targets flattened to bytes once, so the per-cell hot loop does no
/// colour-channel maths beyond the subtraction.
final Uint8List _targetBytes = Uint8List.fromList([
  for (final c in Palette.classifyTargets) ...[
    (c.r * 255).round(),
    (c.g * 255).round(),
    (c.b * 255).round(),
  ],
]);

/// Nearest of red / blue / neutral by squared RGB distance.
Team _classify(int r, int g, int b) {
  var best = Team.neutral;
  var bestDist = 1 << 30;
  for (var i = 0; i < 3; i++) {
    final t = i * 3;
    final dr = r - _targetBytes[t];
    final dg = g - _targetBytes[t + 1];
    final db = b - _targetBytes[t + 2];
    final dist = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = Team.values[i];
    }
  }
  return best;
}
