import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'constants.dart';

/// Prints a frame-time summary to the log while a match is running.
///
/// Section 13 asks for 60fps with forty units on a mid-range device, and the
/// only honest way to know is to measure on one. The on-screen readout in the
/// sandbox is fine when you are holding the phone; this is for when you are
/// reading `adb logcat` instead.
///
/// Off in release builds. It costs a callback per frame and a little
/// arithmetic, which is not something a shipped game should pay for a number
/// nobody will read.
class FrameLog {
  const FrameLog._();

  static bool _running = false;
  static final List<int> _buildUs = <int>[];
  static final List<int> _rasterUs = <int>[];
  static Stopwatch? _since;

  /// How long between summaries.
  static const Duration interval = Duration(seconds: 5);

  /// A frame at 60fps has this long to do everything.
  static const int budgetUs = 16667;

  static void start(String label) {
    if (kReleaseMode || _running) return;
    _running = true;
    _buildUs.clear();
    _rasterUs.clear();
    _since = Stopwatch()..start();
    _label = label;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void stop() {
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _report(); // One last summary, so a short match still reports something.
    _since?.stop();
    _since = null;
  }

  static String _label = '';

  /// A frame this slow is not a dropped frame, it is a stall.
  ///
  /// Android calls an app unresponsive after five seconds without servicing
  /// input and kills it, which players report as a crash rather than as a
  /// freeze. A single frame anywhere near this is the thing to catch, and
  /// waiting for the five-second summary is no good when the summary may
  /// never arrive. Logged the moment it is seen.
  static const int stallUs = 400000; // 0.4s

  static void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      _buildUs.add(build);
      _rasterUs.add(raster);

      if (build > stallUs || raster > stallUs) {
        debugPrint(
          'splatfront.perf STALL  build ${_ms(build)}  raster ${_ms(raster)}'
          '  total ${_ms(timing.totalSpan.inMicroseconds)}',
        );
      }
    }
    if ((_since?.elapsed ?? Duration.zero) >= interval) {
      _report();
      _buildUs.clear();
      _rasterUs.clear();
      _since?.reset();
    }
  }

  static void _report() {
    if (_rasterUs.isEmpty) return;

    final frames = _rasterUs.length;
    final seconds = (_since?.elapsedMilliseconds ?? 1) / 1000;
    final fps = seconds > 0 ? frames / seconds : 0;

    // Raster is where this game spends its time, so it gets the percentiles.
    final sorted = List<int>.from(_rasterUs)..sort();
    final p50 = sorted[sorted.length ~/ 2];
    final p95 = sorted[(sorted.length * 95 ~/ 100).clamp(0, frames - 1)];
    final worst = sorted.last;

    var over = 0;
    for (final us in _rasterUs) {
      if (us > budgetUs) over++;
    }

    final avgBuild =
        _buildUs.fold<int>(0, (a, b) => a + b) / _buildUs.length / 1000;

    // debugPrint rather than dart:developer log: only the former reaches
    // `adb logcat` from a profile build, and reading it over adb is the whole
    // point of having this.
    debugPrint(
      'splatfront.perf $_label  ${fps.toStringAsFixed(1)} fps '
      'over $frames frames  |  '
      'raster p50 ${_ms(p50)} p95 ${_ms(p95)} worst ${_ms(worst)}  |  '
      'build avg ${avgBuild.toStringAsFixed(2)}ms  |  '
      'over budget $over/$frames '
      '(${(over * 100 / frames).toStringAsFixed(1)}%)  |  '
      'target ${PerfBudget.targetFps}fps',
    );
  }

  static String _ms(int microseconds) =>
      '${(microseconds / 1000).toStringAsFixed(2)}ms';
}
