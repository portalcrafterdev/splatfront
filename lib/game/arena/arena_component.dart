import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import 'arena_layout.dart';
import 'deploy_zone.dart';
import 'paint_layer.dart';
import 'paint_sampler.dart';

/// The arena floor: warm off-white ground, the paint layer over it, and the
/// static blockers on top. Everything else in the game renders above this.
class ArenaComponent extends PositionComponent {
  ArenaComponent({required this.layout, this.playerTeam = Team.blue})
    : super(
        position: Vector2.zero(),
        size: Vector2(ArenaSpec.worldWidth, ArenaSpec.worldHeight),
        priority: -100,
      );

  final ArenaLayout layout;
  final Team playerTeam;

  final PaintLayer paintLayer = PaintLayer();
  final DeployZone deployZone = DeployZone();

  /// The HUD's only channel into the arena. Never call setState in here.
  final ValueNotifier<Coverage> coverage = ValueNotifier(const Coverage.zero());

  late final Uint8List _blockedMask = layout.buildBlockedMask();

  double _sampleTimer = 0;

  /// Set the moment the component is torn down. A sampling pass in flight
  /// must not resolve onto a disposed notifier.
  bool _disposed = false;

  final Paint _floorPaint = Paint();

  /// No filtering: the paint layer is a grid of flat cells, and smoothing it
  /// on the way up to screen size would soften the tile edges into the blur
  /// the grid exists to avoid.
  final Paint _imagePaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
  final Paint _blockerPaint = Paint()..color = Palette.blocker;
  final Paint _blockerShadow = Paint()
    ..color = const Color(0x33000000)
    ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 0.06);

  late final Rect _floorRect = Rect.fromLTWH(
    0,
    0,
    ArenaSpec.worldWidth,
    ArenaSpec.worldHeight,
  );
  late final Rect _srcRect = Rect.fromLTWH(
    0,
    0,
    paintLayer.width.toDouble(),
    paintLayer.height.toDouble(),
  );

  /// The scoring grid, drawn over the paint so the tiles read as tiles.
  ///
  /// Baked into one image at load and blitted as a single quad. Replaying it
  /// as a [ui.Picture] meant re-issuing 160 anti-aliased full-length lines
  /// every frame; one textured rectangle is a fraction of that, and it never
  /// changes.
  late final ui.Image _gridImage = _bakeGrid();

  late final Rect _gridSrc = Rect.fromLTWH(
    0,
    0,
    _gridImage.width.toDouble(),
    _gridImage.height.toDouble(),
  );

  final Paint _gridPaint = Paint()..filterQuality = FilterQuality.low;

  ui.Image _bakeGrid() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Drawn at the paint layer's own resolution, so one cell is exactly
    // [ArenaSpec.pixelsPerCellX] pixels and every line lands on a whole
    // pixel rather than smearing across two.
    final ink = Paint()
      ..color = const Color(0x1F000000)
      ..strokeWidth = 1
      ..isAntiAlias = false;

    const w = ArenaSpec.paintImageWidth;
    const h = ArenaSpec.paintImageHeight;
    for (var col = 1; col < ArenaSpec.gridCols; col++) {
      final x = (col * ArenaSpec.pixelsPerCellX).toDouble();
      canvas.drawLine(Offset(x, 0), Offset(x, h.toDouble()), ink);
    }
    for (var row = 1; row < ArenaSpec.gridRows; row++) {
      final y = (row * ArenaSpec.pixelsPerCellY).toDouble();
      canvas.drawLine(Offset(0, y), Offset(w.toDouble(), y), ink);
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return image;
  }

  @override
  Future<void> onLoad() async {
    _floorPaint.color = layout.floor;
    deployZone.updateBlocked(_blockedMask);
    await paintLayer.reset(playerTeam: playerTeam);
    // Kicked off, not awaited: loading must not block on a GPU readback.
    // The first coverage and deploy map land a frame or two later.
    _requestSample();
  }

  double _bakeTimer = 0;

  @override
  void update(double dt) {
    _bakeTimer += dt;
    _sampleTimer += dt;
    if (_sampleTimer >= Timings.coverageSampleTick) {
      _sampleTimer = 0;
      _requestSample();
    }
  }

  /// The pass currently in flight, if any. Only one readback at a time.
  Future<void>? _pass;

  void _requestSample() {
    if (_pass != null || _disposed) return;
    _pass = _sample().whenComplete(() => _pass = null);
  }

  /// Forces a resample and waits for it, rather than waiting for the next
  /// tick. Used when something needs the deploy map to reflect a stamp right
  /// away — a spell landing, or a test asserting on the new deploy line.
  Future<void> resampleNow() async {
    // Let whatever is already reading back finish before starting another.
    await _pass;
    if (_disposed) return;
    final pass = _sample();
    _pass = pass.whenComplete(() => _pass = null);
    await pass;
  }

  /// Reads the paint image back once and reclassifies the whole grid.
  ///
  /// Runs at 2 Hz, and reads back one pixel per cell rather than the whole
  /// image — 24 KB instead of 1.5 MB. The classification itself is ~6k cells
  /// of integer maths; if it ever shows up in the timeline, hand [samplePaint]
  /// and a copy of the buffer to `compute()` — it is already a pure top-level
  /// function for exactly that reason.
  Future<void> _sample() async {
    final bytes = await paintLayer.readCoverage();
    if (bytes == null || _disposed) return;

    final result = samplePaint(
      SampleRequest(
        pixels: bytes.buffer.asUint8List(),
        imageWidth: paintLayer.sampleWidth,
        imageHeight: paintLayer.sampleHeight,
        blockedCells: _blockedMask,
      ),
    );
    if (_disposed) return;
    deployZone.updateOwners(result.owners);
    coverage.value = result.coverage;
  }

  @override
  void render(Canvas canvas) {
    // Baking allocates a whole new paint texture, so it runs on its own tick
    // rather than every frame. Whatever has been queued since is drawn live
    // below, which looks the same and costs a few rectangles.
    if (_bakeTimer >= Timings.paintBakeTick) {
      _bakeTimer = 0;
      paintLayer.flush();
    }

    canvas.drawRect(_floorRect, _floorPaint);

    final image = paintLayer.image;
    if (image != null) {
      canvas.drawImageRect(image, _srcRect, _floorRect, _imagePaint);
    }
    paintLayer.renderPending(canvas);

    canvas.drawImageRect(_gridImage, _gridSrc, _floorRect, _gridPaint);

    for (final blocker in layout.blockers) {
      canvas.drawRRect(
        RRect.fromRectXY(blocker.rect.translate(0, 0.12), 0.25, 0.25),
        _blockerShadow,
      );
      canvas.drawRRect(
        RRect.fromRectXY(blocker.rect, 0.25, 0.25),
        _blockerPaint,
      );
    }
  }

  @override
  void onRemove() {
    _disposed = true;
    paintLayer.dispose();
    _gridImage.dispose();
    coverage.dispose();
    super.onRemove();
  }
}
