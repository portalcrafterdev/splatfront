import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import 'deploy_zone.dart';

/// What the player is currently dragging over the arena.
class DeployPreview {
  const DeployPreview({
    required this.worldPosition,
    required this.radius,
    required this.team,
    required this.valid,
    required this.showValidCells,
  });

  final Vector2 worldPosition;
  final double radius;
  final Team team;

  /// Whether releasing here would actually place the card.
  final bool valid;

  /// Spells may land anywhere, so they get a ghost but no deploy-zone glow.
  final bool showValidCells;
}

/// Draws the drop feedback: a soft glow over every cell the player may deploy
/// on, a green ghost under the finger, and a red X where the drop is refused.
///
/// Lives above the arena and below the units.
class DeployOverlay extends PositionComponent {
  DeployOverlay({required this.deployZone})
    : super(
        position: Vector2.zero(),
        size: Vector2(ArenaSpec.worldWidth, ArenaSpec.worldHeight),
        priority: -50,
      );

  final DeployZone deployZone;

  DeployPreview? _preview;

  DeployPreview? get preview => _preview;

  set preview(DeployPreview? value) {
    _preview = value;
    // The glow only changes when the drag starts or the paint map is
    // resampled, so it is cached rather than rebuilt every frame.
    if (value == null) _dropGlowCache = null;
  }

  ui.Picture? _dropGlowCache;
  int _cachedOwnersVersion = -1;
  Team? _cachedTeam;

  /// A pale wash rather than a tint of [Palette.deployValid], for the same
  /// reason [Palette.deployInvalid] is pink: this is drawn *over* team paint,
  /// and a green wash at 16% over the blue was an invisible confirmation —
  /// green and blue are close enough in hue that it barely moved the colour.
  /// White lifts either team's ground the same amount, so the lit region reads
  /// as your deploy zone whichever side you are playing.
  static final Paint _glowPaint = Paint()
    ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.22);
  static final Paint _ghostFill = Paint();
  static final Paint _ghostEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.09;
  static final Paint _crossPaint = Paint()
    ..color = Palette.deployInvalid
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.12
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    final preview = _preview;
    if (preview == null) return;

    if (preview.showValidCells) _renderValidCells(canvas, preview.team);
    _renderGhost(canvas, preview);
  }

  /// Every cell of [team]'s colour, as one cached picture.
  ///
  /// Cells are merged into horizontal runs first: a full half-arena is about
  /// 3000 cells but only ~48 runs, which is the difference between a stall and
  /// nothing at all.
  void _renderValidCells(Canvas canvas, Team team) {
    if (_dropGlowCache == null ||
        _cachedOwnersVersion != deployZone.version ||
        _cachedTeam != team) {
      _dropGlowCache = _buildGlow(team);
      _cachedOwnersVersion = deployZone.version;
      _cachedTeam = team;
    }
    canvas.drawPicture(_dropGlowCache!);
  }

  ui.Picture _buildGlow(Team team) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final cellW = ArenaSpec.worldWidth / ArenaSpec.gridCols;
    final cellH = ArenaSpec.worldHeight / ArenaSpec.gridRows;

    for (var row = 0; row < ArenaSpec.gridRows; row++) {
      var runStart = -1;
      for (var col = 0; col <= ArenaSpec.gridCols; col++) {
        final valid =
            col < ArenaSpec.gridCols &&
            !deployZone.isBlocked(col, row) &&
            deployZone.ownerOf(col, row) == team;

        if (valid && runStart < 0) {
          runStart = col;
        } else if (!valid && runStart >= 0) {
          canvas.drawRect(
            Rect.fromLTWH(
              runStart * cellW,
              row * cellH,
              (col - runStart) * cellW,
              cellH,
            ),
            _glowPaint,
          );
          runStart = -1;
        }
      }
    }
    return recorder.endRecording();
  }

  void _renderGhost(Canvas canvas, DeployPreview preview) {
    final centre = Offset(preview.worldPosition.x, preview.worldPosition.y);
    final colour = preview.valid ? Palette.deployValid : Palette.deployInvalid;

    _ghostFill.color = colour.withValues(alpha: 0.28);
    _ghostEdge.color = colour;

    canvas.drawCircle(centre, preview.radius, _ghostFill);
    canvas.drawCircle(centre, preview.radius, _ghostEdge);

    if (preview.valid) {
      canvas.drawCircle(centre, preview.radius * 0.18, _ghostEdge);
      return;
    }

    // Red X for a refused drop.
    final arm = preview.radius * 0.45;
    canvas.drawLine(
      centre.translate(-arm, -arm),
      centre.translate(arm, arm),
      _crossPaint,
    );
    canvas.drawLine(
      centre.translate(arm, -arm),
      centre.translate(-arm, arm),
      _crossPaint,
    );
  }
}
