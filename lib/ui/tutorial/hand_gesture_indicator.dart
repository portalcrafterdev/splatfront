import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../core/palette.dart';

/// What the hand is being asked to demonstrate.
enum HandGesture {
  /// A finger comes down on the spot, with a ripple leaving it.
  tap,

  /// A hand presses and glides along a path, with a track showing where it is
  /// going.
  swipe,
}

/// The Lottie file this widget draws, and the two corrections it needs.
///
/// One file for both gestures. It is a tap animation, chosen by the owner
/// from LottieFiles — see `assets/lottie/SOURCE.md` for the link, the author
/// and the licence. It is committed **unmodified**, so swapping it for
/// another is a straight file replacement; everything below adjusts it from
/// Dart instead of editing the JSON.
abstract final class HandAnimations {
  static const String asset = 'assets/lottie/hand_tap.json';

  /// Where the fingertip sits inside the composition, as a fraction of its
  /// own canvas.
  ///
  /// **Measured, not guessed.** The file is 600 x 600 and the fingertip is at
  /// (241.5, 177) — up and to the left of centre, because the hand comes in
  /// from the lower right. Found by rendering the composition to an image and
  /// taking the topmost ink at rest. Centring the canvas on the target, which
  /// is what every coach mark does, would leave the hand pointing about 23dp
  /// low and 11dp right of the thing it is supposed to be indicating.
  static const Offset fingertip = Offset(241.5 / 600, 177 / 600);

  /// How long one pass takes: 41 frames at 25fps.
  ///
  /// Pinned to the file rather than picked. `tutorial_test.dart` asserts the
  /// composition still declares both numbers, so a replacement file that runs
  /// at another speed fails there instead of quietly playing fast or slow.
  static const Duration cycle = Duration(milliseconds: 1640);

  /// Recolours the composition on the way in.
  ///
  /// **Every shape in the file is `#000000`**, which is the right choice for
  /// a hand meant to sit on a white page and the wrong one here: these marks
  /// are drawn over a near-black scrim, so as shipped the hand is invisible.
  ///
  /// Done with delegates rather than by rewriting the JSON so the asset stays
  /// byte-identical to what was downloaded — the licence is easier to honour
  /// when the file is untouched, and the app's colours stay in [Palette]
  /// where the rest of the app can see them.
  ///
  /// The key paths name layers inside somebody else's file, so they are the
  /// one part of this that a swapped animation would break. It fails softly:
  /// an unmatched path recolours nothing rather than throwing, which is why
  /// `tutorial_test.dart` checks the layers are still there by name.
  static LottieDelegates get delegates => LottieDelegates(
    values: [
      // Fills first, and with a wildcard, so no part of the hand is left
      // black whatever the file calls its layers.
      ValueDelegate.color(const ['**'], value: Palette.hudOnScrim),
      // The hand's own outline stays dark, which is this app's shape
      // language: a light fill inside a heavy near-black line.
      ValueDelegate.strokeColor(const [
        'hand_tap_01 Outlines',
        '**',
      ], value: Palette.outlineShadow),
      for (final ring in _ringLayers)
        ValueDelegate.strokeColor([ring, '**'], value: Palette.accent),
    ],
  );

  /// The two expanding rings the tap animation throws off.
  static const List<String> _ringLayers = ['Shape Layer 3', 'Shape Layer 4'];

  /// The same file with the ripples switched off, for the drag step.
  ///
  /// A hand gliding along a path while throwing off tap ripples reads as
  /// somebody jabbing the screen repeatedly, which is the opposite of the
  /// instruction. Hiding two layers is cheaper than a second animation, and
  /// it keeps both steps showing the *same* hand — two different hands in one
  /// three-step sequence looks like a bug.
  static LottieDelegates get delegatesWithoutRipple => LottieDelegates(
    values: [
      ...delegates.values!,
      for (final ring in _ringLayers)
        ValueDelegate.opacity([ring, '**'], value: 0),
    ],
  );

  static LottieDelegates forGesture(HandGesture gesture) => switch (gesture) {
    HandGesture.tap => delegates,
    HandGesture.swipe => delegatesWithoutRipple,
  };
}

