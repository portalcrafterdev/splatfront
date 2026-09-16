import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// What the hand is being asked to demonstrate.
enum HandGesture {
  /// A finger comes down on the spot, with a ripple leaving it.
  tap,

  /// A hand glides along a path, with a track showing where it is going.
  swipe,
}

/// The animated hand that points at whatever a coach mark has cut out of the
/// scrim.
///
/// **It stops.** The house rule in `CLAUDE.md` section 11 is that every
/// animation in this app ends, and it is not a stylistic preference: a
/// repeating animation keeps scheduling frames forever, `pumpAndSettle` waits
/// for them to stop, so one endlessly pulsing hand would *hang* the widget
/// suite rather than fail it. So the hand runs [cycles] times and then rests
/// in a pose that still reads — the finger still on the spot for [tap], the
/// hand mid-path for [swipe]. Attention is drawn, and nothing is left
/// spinning.
///
/// A player who looks away and misses all four cycles is not stranded: the
/// coach mark restarts the hand whenever they tap somewhere it will not
/// accept, which is exactly when they need showing again.
///
/// Set [cycles] to null for a genuine loop. Nothing in the app does, and a
/// widget test that pumps and settles one will never return.
class HandGestureIndicator extends StatefulWidget {
  const HandGestureIndicator({
    super.key,
    this.gesture = HandGesture.tap,
    this.travel = const Offset(120, 0),
    this.cycles = 4,
    this.cycle = const Duration(milliseconds: 1200),
    this.handSize = 44,
    this.colour = Palette.accent,
  }) : assert(cycles == null || cycles > 0, 'cycles must be positive or null');

  final HandGesture gesture;

  /// For [HandGesture.swipe], how far and in which direction the hand
  /// travels. The path is centred on the widget, so the hand crosses the
  /// middle rather than starting there.
  final Offset travel;

  /// How many times to run before resting. Null loops forever — see the class
  /// doc for why nothing in this app passes that.
  final int? cycles;

  /// How long one pulse or one glide takes.
  final Duration cycle;

  final double handSize;

  /// The ripple and the track. The hand itself is always the light on-scrim
  /// colour, because it is always drawn over a dimmed screen.
  final Color colour;

  @override
  State<HandGestureIndicator> createState() => _HandGestureIndicatorState();
}

