import 'package:flutter/widgets.dart';

import '../../core/palette.dart';

/// The sky the match is played under.
///
/// This was a flat near-black, then a dark gradient, and is now a day. A flat
/// dark fill behind a lit board never read as a room the board was sitting
/// in — it read as nothing, a rectangle floating in a void — and no amount of
/// tuning the darkness fixed that, because the problem was that there was
/// nothing there rather than that it was the wrong shade.
///
/// Everything here is **static**. Clouds that drift would be an animation
/// that never ends: `pumpAndSettle` would wait for it forever and hang the
/// widget suite rather than fail it, it would schedule frames behind a game
/// already asking for sixty a second, and by the second match it would be
/// scenery nobody looks at. Painted once, inside a [RepaintBoundary], and the
/// arena never touches it again.
class MatchBackground extends StatelessWidget {
  const MatchBackground({super.key, required this.playerTeam});

  final Team playerTeam;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Palette.hudSkyHigh, Palette.hudSkyLow],
            ),
          ),
        ),
        const CustomPaint(painter: _Clouds()),

        // A breath of each side's colour at the end of the screen that side
        // is fighting from — the opponent's above, yours below.
        //
        // Very low, and far lower than the menus' wash: a sky is already
        // blue, and this is the one screen where blue is also a score. It is
        // there to tint which end is whose, not to be noticed.
        _Bloom(
          colour: Palette.of(playerTeam.opponent),
          from: const Alignment(0, -1.1),
        ),
        _Bloom(colour: Palette.of(playerTeam), from: const Alignment(0, 1.1)),
      ],
    ),
  );
}

/// One side's colour, bled into the air at its end of the screen.
class _Bloom extends StatelessWidget {
  const _Bloom({required this.colour, required this.from});

  final Color colour;
  final Alignment from;

  /// Red is the more luminous of the pair, so an equal wash pushes its half
  /// forward. Keyed to the colour rather than the side, because which side is
  /// red is not fixed.
  double get _alpha => colour == Palette.red ? 0.07 : 0.09;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: from,
        radius: 1.0,
        colors: [
          colour.withValues(alpha: _alpha),
          colour.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

/// Soft cumulus, drawn rather than loaded.
///
/// No asset, for the reason section 13 gives about the hot path: this is one
/// full-screen image that would have to ship at every density and be decoded
/// at launch, and it is a handful of blurred circles. Positions are a fixed
/// table, not a random seed — a background that came out different on every
/// launch would be a bug nobody could reproduce.
class _Clouds extends CustomPainter {
  const _Clouds();

  /// x, y and scale as fractions of the screen.
  ///
  /// Kept off the middle band, which is where the arena sits — a cloud behind
  /// the board is a cloud nobody will ever see — and, more importantly, kept
  /// out of the **top 7%**.
  ///
  /// That strip belongs to the phone. Two clouds used to sit at 2% and 4.5%,
  /// which is exactly where the clock and the signal icons are drawn, and a
  /// white cloud under them is not a readout. It cannot be fixed by choosing
  /// an icon colour either: the ground under the icons changed from blue to
  /// white and back across the width of the bar, so one end or the other was
  /// always lost. Painting a dark bar over the strip fixed the contrast and
  /// looked like a lid on the screen. Moving the clouds costs nothing — the
  /// sky is still sky up there.
  static const List<(double, double, double)> _clouds = [
    (0.16, 0.085, 1.05),
    (0.86, 0.075, 0.8),
    (0.52, 0.125, 0.6),
    (0.05, 0.72, 0.9),
    (0.95, 0.66, 1.05),
    (0.72, 0.83, 0.8),
    (0.22, 0.90, 1.1),
    (0.50, 0.955, 0.7),
  ];

  /// One cloud: offsets and radii of its lobes, relative to its own size.
  static const List<(double, double, double)> _lobes = [
    (-0.85, 0.18, 0.52),
    (-0.30, -0.12, 0.72),
    (0.32, 0.02, 0.60),
    (0.88, 0.24, 0.44),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width * 0.17;
    final soft = Paint()
      ..color = const Color(0xF2FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    // A second, wider and fainter pass under the first, so a cloud has a
    // halo rather than an edge. Two cheap passes beat one expensive shader.
    final haze = Paint()
      ..color = const Color(0x4DFFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    for (final (fx, fy, scale) in _clouds) {
      final centre = Offset(fx * size.width, fy * size.height);
      final r = unit * scale;
      for (final paint in [haze, soft]) {
        for (final (dx, dy, lobe) in _lobes) {
          canvas.drawCircle(centre + Offset(dx * r, dy * r), lobe * r, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Clouds oldDelegate) => false;
}
