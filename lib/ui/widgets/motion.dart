import 'package:flutter/material.dart';

import '../../core/palette.dart';

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
      duration: Motion.of(
        context,
        _down ? Motion.press : Motion.release,
      ),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: Motion.of(
        context,
        _down ? Motion.press : Motion.release,
      ),
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
  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
  });

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
      style: style.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // Lit slightly from the top, like the panels. Kept as a literal
        // pair rather than a token, but it must be re-picked by hand every
        // time the ground changes — a hardcoded cream here is what left every
        // tile floating on a pale wash the first time the palette moved.
        colors: [Color(0xFFF7FAF8), Palette.uiBackground],
      ),
    ),
    // Painted once and cached: the layout above it rebuilds constantly, and
    // there is no reason to re-rasterise a static texture with it.
    child: RepaintBoundary(
      child: CustomPaint(
        painter: const _SplatterPainter(),
        isComplex: true,
        willChange: false,
        child: child,
      ),
    ),
  );
}

/// The page, painted the way the arena is.
///
/// This is the one place the menus are allowed to touch the team colours,
/// and it is what makes the app look like *this* game rather than a generic
/// dark mobile skin. Section 14 keeps red and blue out of chrome — buttons,
/// chips, states — because chrome pointing at a side makes the menus look
/// like they belong to one player. The ground underneath is not chrome. It
/// is the board, and the board is what the whole game is about.
///
/// Red holds the top, blue the bottom, and they meet along a ragged frontier
/// about a third of the way down — the shape a real match leaves behind
/// rather than the ruler-straight 50/50 the whistle starts on. Everything is
/// laid out from a fixed table rather than a random seed, so the pattern is
/// identical on every launch and on every device. A background that
/// reshuffles itself each time the app opens reads as a glitch.
class _SplatterPainter extends CustomPainter {
  const _SplatterPainter();

  /// How strongly the two grounds tint the page.
  ///
  /// Very low, and lower for red than blue: red is the more luminous of the
  /// pair, so matching numbers would put the opponent's half forward. This
  /// has to survive text laid over it at every size, so it is texture you
  /// notice only when you look for it.
  ///
  /// Re-tuned for the light page. The same alpha does not mean the same
  /// thing on a different ground: over near-black these washes were barely
  /// there, and over a pale page they come out as pastel pink and lavender
  /// at once, which is far louder. Both are cut roughly by half.
  static const double _blueWash = 0.07;
  static const double _redWash = 0.05;

  /// The frontier, as fractions of width and height. Deliberately uneven:
  /// a smooth curve reads as a graphic device, and this should read as the
  /// edge of somebody's push.
  static const List<(double, double)> _front = [
    (0.00, 0.30),
    (0.14, 0.335),
    (0.26, 0.30),
    (0.31, 0.365),
    (0.46, 0.345),
    (0.58, 0.395),
    (0.67, 0.35),
    (0.79, 0.375),
    (0.88, 0.325),
    (1.00, 0.355),
  ];

  /// Splats over the top, in the colour of whoever owns that ground.
  /// x, y and radius as fractions, so it scales to any screen.
  static const List<(double, double, double)> _blobs = [
    (0.86, 0.06, 0.26),
    (0.10, 0.20, 0.19),
    (0.72, 0.34, 0.13),
    (-0.04, 0.52, 0.22),
    (0.94, 0.62, 0.20),
    (0.30, 0.78, 0.16),
    (0.78, 0.92, 0.24),
    (0.16, 1.02, 0.18),
  ];

  Path _territory(Size size, {required bool above}) {
    final path = Path();
    path.moveTo(0, above ? 0 : size.height);
    for (final (fx, fy) in _front) {
      path.lineTo(fx * size.width, fy * size.height);
    }
    path.lineTo(size.width, above ? 0 : size.height);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ground = Paint()..isAntiAlias = true;

    ground.color = Palette.red.withValues(alpha: _redWash);
    canvas.drawPath(_territory(size, above: true), ground);

    ground.color = Palette.blue.withValues(alpha: _blueWash);
    canvas.drawPath(_territory(size, above: false), ground);

    final brush = Paint()..isAntiAlias = true;
    final span = size.width;

    for (var i = 0; i < _blobs.length; i++) {
      final (fx, fy, fr) = _blobs[i];
      final centre = Offset(fx * size.width, fy * size.height);
      final radius = fr * span;

      // Painted in whichever side owns the ground it lands on, so a splat
      // near the frontier reads as a push rather than as confetti. Slightly
      // stronger than the wash beneath it, or it disappears into its own
      // half.
      final onBlue = fy > 0.35;
      brush.color = (onBlue ? Palette.blue : Palette.red).withValues(
        alpha: onBlue ? 0.06 : 0.045,
      );

      // A splat is a blob with satellites, not a circle. Three overlapping
      // discs is enough to lose the outline of a perfect circle.
      canvas.drawCircle(centre, radius, brush);
      canvas.drawCircle(
        centre + Offset(radius * 0.72, -radius * 0.48),
        radius * 0.42,
        brush,
      );
      canvas.drawCircle(
        centre + Offset(-radius * 0.55, radius * 0.66),
        radius * 0.3,
        brush,
      );
    }
  }

  @override
  bool shouldRepaint(_SplatterPainter oldDelegate) => false;
}
