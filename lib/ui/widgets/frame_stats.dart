import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/palette.dart';

/// Live frame-time readout for the debug sandboxes.
///
/// Android's `dumpsys gfxinfo` cannot measure a Flutter app — Flutter draws to
/// its own surface and never goes through HWUI, so gfxinfo reports zero frames.
/// The engine's own [FrameTiming] stream is the real source, and it separates
/// the two halves that matter: **build** (Dart UI work, where game logic and
/// widget rebuilds land) and **raster** (GPU work, where the paint layer and
/// all the unit draws land).
///
/// The budget from section 13 is 60fps, so a frame has 16.7 ms for both.
class FrameStats extends StatefulWidget {
  const FrameStats({super.key, this.window = 60});

  /// How many recent frames to average over.
  final int window;

  @override
  State<FrameStats> createState() => _FrameStatsState();
}

class _FrameStatsState extends State<FrameStats> {
  static const double _budgetMs = 1000 / 60;

  final List<FrameTiming> _recent = <FrameTiming>[];
  Duration _lastPublish = Duration.zero;

  double _fps = 0;
  double _build = 0;
  double _raster = 0;
  double _worst = 0;
  int _overBudget = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    _recent.addAll(timings);
    if (_recent.length > widget.window) {
      _recent.removeRange(0, _recent.length - widget.window);
    }

    // Republish about four times a second: often enough to be live, rarely
    // enough that the readout is not itself a source of jank.
    final now = Duration(
      microseconds: timings.last.timestampInMicroseconds(
        FramePhase.rasterFinish,
      ),
    );
    if (now - _lastPublish < const Duration(milliseconds: 250)) return;
    _lastPublish = now;

    var build = 0.0;
    var raster = 0.0;
    var worst = 0.0;
    var over = 0;

    for (final t in _recent) {
      final b = t.buildDuration.inMicroseconds / 1000;
      final r = t.rasterDuration.inMicroseconds / 1000;
      final total = t.totalSpan.inMicroseconds / 1000;
      build += b;
      raster += r;
      if (total > worst) worst = total;
      if (total > _budgetMs) over++;
    }

    final count = _recent.length;
    if (count == 0 || !mounted) return;

    setState(() {
      _build = build / count;
      _raster = raster / count;
      _worst = worst;
      _overBudget = over;
      final frame = (build + raster) / count;
      _fps = frame > 0 ? (1000 / frame).clamp(0, 120) : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final healthy = _overBudget == 0;
    return DefaultTextStyle(
      style: TextStyle(
        color: healthy ? Palette.success : Palette.danger,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      child: Text(
        '${_fps.toStringAsFixed(0)} fps  '
        'build ${_build.toStringAsFixed(1)}  '
        'raster ${_raster.toStringAsFixed(1)}  '
        'worst ${_worst.toStringAsFixed(0)}ms  '
        'over $_overBudget/${_recent.length}',
      ),
    );
  }
}
