import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../type.dart';
import '../widgets/motion.dart';
import 'hand_gesture_indicator.dart';
import 'tutorial_flags.dart';

/// How the hole is cut around a target.
enum CoachMarkShape {
  /// A rounded rectangle, for buttons, tiles and panels.
  rounded,

  /// A pill or circle, for round controls and icon buttons.
  round,
}

/// What moves a step on.
enum CoachMarkAdvance {
  /// The player has to do the thing. Everything except the target is blocked,
  /// and the screen reports the action back through
  /// [TutorialController.report].
  target,

  /// The step is pointing something out rather than asking for anything, so a
  /// tap anywhere moves on.
  ///
  /// For the things a player is told about but cannot press — a score bar, a
  /// clock, a meter that fills on its own. Without this they could only be
  /// explained by a step that waits forever for an interaction the widget
  /// does not offer.
  anywhere,
}

/// One step of a coach-mark sequence: what to light up, what to say about it,
/// and which hand to draw over it.
@immutable
class CoachMarkStep {
  const CoachMarkStep({
    required this.id,
    required this.target,
    required this.message,
    this.title,
    this.gesture = HandGesture.tap,
    this.travel = const Offset(120, 0),
    this.shape = CoachMarkShape.rounded,
    this.padding = const EdgeInsets.all(10),
    this.advanceOn = CoachMarkAdvance.target,
  });

  final CoachMarkAdvance advanceOn;

  /// What the screen reports back when the player actually does the thing.
  /// The step only advances on its own id, so a stray report from a control
  /// that is not the current target is ignored rather than skipping ahead.
  final String id;

  /// The widget to cut out of the scrim. The key has to be on something that
  /// is laid out — a key on a widget behind an `Offstage` or in an unbuilt
  /// sliver measures as nothing and the step will dim the whole screen.
  final GlobalKey target;

  final String? title;
  final String message;

  final HandGesture gesture;

  /// For [HandGesture.swipe], the direction and distance the hand travels.
  final Offset travel;

  final CoachMarkShape shape;

  /// Breathing room between the target's own edge and the hole, so a button
  /// does not sit flush against the dark.
  final EdgeInsets padding;
}

/// Runs a sequence of [CoachMarkStep]s over whatever screen is on top.
///
/// The controller owns an `OverlayEntry` and nothing else. It does not wrap
/// the screen, intercept its gestures or re-plumb its callbacks: the real
/// Attack button keeps its real `onTap`, and the screen tells the tutorial
/// what happened by calling [report]. That is the whole integration surface,
/// and it is deliberate — a tutorial that swallows and re-emits taps is a
/// tutorial that can leave a control dead after it finishes.
///
/// Typical use:
///
/// ```dart
/// final _tutorial = TutorialController(id: 'combat_basics');
///
/// // after the first frame, so the targets have been laid out:
/// await _tutorial.startIfUnseen(context, steps: _steps);
///
/// // in the button's own handler, after it has done its job:
/// void _attack() {
///   setState(() => _enemyHp -= 18);
///   _tutorial.report('attack');
/// }
/// ```
class TutorialController extends ChangeNotifier {
  TutorialController({required this.id});

  /// Identifies this sequence in [TutorialFlags]. One flag per sequence.
  final String id;

  List<CoachMarkStep> _steps = const [];
  int _index = 0;
  OverlayEntry? _entry;
  VoidCallback? _onFinished;

  /// Bumped whenever the player taps somewhere the sequence will not accept.
  /// The overlay keys the hand on it, so a wrong tap remounts and replays the
  /// animation — which is the moment somebody most needs showing again.
  int _nudges = 0;
  int get nudges => _nudges;

  bool get isRunning => _entry != null;

  CoachMarkStep? get current =>
      isRunning && _index < _steps.length ? _steps[_index] : null;

  /// 1-based, for "2 of 3".
  int get stepNumber => _index + 1;
  int get stepCount => _steps.length;

  /// Starts the sequence only if this device has not finished it before.
  ///
  /// Returns whether it started. Call it after the first frame — the targets
  /// have to exist and be laid out before there is anything to cut a hole
  /// around.
  Future<bool> startIfUnseen(
    BuildContext context, {
    required List<CoachMarkStep> steps,
    VoidCallback? onFinished,
  }) async {
    if (await TutorialFlags.isDone(id)) return false;
    if (!context.mounted) return false;
    start(context, steps: steps, onFinished: onFinished);
    return true;
  }

  /// Starts the sequence regardless of whether it has been seen. This is what
  /// "Replay tutorial" calls.
  void start(
    BuildContext context, {
    required List<CoachMarkStep> steps,
    VoidCallback? onFinished,
  }) {
    assert(steps.isNotEmpty, 'a coach-mark sequence needs at least one step');
    if (isRunning) cancel();
    _steps = steps;
    _index = 0;
    _nudges = 0;
    _onFinished = onFinished;
    // rootOverlay, so the marks sit above anything the screen itself has
    // pushed — a bottom sheet, a dialog, the navigator's own routes.
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(builder: (_) => _CoachMarkOverlay(controller: this));
    overlay.insert(_entry!);
    notifyListeners();
  }

