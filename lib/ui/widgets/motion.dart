import 'package:flutter/material.dart';

import '../../core/palette.dart';
import 'match_background.dart';

/// The menu's motion and surface kit.
///
/// Two rules hold everywhere in here, and both matter more than they look:
///
/// **Every animation ends.** Nothing loops, pulses or breathes. A repeating
/// animation keeps scheduling frames forever, and `pumpAndSettle` waits for
/// the frames to stop — one shimmering button would hang every widget test in
/// the suite rather than fail it, which is a much worse afternoon.
///
/// **Motion is feedback, not decoration.** Things move when the player does
/// something or when a number they care about changes. Nothing moves to fill
/// silence, because the second time you see it, it is just latency.
class Motion {
  const Motion._();

  /// A press should read as instant and the release as a settle.
  static const Duration press = Duration(milliseconds: 90);
  static const Duration release = Duration(milliseconds: 220);

  /// How far into a screen's entrance each row starts, per row.
  static const Duration stagger = Duration(milliseconds: 55);

  /// One row's entrance.
  static const Duration entrance = Duration(milliseconds: 380);

  /// A number counting to a new value.
  static const Duration count = Duration(milliseconds: 650);

  /// The duration to actually use, given who is watching.
  ///
  /// Returns [Duration.zero] when the player has asked their device to reduce
  /// motion — an accessibility setting the OS already knows about and that
  /// nothing here was reading. Vestibular disorders are common enough that a
  /// game which ignores the switch is unplayable for some people, and the
  /// cost of honouring it is this function.
  ///
  /// It removes the *movement*, never the information: a counter still lands
  /// on its new value, an entrance still ends with the row on screen. Only
  /// the travel between states goes away.
  static Duration of(BuildContext context, Duration duration) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
      ? Duration.zero
      : duration;
}

/// Scales its child down while held, and springs back on release.
///
/// The whole point is that a tap feels like it landed on the thing under the
/// finger. Wrapping rather than restyling, so it works on any tile.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// How far down it goes. Small on purpose: a big squash on a big panel
  /// reads as the layout breaking rather than as a button.
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down || widget.onTap == null) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => _set(true),
    onTapUp: (_) => _set(false),
    onTapCancel: () => _set(false),
    onTap: widget.onTap,
    // Slides down onto its own shadow as well as scaling: on an outlined
    // tile that reads as the button physically depressing, which a scale
    // alone does not.
    child: AnimatedSlide(
      offset: _down ? const Offset(0, 0.012) : Offset.zero,
      duration: Motion.of(context, _down ? Motion.press : Motion.release),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: Motion.of(context, _down ? Motion.press : Motion.release),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    ),
  );
}

/// Fades and lifts its child in once, [index] rows after the screen appears.
///
/// Runs on first build and never again. A list that re-runs its entrance on
/// every rebuild is a list that flickers every time anything changes.
class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.of(context, Motion.entrance + Motion.stagger * index),
    curve: Interval(
      // The stagger is inside one tween rather than a delayed controller, so
      // there is still exactly one animation to settle.
      (index * 0.09).clamp(0.0, 0.6),
      1,
      curve: Curves.easeOutCubic,
    ),
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    ),
    child: child,
  );
}

/// A number that counts to its new value instead of jumping.
///
/// Coins and trophies are the reward for the last match, and a number that
/// snaps gives that away for free.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // begin only applies on the first build, so the counter runs up from zero
    // when the screen appears and then tracks changes from wherever it is.
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: Motion.of(context, Motion.count),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => Text(
      v.round().toString(),
      // Tabular figures, or the row jitters as the digits change width.
      style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    ),
  );
}

