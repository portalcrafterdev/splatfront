import 'package:flutter/widgets.dart';

import '../../core/palette.dart';
import '../../game/units/unit_art.dart';

/// A troop's character, drawn as a widget.
///
/// The same [UnitArt] the arena uses, so a card always shows the thing it
/// actually puts on the field — nobody has to keep two sets of art in step.
class UnitArtView extends StatelessWidget {
  const UnitArtView({
    super.key,
    required this.cardId,
    required this.size,
    this.team = Team.blue,
    this.facingCamera = true,
  });

  final String cardId;
  final double size;
  final Team team;

  /// Card art wants the face; the arena decides for itself.
  final bool facingCamera;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    // Clipped, because CustomPaint does not do it and a painter is free to
    // draw anywhere on the canvas it is handed. A character that runs over
    // lands on whatever the tile puts underneath it — which is how the card
    // name ended up printed across the middle of the unit.
    child: ClipRect(
      child: CustomPaint(
        painter: _UnitArtPainter(
          art: artFor(cardId),
          team: team,
          facingCamera: facingCamera,
        ),
      ),
    ),
  );
}

class _UnitArtPainter extends CustomPainter {
  _UnitArtPainter({
    required this.art,
    required this.team,
    required this.facingCamera,
  });

  final UnitArt art;
  final Team team;
  final bool facingCamera;

  /// Height of a character in art units: feet at 1.0, crown near -1.6, plus a
  /// little air so nothing touches the edge of the tile.
  static const double _artHeight = 3.1;

  /// Where the character's **origin** sits down the tile.
  ///
  /// Not where its feet sit. The art has its origin at the character's centre
  /// and stands its feet at y = 1.0, so translating to 0.82 put the feet at
  /// 0.82 + 1.0/3.1 = 1.14 of the tile height — over a tenth of the character
  /// below its own box, printed on top of whatever came next. At 0.55 the
  /// crown lands at 3% down and the shadow at 94%, which is the "little air"
  /// [_artHeight] was reserving in the first place.
  static const double _originY = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final pose = UnitPose()
      ..team = team
      ..facingY = facingCamera ? 1 : -1
      ..facingX = 0
      ..moving = false;

    final scale = size.height / _artHeight;
    canvas.save();
    // Feet a little above the bottom edge, so the shadow has somewhere to sit.
    canvas.translate(size.width / 2, size.height * _originY);
    canvas.scale(scale);
    // The same rim-then-body pair the arena draws, so a card and the unit it
    // deploys are the same picture.
    pose.outlinePass = true;
    art.draw(canvas, pose);
    pose.outlinePass = false;
    art.draw(canvas, pose);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnitArtPainter old) =>
      old.art != art || old.team != team || old.facingCamera != facingCamera;
}