  /// Tells the sequence that the player did [stepId].
  ///
  /// A report for anything other than the current step is ignored, so the
  /// screen can call this unconditionally from every action's handler without
  /// having to know whether a tutorial is running.
  void report(String stepId) {
    if (current?.id != stepId) return;
    _index++;
    if (_index >= _steps.length) {
      finish();
      return;
    }
    notifyListeners();
  }

  /// Called by the overlay when a tap lands on the blocked part of the
  /// screen. Nothing advances; the hand replays.
  void bumpNudge() {
    if (!isRunning) return;
    _nudges++;
    notifyListeners();
  }

  /// Ends the sequence and remembers that it was completed.
  void finish() {
    if (!isRunning) return;
    _teardown();
    // Fire and forget: the write is swallowed if it fails, and the sequence
    // has already ended on screen either way.
    unawaited(TutorialFlags.setDone(id, value: true));
    final done = _onFinished;
    _onFinished = null;
    notifyListeners();
    done?.call();
  }

  /// Ends the sequence *without* remembering it, so it is offered again.
  void cancel() {
    if (!isRunning) return;
    _teardown();
    _onFinished = null;
    notifyListeners();
  }

  void _teardown() {
    _entry?.remove();
    _entry = null;
    _steps = const [];
    _index = 0;
  }

  @override
  void dispose() {
    // An overlay entry outliving its controller would be an undismissable
    // black screen, which is the worst bug this file could have.
    _entry?.remove();
    _entry = null;
    super.dispose();
  }
}

class _CoachMarkOverlay extends StatefulWidget {
  const _CoachMarkOverlay({required this.controller});

  final TutorialController controller;

  @override
  State<_CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<_CoachMarkOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _fade;