/// The standard menu surface: a light tile, a heavy dark outline and a flat
/// shadow sitting under it.
///
/// The outline is the whole style. A light UI without one is pale rectangles
/// on a pale page, and every edge has to be found rather than seen. The
/// shadow is solid and offset rather than blurred, because a soft shadow
/// under a hard line reads as a rendering mistake rather than as depth.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.accent,
    this.radius = 16,
    this.raised = true,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Fills the tile instead of the neutral surface. The outline stays dark
  /// either way — a coloured tile with a coloured edge loses its shape.
  final Color? accent;
  final double radius;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final fill = accent;
    return Container(
      decoration: BoxDecoration(
        // A vertical gradient, not a flat fill. Lighter at the top puts a
        // light source in the room, so a tile reads as an object lying on the
        // page rather than as a shape cut out of it. Subtle on a light ground
        // — the heavy outline is doing most of the work here — and it was
        // load-bearing on the dark one, where there is no outline to help.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: fill == null
              ? const [Palette.uiSurfaceHigh, Palette.uiSurface]
              : [
                  Color.alphaBlend(Colors.white.withValues(alpha: 0.10), fill),
                  fill,
                ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Palette.outline, width: Panel.stroke),
        boxShadow: raised
            ? const [
                BoxShadow(
                  color: Palette.outlineShadow,
                  offset: Offset(0, Panel.lift),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  /// One outline width for the whole app. Thin enough to keep small tiles
  /// legible, thick enough to be the thing you notice.
  static const double stroke = 2.5;

  /// How far the flat shadow sits below its tile.
  static const double lift = 4;
}

/// The page background: cream, with paint spattered across it.
///
/// A flat cream page is clean and says nothing. This is a game about covering
/// ground in paint, and the menus had no trace of that anywhere on them — the
/// splats are what make the app look like it belongs to the match rather than
/// like a settings screen that happens to sit in front of one.
///
/// Kept very faint and behind everything: it is texture, not decoration, and
/// the moment you notice an individual blob it is too strong.
class MenuBackground extends StatelessWidget {
  const MenuBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // Fills the viewport rather than the content.
      //
      // This used to paint as the *parent* of the page, which meant it sized
      // to whatever the page happened to be — and a page shorter than the
      // screen left a band of flat colour above the bottom bar. A gradient
      // hid that; a sky does not.
      Positioned.fill(
        // Painted once and cached: the layout above it rebuilds constantly,
        // and there is no reason to re-rasterise a static texture with it.
        child: RepaintBoundary(
          child: CustomPaint(
            painter: const _MenuSkyPainter(),
            isComplex: true,
            willChange: false,
          ),
        ),
      ),
      child,
    ],
  );
}

/// The menus stand under the same sky the match is played under.
///
/// Home used to have a ground of its own — the arena seen from above, red
/// holding the top and blue the bottom along a ragged frontier. The argument
/// for it still holds and is section 14's: the board is the thing the whole
/// game is about, and without it a menu is a generic mobile skin. What
/// changed is that the match screen became a bright day, and two different
/// worlds either side of the Battle button is worse than one.
///
/// So the board did not go, it moved outdoors. The sky is the match's, paler,
/// and each side's colour still holds its own end of the page — the opponent
/// above, the player below — only now as weather rather than as paint.
class _MenuSkyPainter extends CustomPainter {
  const _MenuSkyPainter();

  /// Paler than the match sky, and it has to be: there is text over almost
  /// all of this page, and the arena screen's own sky is mostly hidden behind
  /// the board. Here it is the whole page.
  static const Color _high = Color(0xFFAEDFF4);
  static const Color _low = Color(0xFFE6F4F1);

  /// How strongly the two sides tint their ends.
  ///
  /// Lower for red than blue: red is the more luminous of the pair, so
  /// matching numbers would push the opponent's half forward. Both are far
  /// below the old splatter's, because that sat on a flat page and this sits
  /// on a sky that already has a colour of its own.
  static const double _blueWash = 0.05;
  static const double _redWash = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_high, _low],
        ).createShader(rect),
    );

    for (final (colour, wash, from) in [
      (Palette.red, _redWash, const Alignment(0, -1)),
      (Palette.blue, _blueWash, const Alignment(0, 1)),
    ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: from,
            radius: 1.15,
            colors: [
              colour.withValues(alpha: wash),
              colour.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    const CloudPainter(opacity: 0.55).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_MenuSkyPainter oldDelegate) => false;
}