/// The animated hand that points at whatever a coach mark has cut out of the
/// scrim.
///
/// **The hand itself is Lottie.** The composition draws the finger, the press
/// and — for [HandGesture.tap] — the ripples leaving it.
///
/// **The travel is not, and cannot be.** A Lottie file bakes its motion in at
/// author time, and [travel] is a runtime value: the battle screen sweeps
/// straight up out of the card tray, the movement pad sweeps sideways, and a
/// future step could go anywhere. So this widget translates the composition
/// along the path and paints the track and arrowhead itself, which stay
/// correct at any angle. Rotating a baked horizontal sweep would have been the
/// alternative, and it lays the hand on its side to point upward.
///
/// **It stops.** The house rule in `CLAUDE.md` section 11 is that every
/// animation in this app ends, and it is not a stylistic preference: a
/// repeating animation keeps scheduling frames forever, `pumpAndSettle` waits
/// for them to stop, so one endlessly looping hand would *hang* the widget
/// suite rather than fail it. That is why the composition is driven by an
/// [AnimationController] this widget owns and re-runs [cycles] times, rather
/// than by Lottie's own `repeat`, which defaults to **true** and would never
/// stop.
///
/// A player who looks away and misses all four cycles is not stranded: the
/// coach mark restarts the hand whenever they tap somewhere it will not
/// accept, which is exactly when they need showing again.
class HandGestureIndicator extends StatefulWidget {
  const HandGestureIndicator({
    super.key,
    this.gesture = HandGesture.tap,
    this.travel = const Offset(120, 0),
    this.cycles = 4,
    this.cycle = HandAnimations.cycle,
    this.handSize = 110,
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

  /// How long one pulse or one glide takes. Defaults to the length the
  /// composition was authored at — see [HandAnimations.cycle] — so it plays
  /// at its intended speed rather than stretched or compressed.
  final Duration cycle;

  /// The rendered size of the composition, which is square.
  final double handSize;

  /// The track under a swipe. The hand's own colours live in the Lottie file.
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

  /// How many full passes have played.
  int _done = 0;

  /// Cleared when the platform asks for reduced motion, in which case the
  /// hand is drawn once in its resting pose and never moves.
  bool _animate = true;

  @override
  void initState() {
    super.initState();
    // One cycle long, re-run by hand. Lottie maps a controller's 0..1 onto
    // the whole composition, so a controller spanning four cycles would play
    // the composition once at quarter speed instead of four times.
    _controller = AnimationController(vsync: this, duration: widget.cycle)
      ..addStatusListener(_onCycleEnd);
  }

  void _onCycleEnd(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _done++;
    final cycles = widget.cycles;
    if (cycles != null && _done >= cycles) return;
    if (!mounted) return;
    _controller!.forward(from: 0);
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
    _controller!.forward();
  }

  @override
  void didUpdateWidget(HandGestureIndicator old) {
    super.didUpdateWidget(old);
    if (widget.cycle != _controller!.duration) {
      _controller!.duration = widget.cycle;
    }
  }

  @override
  void dispose() {
    _controller!.dispose();
    super.dispose();
  }

  /// Where in a single pass we are, 0 to 1.
  ///
  /// Once the run is over this holds at [_restPhase] rather than falling back
  /// to 0, because for a swipe phase 0 is the invisible frame at the start of
  /// the fade-in — the hand would finish by disappearing.
  double get _phase {
    final controller = _controller!;
    if (!_animate) return _restPhase;
    if (controller.isCompleted && _isLastCycle) return _restPhase;
    return controller.value;
  }

  bool get _isLastCycle {
    final cycles = widget.cycles;
    return cycles != null && _done >= cycles;
  }

  double get _restPhase => widget.gesture == HandGesture.swipe ? 0.45 : 0.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) => switch (widget.gesture) {
        HandGesture.tap => _tap(),
        HandGesture.swipe => _swipe(_phase),
      },
    );
  }

  /// The composition, at the frame [_phase] asks for.
  ///
  /// [Lottie.asset] is handed an explicit `controller`, which is what keeps
  /// the composition on this widget's clock rather than on Lottie's own
  /// looping one. `animate: false` is not enough on its own — that only stops
  /// it self-driving; without a controller it would sit on frame 0.
  Widget _composition() {
    // Shift the composition so its fingertip, rather than the middle of its
    // canvas, lands on whatever this widget is centred over.
    final hotspot = HandAnimations.fingertip;
    return Transform.translate(
      offset: Offset(
        (0.5 - hotspot.dx) * widget.handSize,
        (0.5 - hotspot.dy) * widget.handSize,
      ),
      child: _raw(),
    );
  }

  Widget _raw() => Lottie.asset(
    HandAnimations.asset,
    controller: _frame,
    delegates: HandAnimations.forGesture(widget.gesture),
    width: widget.handSize,
    height: widget.handSize,
    fit: BoxFit.contain,
    // A missing or unparsable file must not take the coach mark down with
    // it: the scrim, the hole and the caption still do their job, and a step
    // with no hand on it is a degraded lesson rather than a broken screen.
    errorBuilder: (context, error, stack) {
      debugPrint('Could not draw the gesture hand: $error');
      return SizedBox(width: widget.handSize, height: widget.handSize);
    },
  );

  /// The controller as Lottie wants it — an [Animation] over 0..1 — pinned to
  /// the resting frame once the run is over.
  Animation<double> get _frame => _animate && !_isLastCycle
      ? _controller!
      : AlwaysStoppedAnimation<double>(_restPhase);

  // --- Tap ------------------------------------------------------------------

  /// Nothing around it. The ripples are inside the composition, so the whole
  /// gesture is one file and one clock.
  Widget _tap() => IgnorePointer(child: _composition());

  // --- Swipe ----------------------------------------------------------------

  Widget _swipe(double phase) {
    final travel = widget.travel;
    final box = widget.handSize;
    final eased = Curves.easeInOutCubic.transform(phase);
    final at = Offset.lerp(-travel / 2, travel / 2, eased)!;

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
      child: IgnorePointer(
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(travel.dx.abs() + box, travel.dy.abs() + box),
              painter: _TrackPainter(travel: travel, colour: widget.colour),
            ),
            Transform.translate(
              offset: at,
              child: Opacity(
                opacity: alpha.clamp(0.0, 1.0),
                child: _composition(),
              ),
            ),
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