  /// The hole, in this overlay's coordinates. Null until the first frame has
  /// been laid out, which is the one frame where the screen dims flat.
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: Motion.entrance)
      ..forward();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onStep);
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStep);
    WidgetsBinding.instance.removeObserver(this);
    _fade!.dispose();
    super.dispose();
  }

  /// A rotation or a keyboard moves every target on the screen.
  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
  }

  void _onStep() {
    if (!mounted) return;
    // Measured synchronously rather than on the next frame. This listener
    // runs from the button's own handler, between frames, when last frame's
    // layout is still valid and the next step's target is already placed —
    // so the hole moves in the same frame as the step, with no flash of the
    // old target still lit.
    setState(() => _hole = _measure());
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
  }

  void _remeasure() {
    if (!mounted) return;
    final found = _measure();
    if (found == _hole) return;
    setState(() => _hole = found);
  }

  Rect? _measure() {
    final step = widget.controller.current;
    if (step == null) return null;
    final target = step.target.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (target is! RenderBox || !target.hasSize) return null;
    if (self is! RenderBox || !self.hasSize) return null;
    final topLeft = target.localToGlobal(Offset.zero, ancestor: self);
    return step.padding.inflateRect(topLeft & target.size);
  }

  double _holeRadius(Rect hole, CoachMarkShape shape) => switch (shape) {
    CoachMarkShape.round => hole.shortestSide / 2,
    CoachMarkShape.rounded => 18,
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final step = controller.current;
    if (step == null) return const SizedBox.shrink();

    final hole = _hole;
    final screen = MediaQuery.sizeOf(context);
    final radius = hole == null ? 0.0 : _holeRadius(hole, step.shape);

    return AnimatedBuilder(
      animation: _fade!,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_fade!.value);
        return Stack(
          children: [
            // The dim, with the target punched out of it. Never hit-tested —
            // the blockers below are what actually stop taps, so a painter
            // that happens to cover the hole cannot swallow the one tap the
            // player is being asked for.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ScrimPainter(
                    hole: hole,
                    radius: radius,
                    progress: t,
                  ),
                ),
              ),
            ),
            // A step that only points something out takes a tap anywhere,
            // the target included — it is explaining a thing, not asking for
            // it, and a hole you must press to get past a sentence about the
            // score bar is a puzzle rather than a tutorial.
            if (step.advanceOn == CoachMarkAdvance.anywhere)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => controller.report(step.id),
                ),
              )
            // Otherwise everything except the target absorbs taps.
            else if (hole != null)
              ..._blockers(screen, hole, controller.bumpNudge)
            else
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.bumpNudge,
                ),
              ),
            // No hand on a "tap anywhere" step: a finger jabbing at the score
            // bar while the caption says to tap anywhere points the player at
            // the one place the instruction does not mean.
            if (hole != null && step.advanceOn == CoachMarkAdvance.target)
              _hand(step, hole, t, controller.nudges),
            if (hole != null) _caption(step, hole, screen, t, controller),
          ],
        );
      },
    );
  }

  /// Four rectangles around the hole, each swallowing taps.
  ///
  /// Four rather than one full-screen absorber with a hole in it, because
  /// there is no way to let a tap fall *through* a widget that is painted on
  /// top of the thing it should reach. Leaving the hole genuinely empty is
  /// what lets the real button underneath receive the real tap, with its real
  /// splash and its real handler.
  List<Widget> _blockers(Size screen, Rect hole, VoidCallback onBlocked) {
    final top = hole.top.clamp(0.0, screen.height);
    final bottom = hole.bottom.clamp(0.0, screen.height);
    final left = hole.left.clamp(0.0, screen.width);
    final right = hole.right.clamp(0.0, screen.width);

    Widget block({
      required double l,
      required double t,
      required double w,
      required double h,
    }) => Positioned(
      left: l,
      top: t,
      width: math.max(0, w),
      height: math.max(0, h),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onBlocked,
        child: const SizedBox.expand(),
      ),
    );

    return [
      block(l: 0, t: 0, w: screen.width, h: top),
      block(l: 0, t: bottom, w: screen.width, h: screen.height - bottom),
      block(l: 0, t: top, w: left, h: bottom - top),
      block(l: right, t: top, w: screen.width - right, h: bottom - top),
    ];
  }

  Widget _hand(CoachMarkStep step, Rect hole, double t, int nudges) {
    // Keyed on the nudge count so a rejected tap remounts the indicator and
    // replays it from the top.
    final indicator = HandGestureIndicator(
      key: ValueKey('${step.id}-$nudges'),
      gesture: step.gesture,
      travel: step.travel,
    );
    return Positioned(
      left: hole.center.dx - 140,
      top: hole.center.dy - 140,
      width: 280,
      height: 280,
      child: IgnorePointer(
        child: Opacity(
          opacity: t,
          child: Center(child: indicator),
        ),
      ),
    );
  }

  Widget _caption(
    CoachMarkStep step,
    Rect hole,
    Size screen,
    double t,
    TutorialController controller,
  ) {
    // Whichever side of the target has more room, so the caption never
    // covers the thing it is talking about and never runs off the top for a
    // target sitting in the middle of the screen.
    final spaceAbove = hole.top;
    final spaceBelow = screen.height - hole.bottom;
    final below = spaceBelow >= spaceAbove;
    // Ideally clear of the hand, which reaches about 60dp past the hole. Give
    // that up rather than the caption when the gap is tight: 130dp is kept
    // back for the panel itself.
    final clearance = math.min(
      76.0,
      math.max(16.0, (below ? spaceBelow : spaceAbove) - 130),
    );

    final panel = Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (below ? -12 : 12) * (1 - t)),
        child: Panel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (step.title != null)
                    Expanded(
                      child: Text(
                        step.title!,
                        style: Fonts.shout(size: 19, colour: Palette.uiText),
                      ),
                    )
                  else
                    const Spacer(),
                  if (controller.stepCount > 1)
                    Text(
                      '${controller.stepNumber} of ${controller.stepCount}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Palette.uiTextDim,
                      ),
                    ),
                ],
              ),
              if (step.title != null) const SizedBox(height: 4),
              Text(
                step.message,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: Palette.uiText,
                ),
              ),
              if (step.advanceOn == CoachMarkAdvance.anywhere) ...[
                const SizedBox(height: 8),
                const Text(
                  'Tap to carry on',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Palette.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Positioned(
      left: 16,
      right: 16,
      top: below ? hole.bottom + clearance : null,
      bottom: below ? null : screen.height - hole.top + clearance,
      child: IgnorePointer(child: panel),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({
    required this.hole,
    required this.radius,
    required this.progress,
  });

  final Rect? hole;
  final double radius;
  final double progress;

  /// Near-black, matching the countdown and result scrims in the arena.
  /// `CLAUDE.md` section 14: a scrim dims a lit thing rather than sitting
  /// beside it, and it stays dark whatever the page underneath is doing.
  static const Color _ink = Palette.outlineShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = _ink.withValues(alpha: 0.74 * progress);
    final full = Offset.zero & size;
    final cut = hole;
    if (cut == null) {
      canvas.drawRect(full, dim);
      return;
    }

    final rrect = RRect.fromRectAndRadius(cut, Radius.circular(radius));
    // `clipRRect` has no difference operation — only `clipRect` does — so the
    // hole is subtracted from the dim as a path instead. One fill, no save
    // layer, and the rounded corners come out right.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRRect(rrect),
      ),
      dim,
    );

    // A ring on the hole's edge. Without it a cut-out reads as the dim having
    // failed to cover something, rather than as a deliberate spotlight.
    canvas.drawRRect(
      rrect.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Palette.accent.withValues(alpha: progress),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.radius != radius || old.progress != progress;
}
