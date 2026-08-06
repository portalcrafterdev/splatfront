import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';

/// The paint layer: one offscreen [ui.Image] holding every stamp ever made.
///
/// This is simultaneously the scoreboard, the deploy-zone map and the
/// battlefield floor, so it is the one thing in the game that must never
/// get slow. The rules it enforces on itself:
///
///  * stamps are queued and flushed **once per frame**, never one image per
///    stamp;
///  * [Paint] objects are allocated once, never inside the stamp loop;
///  * pixels are read back at most every [Timings.coverageSampleTick], never
///    per frame.
///
/// Paint is laid down in whole grid cells rather than soft blobs. A stamp
/// claims every cell whose centre falls inside its radius and fills it edge
/// to edge, which means the tiles you see are exactly the cells the sampler
/// scores and the deploy map reads — no half-covered cell can look painted
/// but count as enemy ground. It also draws in a handful of row-wide
/// rectangles instead of one shape per cell: a Roller blob is about 250
/// cells but only 18 rows.
class PaintLayer {
  PaintLayer({
    this.width = ArenaSpec.paintImageWidth,
    this.height = ArenaSpec.paintImageHeight,
  });

  final int width;
  final int height;

  ui.Image? _image;

  /// The current paint image. Null until [reset] has been awaited.
  ui.Image? get image => _image;

  /// Queued stamps, drained by [flush] on the next frame.
  final List<_Stamp> _pending = <_Stamp>[];

  /// One hard-edged [Paint] per team, built once. Cells are filled flat and
  /// anti-aliasing is off, so neighbouring cells of the same colour merge
  /// into one solid shape with no seam between them.
  static final Map<Team, Paint> _flats = {
    for (final team in Team.values)
      team: Paint()
        ..color = Palette.of(team)
        ..isAntiAlias = false,
  };
  static final Paint _blit = Paint()..filterQuality = FilterQuality.none;

  /// Width and height of one grid cell, in paint-image pixels.
  double get _cellW => width / ArenaSpec.gridCols;
  double get _cellH => height / ArenaSpec.gridRows;

  /// Paints the match start state: the arena split in half, [playerTeam] at
  /// the bottom and their opponent at the top. No neutral ground — the board
  /// starts 50/50 and every cell belongs to somebody.
  Future<void> reset({Team playerTeam = Team.blue}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Snapped to a cell boundary so the halves are exactly equal and the
    // seam falls between two rows rather than through one.
    final split = (ArenaSpec.gridRows ~/ 2) * _cellH;

    canvas.drawRect(
      Rect.fromLTRB(0, 0, width.toDouble(), split),
      _flats[playerTeam.opponent]!,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, split, width.toDouble(), height.toDouble()),
      _flats[playerTeam]!,
    );

