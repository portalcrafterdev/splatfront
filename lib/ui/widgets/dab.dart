import 'package:flutter/material.dart';

import '../../core/palette.dart';
import 'motion.dart';

/// The guide: a paint blob who says the one thing you can do next.
///
/// **Dab is a card in the deck**, the 2-elixir blob that spawns three of
/// itself, so the mascot is something the player already meets in a match
/// rather than a character invented for the menus.
///
/// **It belongs to no side.** A guide drawn in the player's blue would be
/// chrome pointing at a team, which section 14 rules out — chrome that points
/// at a side makes the menus look like they belong to one player. So Dab is
/// cream with teal cheeks: a blob that has not picked a colour yet, which is
/// also the most honest thing a neutral narrator could look like in a game
/// about claiming ground.
class Dab extends StatelessWidget {
  const Dab({super.key, this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    // CustomPaint does not clip, and the blob's outline stroke rides its
    // edge — half of it falls outside the path.
    child: ClipRect(
      child: CustomPaint(painter: _DabPainter(), isComplex: false),
    ),
  );
}

class _DabPainter extends CustomPainter {
  /// Authored on a 48-unit square and scaled, so the proportions hold at any
  /// size the callers ask for.
  static const double _grid = 48;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _grid);

    final body = Path()
      ..moveTo(24, 4)
      ..cubicTo(33, 4, 41, 11, 41, 20)
      ..cubicTo(41, 26, 38, 29, 38, 34)
      ..cubicTo(38, 40, 33, 44, 24, 44)
      ..cubicTo(15, 44, 10, 40, 10, 34)
      ..cubicTo(10, 29, 7, 26, 7, 20)
      ..cubicTo(7, 11, 15, 4, 24, 4)
      ..close();

    canvas.drawPath(body, Paint()..color = Palette.uiSurfaceHigh);

    // Cheeks go on before the outline, so the stroke sits over them rather
    // than under — otherwise the two teal ovals look stuck on the front.
    final cheek = Paint()..color = Palette.accent.withValues(alpha: 0.42);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(12.5, 28), width: 6.4, height: 4.6),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(35.5, 28), width: 6.4, height: 4.6),
      cheek,
    );

    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..color = Palette.outline,
    );

    final ink = Paint()..color = Palette.outline;
    canvas.drawCircle(const Offset(18, 24), 3.4, ink);
    canvas.drawCircle(const Offset(30, 24), 3.4, ink);

    // A catchlight in each eye. Two dots make a face; two dots with a
    // highlight make a face that is looking at you, and it is four pixels of
    // work.
    final glint = Paint()..color = Palette.uiSurfaceHigh;
    canvas.drawCircle(const Offset(19.2, 22.8), 1.1, glint);
    canvas.drawCircle(const Offset(31.2, 22.8), 1.1, glint);

    canvas.drawPath(
      Path()
        ..moveTo(19, 31)
        ..quadraticBezierTo(24, 34.4, 29, 31),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = Palette.outline,
    );
  }

  @override
  bool shouldRepaint(_DabPainter oldDelegate) => false;
}

/// Dab, with one line in a speech bubble.
///
/// One line, and only ever one. The whole point is that a child who cannot
/// yet read a paragraph can still be told what to do next, so this competes
/// with nothing: if there were two useful things to say, neither would get
/// read.
///
/// Pass the *next action*, never a status. "You have 0 trophies" is a fact;
/// "Tap Battle to paint your first level" is a thing to go and do.
class DabSays extends StatelessWidget {
  const DabSays(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      const Dab(),
      const SizedBox(width: 10),
      Expanded(
        child: Panel(
          radius: 14,
          // Soft, like the rest of Home. Dab keeps its own outline because
          // that is the character's line art rather than a panel edge — a
          // cream blob on a pale page with no line around it is a smudge.
          outlined: false,
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Palette.uiText,
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
            child: Text(text),
          ),
        ),
      ),
    ],
  );
}