class _HandGestureIndicatorState extends State<HandGestureIndicator>
    with SingleTickerProviderStateMixin {
  // Built eagerly rather than `late final`. A lazily-built controller first
  // touched in dispose() gets constructed mid-unmount and throws on the
  // ancestor lookup — a trap this codebase has already paid for once.
  AnimationController? _controller;
  bool _started = false;

  /// Cleared when the platform asks for reduced motion, in which case the
  /// hand is drawn once in its resting pose and never moves.
  bool _animate = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);
  }

  Duration get _total {
    final cycles = widget.cycles;
    return cycles == null ? widget.cycle : widget.cycle * cycles;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is not readable in initState, so the reduced-motion check
    // and the actual start both live here, guarded to run once.
    if (_started) return;
    _started = true;
    _animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (!_animate) return;
    if (widget.cycles == null) {
      _controller!.repeat();
    } else {
      _controller!.forward();
    }
  }

  @override
  void didUpdateWidget(HandGestureIndicator old) {
    super.didUpdateWidget(old);
    if (_total != _controller!.duration) {
      _controller!.duration = _total;
    }
  }

  @override
  void dispose() {
    _controller!.dispose();
    super.dispose();
  }

  /// Where in a single pulse or glide we are, 0 to 1.
  ///
  /// Once the run is over this holds at [_restPhase] rather than falling back
  /// to 0, because for a swipe phase 0 is the invisible frame at the start of
  /// the fade-in — the hand would finish by disappearing.
  double get _phase {
    final controller = _controller!;
    if (!_animate || controller.isCompleted) return _restPhase;
    final cycles = widget.cycles;
    if (cycles == null) return controller.value;
    return (controller.value * cycles) % 1.0;
  }

  double get _restPhase =>
      widget.gesture == HandGesture.swipe ? 0.45 : 0.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) => switch (widget.gesture) {
        HandGesture.tap => _tap(_phase),
        HandGesture.swipe => _swipe(_phase),
      },
    );
  }

  // --- Tap ------------------------------------------------------------------

  Widget _tap(double phase) {
    final box = widget.handSize * 2.6;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Two rings, half a cycle apart, so the spot never goes completely
          // quiet between pulses.
          _ripple(phase, box),
          _ripple((phase + 0.5) % 1.0, box),
          // The finger presses down on the first third of the pulse and comes
          // back up on the second, which is what makes it read as a tap
          // rather than as a hand hovering over a target.
          Transform.translate(
            offset: Offset(0, _dip(phase)),
            child: _hand(),
          ),
        ],
      ),
    );
  }

  Widget _ripple(double t, double box) {
    final small = widget.handSize * 0.55;
    final size = small + (box - small) * Curves.easeOut.transform(t);
    final alpha = (1 - t) * 0.6;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.colour.withValues(alpha: alpha),
            width: 3,
          ),
        ),
      ),
    );
  }

  /// How far the fingertip has pushed into the screen, in logical pixels.
  double _dip(double t) {
    const depth = 5.0;
    if (t < 0.18) return depth * Curves.easeOut.transform(t / 0.18);
    if (t < 0.42) return depth * (1 - Curves.easeIn.transform((t - 0.18) / 0.24));
    return 0;
  }

  // --- Swipe ----------------------------------------------------------------

  Widget _swipe(double phase) {
    final box = widget.handSize * 2.0;
    final travel = widget.travel;
    final eased = Curves.easeInOutCubic.transform(phase);
    final from = -travel / 2;
    final at = Offset.lerp(from, travel / 2, eased)!;

    // Fade in at the start of the glide and out at the end, so the hand does
    // not teleport back to the beginning of the path between cycles.
    final double alpha;
    if (phase < 0.12) {
      alpha = phase / 0.12;
    } else if (phase > 0.86) {
      alpha = (1 - phase) / 0.14;
    } else {
      alpha = 1;
    }

    return SizedBox(
      width: travel.dx.abs() + box,
      height: travel.dy.abs() + box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: Size(travel.dx.abs() + box, travel.dy.abs() + box),
              painter: _TrackPainter(travel: travel, colour: widget.colour),
            ),
          ),
          Transform.translate(
            offset: at,
            child: Opacity(opacity: alpha.clamp(0.0, 1.0), child: _hand()),
          ),
        ],
      ),
    );
  }

  // --- The hand itself ------------------------------------------------------

  /// The glyph's fingertip sits up and to the left of its own centre, so the
  /// icon is nudged the other way to put the tip on the point being indicated
  /// rather than the middle of the wrist.
  Widget _hand() {
    final size = widget.handSize;
    return IgnorePointer(
      child: Transform.translate(
        offset: Offset(size * 0.20, size * 0.24),
        child: Icon(
          Icons.touch_app_rounded,
          size: size,
          color: Palette.hudOnScrim,
          shadows: const [
            // A hard-ish dark shadow rather than a glow: the hand has to stay
            // legible over the one thing that is *not* dimmed, which is the
            // lit target underneath it.
            Shadow(color: Palette.outlineShadow, blurRadius: 6, offset: Offset(0, 2)),
            Shadow(color: Palette.outlineShadow, blurRadius: 2),
          ],
        ),
      ),
    );
  }
}

/// The line the hand is about to travel down, with a head on the far end.
class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.travel, required this.colour});

  final Offset travel;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (travel == Offset.zero) return;
    final centre = Offset(size.width / 2, size.height / 2);
    final from = centre - travel / 2;
    final to = centre + travel / 2;

    final line = Paint()
      ..color = colour.withValues(alpha: 0.45)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, line);

    // An arrowhead, so a horizontal track cannot be read backwards.
    final angle = math.atan2(travel.dy, travel.dx);
    const headLength = 13.0;
    const spread = 0.5;
    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - headLength * math.cos(angle - spread),
        to.dy - headLength * math.sin(angle - spread),
      )
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - headLength * math.cos(angle + spread),
        to.dy - headLength * math.sin(angle + spread),
      );
    canvas.drawPath(head, line);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.travel != travel || old.colour != colour;
}