    final picture = recorder.endRecording();
    final next = picture.toImageSync(width, height);
    picture.dispose();
    _image?.dispose();
    _image = next;
    _pending.clear();
  }

  /// Queues a round splat at [worldPos] with [radius] in world units.
  ///
  /// Overwriting is absolute: every cell the splat claims becomes [team]'s
  /// colour. No per-cell health, no blending.
  void stamp(Vector2 worldPos, double radius, Team team) {
    if (radius <= 0) return;
    _pending.add(
      _Stamp(
        worldPos.x * ArenaSpec.cellsPerUnit,
        worldPos.y * ArenaSpec.cellsPerUnit,
        radius * ArenaSpec.cellsPerUnit,
        team,
      ),
    );
  }

  /// Queues the single large splat a spell leaves behind.
  void stampSpell(Vector2 worldPos, double radius, Team team) =>
      stamp(worldPos, radius, team);

  bool get hasPendingStamps => _pending.isNotEmpty;

  /// Burns every queued stamp into the image.
  ///
  /// This is the single most expensive thing the game does per call: it blits
  /// the whole image forward and then allocates a **new** one, because a
  /// `ui.Image` cannot be drawn into in place. At 512x768 that is 1.5 MB of
  /// fresh texture every time.
  ///
  /// So do not call it every frame. [ArenaComponent] bakes on
  /// [Timings.paintBakeTick] and draws anything still queued live on top with
  /// [renderPending], which looks identical and costs a handful of rectangles
  /// instead of a texture allocation. Calling it per frame cost roughly
  /// 90 MB/s of GPU churn and was the reason the frame rate sagged in a busy
  /// fight.
  void flush() {
    final current = _image;
    if (current == null || _pending.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(current, Offset.zero, _blit);
    for (var i = 0; i < _pending.length; i++) {
      _drawCells(canvas, _pending[i], _cellW, _cellH);
    }
    final picture = recorder.endRecording();
    final next = picture.toImageSync(width, height);
    picture.dispose();
    current.dispose();
    _image = next;
    _pending.clear();
  }

  /// Draws the stamps queued since the last bake, in world units.
  ///
  /// The caller has already drawn the baked image underneath, so together
  /// these are exactly what a per-frame bake would have produced — the paint
  /// appears the instant a unit lays it down, without paying for an image to
  /// say so.
  void renderPending(Canvas canvas) {
    if (_pending.isEmpty) return;
    const cell = ArenaSpec.worldWidth / ArenaSpec.gridCols;
    for (var i = 0; i < _pending.length; i++) {
      _drawCells(canvas, _pending[i], cell, cell);
    }
  }

  /// Fills the cells of one splat, a whole row at a time.
  ///
  /// A cell is claimed when its centre lies inside the circle, and the whole
  /// cell is then filled flat. The sampler scores a cell by reading its
  /// centre pixel, so what is drawn and what is counted can never disagree.
  /// The smallest splat still takes a cell: a stamp that painted nothing
  /// would leave a unit trailing gaps.
  ///
  /// [cellW] and [cellH] are the size of a grid cell in whatever space the
  /// canvas is in: image pixels when baking, world units when drawing live.
  void _drawCells(Canvas canvas, _Stamp s, double cellW, double cellH) {
    final paint = _flats[s.team]!;
    final r = math.max(s.r, 0.5);
    final firstRow = math.max((s.cy - r - 0.5).floor(), 0);
    final lastRow = math.min((s.cy + r + 0.5).ceil(), ArenaSpec.gridRows - 1);

    for (var row = firstRow; row <= lastRow; row++) {
      // Horizontal half-width of the circle at this row of cell centres.
      final dy = (row + 0.5) - s.cy;
      final span = r * r - dy * dy;
      if (span <= 0) continue;
      final half = math.sqrt(span);

      final from = math.max((s.cx - half - 0.5).ceil(), 0);
      final to = math.min((s.cx + half - 0.5).floor(), ArenaSpec.gridCols - 1);
      if (to < from) continue;

      canvas.drawRect(
        Rect.fromLTRB(
          from * cellW,
          row * cellH,
          (to + 1) * cellW,
          (row + 1) * cellH,
        ),
        paint,
      );
    }
  }

  /// Reads the whole image back once, at full resolution.
  ///
  /// 1.5 MB across the bus. Nothing in the game needs that — [readCoverage]
  /// is what the sampler uses. Kept because a test that wants to inspect the
  /// actual pixels should be able to.
  Future<ByteData?> readPixels() =>
      _image?.toByteData(format: ui.ImageByteFormat.rawRgba) ??
      Future<ByteData?>.value();

  /// Size of the buffer [readCoverage] hands back: one pixel per grid cell.
  int get sampleWidth => ArenaSpec.gridCols;
  int get sampleHeight => ArenaSpec.gridRows;

  /// Reads the paint back at exactly one pixel per scoring cell.
  ///
  /// The sampler only ever looks at cell centres, so pulling the full
  /// 512x768 image over the bus moved sixty-four times more data than it
  /// read. Scaling down to the grid first costs one tiny image and turns a
  /// 1.5 MB readback into 24 KB.
  ///
  /// The downscale is safe rather than approximate: a cell is a flat block of
  /// [ArenaSpec.pixelsPerCellX] identical pixels, and unfiltered sampling
  /// lands in the middle of one, so the colour cannot come out blended.
  Future<ByteData?> readCoverage() async {
    final current = _image;
    if (current == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      current,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Rect.fromLTWH(0, 0, sampleWidth.toDouble(), sampleHeight.toDouble()),
      _blit,
    );
    final picture = recorder.endRecording();
    final small = picture.toImageSync(sampleWidth, sampleHeight);
    picture.dispose();

    try {
      return await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      small.dispose();
    }
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _pending.clear();
  }
}

/// One queued splat, in grid-cell coordinates.
class _Stamp {
  const _Stamp(this.cx, this.cy, this.r, this.team);

  /// Centre, in cells from the top-left of the grid.
  final double cx;
  final double cy;

  /// Radius, in cells.
  final double r;
  final Team team;
}
