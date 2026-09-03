import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../core/palette.dart';

/// How a troop looks on the field.
///
/// The design spec puts unit animation on Rive state machines, and it will
/// not call a unit done without idle/walk/attack/die artboards. Nothing here
/// changes that plan: these are hand-drawn vector characters standing in
/// until the `.riv` files exist, and they sit behind exactly the seam a Rive
/// artboard will occupy. Moving one troop over to Rive later means replacing
/// its entry in [unitArt] — [Unit] itself does not change.
///
/// Everything is authored in a normalised space: the origin is the unit's
/// centre and 1.0 is its collision radius, so the caller scales and the
/// shapes here never mention world units. Feet rest on y = 1.0 and heads
/// reach about y = -1.6, which makes a character roughly two and a half
/// radii tall and gives it a silhouette instead of an outline.
///
/// The characters do not rotate. They stand upright and face the way they
/// walk — eyes toward the camera coming down the screen, the back of the head
/// going up. A top-down silhouette is unreadable at the 40 px these are drawn
/// at; an upright one is not.
abstract class UnitArt {
  const UnitArt();

  void draw(Canvas canvas, UnitPose pose);
}

/// Everything the art needs to know about a unit this frame.
///
/// One instance is reused for every unit on the field: `render` runs
/// sequentially on one thread, and forty of these a frame would be forty
/// allocations a frame for nothing.
class UnitPose {
  UnitPose();

  /// Radians of walk cycle, advancing while the unit moves.
  double walk = 0;

  /// Radians of idle breathing, advancing on the clock whether the unit is
  /// moving or not. A troop waiting for something to fight should still look
  /// alive.
  double breath = 0;

  /// 1 the moment a swing fires, decaying to 0. Drives the lunge and any
  /// muzzle or brush follow-through.
  double attack = 0;

  /// Unit facing, roughly normalised. Positive y is down the screen, toward
  /// the camera, which is when the face is visible.
  double facingX = 0;
  double facingY = 1;

  bool moving = false;

  /// Fades the whole character out as it dies.
  double alpha = 1;

  /// True on the first of the two passes that draw a character.
  ///
  /// A unit stands on ground it has just painted its own colour, so a body in
  /// the team colour is invisible against it. The fix is a sticker outline:
  /// the whole character is drawn once in a fat pale stroke, then again
  /// normally on top, leaving a cream rim around every shape. Painters do not
  /// need to know — [solid] and [line] both hand back the outline brush while
  /// this is set.
  bool outlinePass = false;

  /// True on an optional third pass that whites the character out.
  ///
  /// Drawn over the finished body at [flash] opacity for the tenth of a
  /// second after a unit is hit. Reusing the same painters means a new
  /// character gets its hit flash for free.
  bool flashPass = false;

  /// How hard to white it out, 0 to 1.
  double flash = 0;

  Team _team = Team.red;
  _Shades _shades = _shadesFor(Team.red);

  Team get team => _team;
  set team(Team value) {
    if (value == _team) return;
    _team = value;
    _shades = _shadesFor(value);
  }

  /// The team colour: the body.
  Color get body => _shades.body;

  /// A deep shade of it: limbs, outlines, pupils.
  Color get dark => _shades.dark;

  /// A pale tint: eyes and highlights.
  Color get light => _shades.light;

  /// Neutral grey-brown for equipment, so a roller drum or a cannon reads as
  /// a tool rather than as more paint.
  Color get tool => _shades.tool;

  /// A fill brush in [colour], already faded if the unit is dying.
  Paint solid(Color colour) {
    if (outlinePass) return _outlineBrush();
    if (flashPass) return _fill..color = _flashInk();
    return _fill..color = _faded(colour);
  }

  /// A round-capped stroke brush in [colour] at [width].
  Paint line(Color colour, double width) {
    if (outlinePass) return _outlineBrush(width);
    return _stroke
      ..color = flashPass ? _flashInk() : _faded(colour)
      ..strokeWidth = width;
  }

  Color _flashInk() =>
      const Color(0xFFFFFFFF).withValues(alpha: flash.clamp(0.0, 1.0) * alpha);

  /// The fat pale stroke of the outline pass. Half of it ends up under the
  /// real character, so the visible rim is half [_outlineWidth] wide.
  Paint _outlineBrush([double over = 0]) => _stroke
    ..color = _faded(_outlineInk)
    ..strokeWidth = _outlineWidth + over;

  Color _faded(Color colour) =>
      alpha >= 1 ? colour : colour.withValues(alpha: colour.a * alpha);
}

/// The rim colour and its total stroke width, in art units.
///
/// Kept narrow on purpose. Half of the stroke lands inside the shape it is
/// rimming, and a body is only about a radius across — too wide a rim and
/// every character turns into a white blob with no team colour left in it.
const Color _outlineInk = Color(0xFFFFF3E0);
const double _outlineWidth = 0.20;

/// Shared brushes. A [Paint] per unit per frame would be 2400 objects a
/// second at the forty-unit budget, so every painter reuses these two.
final Paint _fill = Paint()..isAntiAlias = true;
final Paint _stroke = Paint()
  ..isAntiAlias = true
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

const Color _shadowInk = Color(0x33000000);

class _Shades {
  const _Shades(this.body, this.dark, this.light, this.tool);
  final Color body;
  final Color dark;
  final Color light;
  final Color tool;
}

final Map<Team, _Shades> _shadeCache = <Team, _Shades>{};

_Shades _shadesFor(Team team) => _shadeCache.putIfAbsent(team, () {
  final hsl = HSLColor.fromColor(Palette.of(team));

  // Not the paint colour exactly: a unit spends most of its life standing on
  // ground it has just painted its own colour, and a body that matches that
  // ground pixel for pixel disappears into it.
  //
  // Which way to move depends on the paint. Darkening works against a bright
  // colour, but dark blue already sits at 37% lightness, and taking a further
  // bite out of that leaves a body indistinguishable from its own shadow. So
  // step *away* from the paint: down from a light colour, up from a dark one.
  // Either way the body separates from the ground and still reads as the team.
  final away = hsl.lightness < 0.45 ? 1.0 : -1.0;
  Color shift(HSLColor from, double delta) =>
      from.withLightness((from.lightness + delta).clamp(0.08, 0.92)).toColor();

  final body = shift(hsl, away * 0.11);

  return _Shades(
    body,
    // The underside is darker than the body whichever way the body went, or
    // the character reads as lit from underneath.
    shift(HSLColor.fromColor(body), -0.17),
    const Color(0xFFFFF7EC),
    const Color(0xFF4A423B),
  );
});

// --- Shared rig ----------------------------------------------------------

/// The ground line every character stands on.
const double _footY = 1.0;

/// Vertical bounce of a body. Two dips per stride while walking, since both
/// feet land in one cycle; a slow breath while standing, so an idle unit is
/// never a still image.
double _bob(UnitPose p) =>
    p.moving ? -math.sin(p.walk * 2).abs() * 0.07 : math.sin(p.breath) * 0.035;

/// Squash and stretch, as a (horizontal, vertical) scale pair.
///
/// A walking body widens as it lands and narrows as it lifts. It is a small
/// number — 4% — but it is most of the difference between a character that
/// walks and a drawing being slid across the floor.
void _squash(Canvas c, UnitPose p, {double amount = 0.04}) {
  final phase = p.moving ? math.sin(p.walk * 2) : math.sin(p.breath) * 0.4;
  final sx = 1 + phase * amount;
  // Feet stay planted: scaling about the centre would slide them.
  c.translate(0, _footY);
  c.scale(sx, 1 / sx);
  c.translate(0, -_footY);
}

/// A soft shade across the lower half of a round body.
///
/// Cheap volume: one darker arc turns a flat disc into something with a lit
/// side. Skipped on the outline and flash passes, which want flat shapes.
void _underShade(Canvas c, UnitPose p, Offset centre, double radius) {
  if (p.outlinePass || p.flashPass) return;
  c.save();
  c.clipRect(
    Rect.fromLTRB(
      centre.dx - radius,
      centre.dy + radius * 0.15,
      centre.dx + radius,
      centre.dy + radius,
    ),
  );
  c.drawCircle(centre, radius, p.solid(p.dark.withValues(alpha: 0.28)));
  c.restore();
}

/// How far through a swing the unit is: 0 at rest, 1 at the extreme.
double _swing(UnitPose p) => math.sin(p.attack * math.pi);

/// Which side props are held on. Facing straight up or down, the right.
double _side(UnitPose p) => p.facingX >= 0 ? 1.0 : -1.0;

void _shadow(Canvas c, UnitPose p, double width, {double y = _footY}) {
  // A cream ring round the shadow helps nobody, and a white one would put a
  // glowing puddle under a unit every time it was hit.
  if (p.outlinePass || p.flashPass) return;
  c.drawOval(
    Rect.fromCenter(
      center: Offset(0, y + 0.05),
      width: width,
      height: width * 0.28,
    ),
    p.solid(_shadowInk),
  );
}

/// Two legs mid-stride, hips at [hipY].
void _legs(
  Canvas c,
  UnitPose p, {
  required double hipY,
  double spread = 0.30,
  double width = 0.20,
  double stride = 0.24,
}) {
  final swing = p.moving ? math.sin(p.walk) * stride : 0.0;
  final brush = p.line(p.dark, width);
  c.drawLine(Offset(-spread, hipY), Offset(-spread + swing, _footY), brush);
  c.drawLine(Offset(spread, hipY), Offset(spread - swing, _footY), brush);
}

/// A face, or the back of a head, centred on (0, [y]) at radius [r].
void _face(
  Canvas c,
  UnitPose p, {
  required double y,
  required double r,
  double spread = 0.40,
  double size = 0.24,
}) {
  // The face sits inside the head, so it needs no rim of its own.
  if (p.outlinePass) return;

  if (p.facingY < -0.15) {
    // Walking away. A cap over the crown reads as the back of a head; two
    // eyes drawn here would have the unit moonwalking up the arena.
    c.drawArc(
      Rect.fromCircle(center: Offset(0, y), radius: r * 0.94),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      p.line(p.dark, r * 0.34),
    );
    return;
  }

  final ex = r * spread;
  final ey = y + r * 0.04;
  final er = r * size;
  final look = p.facingX.clamp(-1.0, 1.0) * er * 0.34;

  c.drawCircle(Offset(-ex, ey), er, p.solid(p.light));
  c.drawCircle(Offset(ex, ey), er, p.solid(p.light));
  c.drawCircle(Offset(-ex + look, ey), er * 0.55, p.solid(p.dark));
  c.drawCircle(Offset(ex + look, ey), er * 0.55, p.solid(p.dark));
}

/// The standard two-legged body: legs, torso, head, face.
///
/// Returns the shoulder line, which is where every painter hangs its arms
/// and its equipment.
double _biped(
  Canvas c,
  UnitPose p, {
  required double bodyW,
  required double bodyH,
  required double headR,
  double legWidth = 0.20,
}) {
  _shadow(c, p, bodyW * 1.55);

  final bob = _bob(p);
  final hipY = 0.34 + bob;
  final shoulderY = hipY - bodyH;

  // Everything above the shadow squashes together, so the body and head stay
  // one object rather than drifting apart on the bounce.
  c.save();
  _squash(c, p);

  _legs(c, p, hipY: hipY, spread: bodyW * 0.28, width: legWidth);

  final torso = RRect.fromRectXY(
    Rect.fromLTRB(-bodyW / 2, shoulderY, bodyW / 2, hipY + 0.06),
    bodyW * 0.36,
    bodyW * 0.36,
  );
  c.drawRRect(torso, p.solid(p.body));
  if (!p.outlinePass && !p.flashPass) {
    // A band along the bottom of the torso, in place of a full round shade:
    // the torso is a rounded rectangle, so an arc would not follow it.
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTRB(-bodyW / 2, hipY - bodyH * 0.30, bodyW / 2, hipY + 0.06),
        bodyW * 0.30,
        bodyW * 0.30,
      ),
      p.solid(p.dark.withValues(alpha: 0.24)),
    );
  }

  final headY = shoulderY - headR * 0.72;
  c.drawCircle(Offset(0, headY), headR, p.solid(p.body));
  _underShade(c, p, Offset(0, headY), headR);
  _face(c, p, y: headY, r: headR);

  c.restore();
  return shoulderY;
}

/// One arm, from the shoulder to a hand at ([handX], [handY]).
void _arm(Canvas c, UnitPose p, double shoulderY, double handX, double handY) {
  c.drawLine(
    Offset(handX.sign * 0.30, shoulderY + 0.14),
    Offset(handX, handY),
    p.line(p.dark, 0.17),
  );
}

// --- The characters ------------------------------------------------------

/// Dab: small, fast and always leaning into the run. Three of them arrive at
/// once, so the shape stays lean enough to read in a clump.
class _Dab extends UnitArt {
  const _Dab();

  @override
  void draw(Canvas c, UnitPose p) {
    _shadow(c, p, 1.25);

    final bob = _bob(p);
    _legs(c, p, hipY: 0.36 + bob, spread: 0.26, width: 0.14, stride: 0.30);

    final cy = -0.28 + bob;
    c.drawOval(
      Rect.fromCenter(center: Offset(0, cy + 0.35), width: 1.05, height: 1.5),
      p.solid(p.body),
    );
    // A swept crest: the only thing telling you this one is quick.
    final side = _side(p);
    c.drawLine(
      Offset(0, cy - 0.55),
      Offset(-side * 0.75, cy - 0.85),
      p.line(p.dark, 0.16),
    );
    _face(c, p, y: cy - 0.10, r: 0.52, size: 0.30);
  }
}

/// Roller: a squat body shoving a loaded drum ahead of it. The drum is the
/// whole point of the card, so it is drawn nearly as big as the unit and its
/// stripes turn as the unit walks.
class _Roller extends UnitArt {
  const _Roller();

  @override
  void draw(Canvas c, UnitPose p) {
    _shadow(c, p, 2.1);

    final bob = _bob(p);
    final away = p.facingY < -0.15;
    // Ahead of the body means further down the screen coming toward you, and
    // further up it walking away.
    final drumY = away ? -0.30 + bob : 0.72 + bob * 0.4;

    void body() {
      c.drawRRect(
        RRect.fromRectXY(
          Rect.fromLTRB(-0.68, -0.62 + bob, 0.68, 0.62 + bob),
          0.30,
          0.30,
        ),
        p.solid(p.body),
      );
      _face(c, p, y: -0.18 + bob, r: 0.55, size: 0.26);
    }

    void drum() {
      c.drawLine(Offset(0, bob), Offset(0, drumY), p.line(p.tool, 0.15));
      c.drawRRect(
        RRect.fromRectXY(
          Rect.fromLTRB(-1.18, drumY - 0.40, 1.18, drumY + 0.40),
          0.40,
          0.40,
        ),
        p.solid(p.tool),
      );
      // Paint-soaked bands rolling across the drum.
      final brush = p.line(p.body, 0.17);
      for (var i = 0; i < 3; i++) {
        final t = (p.walk / (math.pi * 2) + i / 3) % 1.0;
        final x = -0.94 + t * 1.88;
        c.drawLine(Offset(x, drumY - 0.27), Offset(x, drumY + 0.27), brush);
      }
    }

    // Whichever is further from the camera goes down first.
    if (away) {
      drum();
      body();
    } else {
      body();
      drum();
    }
  }
}

/// Brusher: the standard front line. A broad brush on a short arm that
/// sweeps through the swing.
class _Brusher extends UnitArt {
  const _Brusher();

  @override
  void draw(Canvas c, UnitPose p) {
    final shoulderY = _biped(c, p, bodyW: 1.10, bodyH: 1.00, headR: 0.50);

    final side = _side(p);
    final swing = _swing(p);
    final handX = side * (0.66 + swing * 0.30);
    final handY = shoulderY + 0.42 - swing * 0.34;
    _arm(c, p, shoulderY, handX, handY);

    c.save();
    c.translate(handX, handY);
    c.rotate(side * (0.5 - swing * 1.1));

    // Ferrule, then bristles fanning out of it.
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-0.16, -0.40, 0.16, 0.14),
        0.08,
        0.08,
      ),
      p.solid(p.tool),
    );
    final bristle = p.line(p.body, 0.13);
    for (var i = -1; i <= 1; i++) {
      c.drawLine(Offset(i * 0.11, 0.10), Offset(i * 0.20, 0.56), bristle);
    }
    c.restore();
  }
}

/// Kite: the only flyer. It never touches the ground, so it keeps a shadow
/// below it and beats a pair of wings to hold station.
class _Kite extends UnitArt {
  const _Kite();

  @override
  void draw(Canvas c, UnitPose p) {
    _shadow(c, p, 1.15, y: 1.05);

    final hover = math.sin(p.walk * 1.7) * 0.13;
    final cy = -0.62 + hover;
    final flap = math.sin(p.walk * 3.2) * 0.42;

    // Wings behind the body, so the body reads as the near shape.
    for (final side in const [-1.0, 1.0]) {
      c.save();
      c.translate(side * 0.35, cy - 0.12);
      c.rotate(side * (0.55 + flap));
      c.drawOval(const Rect.fromLTRB(0, -0.20, 1.15, 0.20), p.solid(p.dark));
      c.restore();
    }

    c.drawOval(
      Rect.fromCenter(center: Offset(0, cy), width: 1.15, height: 1.35),
      p.solid(p.body),
    );
    _underShade(c, p, Offset(0, cy), 0.60);
    // Tail ribbon, trailing behind and swinging with the beat.
    final tail = p.line(p.dark, 0.12);
    c.drawLine(Offset(0, cy + 0.62), Offset(flap * 0.35, cy + 1.20), tail);
    _face(c, p, y: cy - 0.12, r: 0.56, size: 0.28);
  }
}

/// Pin: the anti-air answer. A slim body under a long needle held high, which
/// is the read that says "this one shoots up".
class _Pin extends UnitArt {
  const _Pin();

  @override
  void draw(Canvas c, UnitPose p) {
    final shoulderY = _biped(c, p, bodyW: 0.92, bodyH: 1.02, headR: 0.46);

    final side = _side(p);
    final swing = _swing(p);
    final tipX = side * (0.72 + swing * 0.18);
    final tipY = -1.90 + swing * 0.22;

    _arm(c, p, shoulderY, side * 0.48, shoulderY + 0.24);
    c.drawLine(
      Offset(side * 0.48, shoulderY + 0.24),
      Offset(tipX, tipY),
      p.line(p.tool, 0.12),
    );
    c.drawCircle(Offset(tipX, tipY), 0.15, p.solid(p.body));
  }
}

/// Sprayer: paints while it shoots. A tank on its back feeds a wand, and the
/// wand puffs on every shot.
class _Sprayer extends UnitArt {
  const _Sprayer();

  @override
  void draw(Canvas c, UnitPose p) {
    final shoulderY = _biped(c, p, bodyW: 1.00, bodyH: 1.00, headR: 0.47);

    final side = _side(p);
    final swing = _swing(p);

    // Tank slung on the far side from the wand.
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTRB(
          -side * 0.78,
          shoulderY + 0.06,
          -side * 0.40,
          shoulderY + 0.88,
        ),
        0.19,
        0.19,
      ),
      p.solid(p.tool),
    );

    final nozzleX = side * 1.02;
    final nozzleY = shoulderY + 0.34;
    _arm(c, p, shoulderY, side * 0.58, nozzleY);
    c.drawLine(
      Offset(side * 0.42, shoulderY + 0.52),
      Offset(nozzleX, nozzleY),
      p.line(p.tool, 0.14),
    );

    if (swing > 0.02) {
      final puff = p.solid(p.body.withValues(alpha: 0.55 * swing));
      for (var i = 1; i <= 3; i++) {
        c.drawCircle(
          Offset(nozzleX + side * i * 0.28, nozzleY - i * 0.05),
          0.10 + i * 0.05,
          puff,
        );
      }
    }
  }
}

/// Nozzle: slow, heavy, and built around a bell mouth wide enough to explain
/// the splash radius on its own.
class _Nozzle extends UnitArt {
  const _Nozzle();

  @override
  void draw(Canvas c, UnitPose p) {
    _shadow(c, p, 2.0);

    final bob = _bob(p);
    final swing = _swing(p);
    _legs(c, p, hipY: 0.48 + bob, spread: 0.42, width: 0.26, stride: 0.16);

    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTRB(-0.80, -0.72 + bob, 0.80, 0.54 + bob),
        0.32,
        0.32,
      ),
      p.solid(p.body),
    );
    _face(c, p, y: -0.30 + bob, r: 0.58, size: 0.24);

    // The bell, kicking back as it fires.
    final side = _side(p);
    final recoil = swing * 0.20;
    c.save();
    c.translate(side * (0.86 - recoil), 0.02 + bob);
    c.rotate(side * 0.28);
    c.drawPath(_bell, p.solid(p.tool));
    c.drawOval(const Rect.fromLTRB(0.52, -0.44, 0.74, 0.44), p.solid(p.dark));
    if (swing > 0.02) {
      c.drawCircle(
        const Offset(0.95, 0),
        0.42 * swing,
        p.solid(p.body.withValues(alpha: 0.6 * swing)),
      );
    }
    c.restore();
  }
}

/// Sniper Nib: all barrel and no body. The silhouette should make you want to
/// keep it behind something.
class _SniperNib extends UnitArt {
  const _SniperNib();

  @override
  void draw(Canvas c, UnitPose p) {
    final shoulderY = _biped(
      c,
      p,
      bodyW: 0.76,
      bodyH: 1.06,
      headR: 0.40,
      legWidth: 0.15,
    );

    final side = _side(p);
    final swing = _swing(p);
    final muzzleX = side * (1.85 - swing * 0.22);
    final barrelY = shoulderY + 0.30;

    _arm(c, p, shoulderY, side * 0.52, barrelY);
    c.drawLine(
      Offset(-side * 0.30, barrelY + 0.10),
      Offset(muzzleX, barrelY),
      p.line(p.tool, 0.11),
    );
    // The nib itself: a wedge on the end of the barrel.
    c.save();
    c.translate(muzzleX, barrelY);
    c.scale(side, 1);
    c.drawPath(_nib, p.solid(p.body));
    c.restore();
  }
}

/// Swarmlets: six tiny bodies at once, so this is deliberately the least
/// detailed thing on the field. One eye and a pair of feelers.
class _Swarmlets extends UnitArt {
  const _Swarmlets();

  @override
  void draw(Canvas c, UnitPose p) {
    final lift = p.moving ? -math.sin(p.walk * 2.4).abs() * 0.20 : 0.0;
    _shadow(c, p, 1.15 + lift * 0.8);

    final cy = 0.18 + lift;
    c.drawOval(
      Rect.fromCenter(center: Offset(0, cy), width: 1.55, height: 1.35),
      p.solid(p.body),
    );
    _underShade(c, p, Offset(0, cy), 0.76);

    final wobble = math.sin(p.walk * 2) * 0.16;
    final feeler = p.line(p.dark, 0.11);
    c.drawLine(
      Offset(-0.34, cy - 0.55),
      Offset(-0.55 + wobble, cy - 1.15),
      feeler,
    );
    c.drawLine(
      Offset(0.34, cy - 0.55),
      Offset(0.55 + wobble, cy - 1.15),
      feeler,
    );

    if (p.facingY < -0.15) return; // Facing away: no eye to show.
    c.drawCircle(Offset(0, cy - 0.05), 0.36, p.solid(p.light));
    c.drawCircle(
      Offset(p.facingX.clamp(-1.0, 1.0) * 0.11, cy - 0.05),
      0.19,
      p.solid(p.dark),
    );
  }
}

/// Bucket Bot: the tank. A wide bucket on stubby legs, with a handle over the
/// top and a visor instead of a face, so it reads as armour at a glance.
class _BucketBot extends UnitArt {
  const _BucketBot();

  @override
  void draw(Canvas c, UnitPose p) {
    _shadow(c, p, 2.15);

    final bob = _bob(p);
    _legs(c, p, hipY: 0.58 + bob, spread: 0.48, width: 0.30, stride: 0.14);

    c.save();
    c.translate(0, bob);

    // Handle first, so the bucket rim covers where it joins.
    c.drawArc(
      const Rect.fromLTRB(-0.92, -1.55, 0.92, -0.35),
      math.pi,
      math.pi,
      false,
      p.line(p.tool, 0.13),
    );
    c.drawPath(_bucket, p.solid(p.body));
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-1.04, -0.98, 1.04, -0.70),
        0.14,
        0.14,
      ),
      p.solid(p.dark),
    );

    // A visor rather than eyes: it works from either side.
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-0.56, -0.42, 0.56, -0.10),
        0.16,
        0.16,
      ),
      p.solid(p.dark),
    );
    if (p.facingY >= -0.15) {
      final glow = p.solid(p.light);
      c.drawCircle(const Offset(-0.26, -0.26), 0.10, glow);
      c.drawCircle(const Offset(0.26, -0.26), 0.10, glow);
    }
    c.restore();
  }
}

/// Warden: broad, planted, and holding a shield. The aura ring itself is
/// drawn by the [Warden] component, not here.
class _Warden extends UnitArt {
  const _Warden();

  @override
  void draw(Canvas c, UnitPose p) {
    final shoulderY = _biped(
      c,
      p,
      bodyW: 1.30,
      bodyH: 1.02,
      headR: 0.52,
      legWidth: 0.24,
    );

    final side = _side(p);
    final swing = _swing(p);
    final shieldX = side * (0.86 + swing * 0.24);
    final shieldY = shoulderY + 0.46;

    _arm(c, p, shoulderY, shieldX * 0.7, shieldY);
    c.drawCircle(Offset(shieldX, shieldY), 0.62, p.solid(p.tool));
    c.drawCircle(Offset(shieldX, shieldY), 0.62, p.line(p.body, 0.14));
    c.drawCircle(Offset(shieldX, shieldY), 0.20, p.solid(p.body));
  }
}

/// Whirl: a body under a blade that never stops turning.
class _Whirl extends UnitArt {
  const _Whirl();

  @override
  void draw(Canvas c, UnitPose p) {
    _shadow(c, p, 1.9);

    final bob = _bob(p);
    _legs(c, p, hipY: 0.44 + bob, spread: 0.34, width: 0.22, stride: 0.18);

    // Squat housing, low so the blade is the thing you see.
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTRB(-0.58, -0.30 + bob, 0.58, 0.52 + bob),
        0.24,
        0.24,
      ),
      p.solid(p.body),
    );
    _face(c, p, y: -0.02 + bob, r: 0.46, size: 0.26);

    // The blade. Spun off the walk cycle while moving and the breath clock
    // while idle, so it is turning whatever the unit is doing — a saw that
    // stops when you stop reads as broken.
    final spin = p.walk * 2.6 + p.breath * 1.4 + _swing(p) * 3.0;
    c.save();
    c.translate(0, -0.72 + bob);
    c.rotate(spin);

    const teeth = 6;
    final tooth = p.solid(p.tool);
    for (var i = 0; i < teeth; i++) {
      c.save();
      c.rotate(i * math.pi * 2 / teeth);
      c.drawRRect(
        RRect.fromRectXY(
          const Rect.fromLTRB(-0.13, -0.98, 0.13, -0.42),
          0.06,
          0.06,
        ),
        tooth,
      );
      c.restore();
    }
    c.drawCircle(Offset.zero, 0.52, p.solid(p.tool));
    c.drawCircle(Offset.zero, 0.34, p.solid(p.body));
    c.drawCircle(Offset.zero, 0.12, p.solid(p.dark));
    c.restore();
  }
}

// --- Buildings -----------------------------------------------------------
// Deliberately squarer and flatter than the troops. A building is something
// you should be able to pick out of a scrum at a glance, and the fastest way
// to say "this one will not chase you" is to give it a base instead of legs.

/// A plinth: the flat base every building sits on.
void _plinth(Canvas c, UnitPose p, double halfWidth) {
  _shadow(c, p, halfWidth * 2.5);
  c.drawRRect(
    RRect.fromRectXY(
      Rect.fromLTRB(-halfWidth, 0.52, halfWidth, 1.02),
      0.12,
      0.12,
    ),
    p.solid(p.dark),
  );
}

/// Turret: a cannon on a swivel, aimed the way it last fired.
class _Turret extends UnitArt {
  const _Turret();

  @override
  void draw(Canvas c, UnitPose p) {
    _plinth(c, p, 0.92);

    // Housing.
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-0.68, -0.42, 0.68, 0.60),
        0.18,
        0.18,
      ),
      p.solid(p.body),
    );
    _underShade(c, p, const Offset(0, 0.10), 0.66);

    // Barrel, swinging toward whatever it is shooting and recoiling as it
    // fires. This is the whole read of the card, so it is drawn big.
    final side = _side(p);
    final recoil = _swing(p) * 0.22;
    c.save();
    c.translate(0, -0.30);
    c.rotate(side * 0.55 + p.facingY.clamp(-1.0, 1.0) * 0.12);
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTRB(-0.16, -1.15 + recoil, 0.16, 0.20 + recoil),
        0.14,
        0.14,
      ),
      p.solid(p.tool),
    );
    c.drawCircle(Offset(0, -1.15 + recoil), 0.22, p.solid(p.tool));
    if (_swing(p) > 0.02) {
      c.drawCircle(
        Offset(0, -1.42 + recoil),
        0.30 * _swing(p),
        p.solid(p.body.withValues(alpha: 0.65 * _swing(p))),
      );
    }
    c.restore();

    // Mount collar, over the barrel root so the join reads as a pivot.
    c.drawCircle(const Offset(0, -0.30), 0.30, p.solid(p.dark));
    c.drawCircle(const Offset(0, -0.30), 0.13, p.solid(p.light));
  }
}

/// Sprinkler: a squat head throwing arcs of paint, spinning as it goes.
class _Sprinkler extends UnitArt {
  const _Sprinkler();

  @override
  void draw(Canvas c, UnitPose p) {
    _plinth(c, p, 0.72);

    // Stem and head.
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-0.22, -0.42, 0.22, 0.62),
        0.10,
        0.10,
      ),
      p.solid(p.tool),
    );
    c.drawOval(const Rect.fromLTRB(-0.62, -0.88, 0.62, -0.24), p.solid(p.body));
    _underShade(c, p, const Offset(0, -0.56), 0.60);

    // Four arcs of spray, turning on the breath clock. It has no walk cycle
    // of its own — it never moves — so the idle timer drives it.
    if (p.outlinePass || p.flashPass) return;
    final spray = p.line(p.body.withValues(alpha: 0.75), 0.12);
    for (var i = 0; i < 4; i++) {
      final angle = p.breath * 0.9 + i * math.pi / 2;
      final dx = math.cos(angle);
      c.drawArc(
        Rect.fromCenter(
          center: Offset(dx * 0.75, -0.30),
          width: 1.5,
          height: 0.9,
        ),
        math.pi,
        math.pi,
        false,
        spray,
      );
    }
  }
}

/// Beamer: a lens on a post, glowing brighter the closer it is to firing.
class _Beamer extends UnitArt {
  const _Beamer();

  @override
  void draw(Canvas c, UnitPose p) {
    _plinth(c, p, 0.78);

    // Post.
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-0.20, -0.50, 0.20, 0.60),
        0.09,
        0.09,
      ),
      p.solid(p.tool),
    );

    // Emitter head, tilted the way it last fired.
    final side = _side(p);
    c.save();
    c.translate(0, -0.86);
    c.rotate(side * 0.30);
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-0.56, -0.40, 0.56, 0.34),
        0.20,
        0.20,
      ),
      p.solid(p.body),
    );
    _underShade(c, p, const Offset(0, -0.03), 0.52);

    // The lens. Pulses on the idle clock and flares white on the shot, so
    // the card reads as charging even when nothing is in range.
    if (!p.outlinePass && !p.flashPass) {
      final charge = 0.45 + 0.25 * math.sin(p.breath * 1.6).abs();
      final flare = _swing(p);
      c.drawCircle(const Offset(0, -0.03), 0.26, p.solid(p.dark));
      c.drawCircle(
        const Offset(0, -0.03),
        0.18 + flare * 0.10,
        p.solid(Color.lerp(p.body, p.light, (charge + flare).clamp(0.0, 1.0))!),
      );
    }
    c.restore();
  }
}

/// Scatter: a ring of barrels pointing outward, turning between volleys.
class _Scatter extends UnitArt {
  const _Scatter();

  /// One barrel per shell it throws, so the picture says what the card does.
  static const int barrels = 8;

  @override
  void draw(Canvas c, UnitPose p) {
    _plinth(c, p, 1.0);

    // The turret turns on the idle clock. It has no walk cycle — it never
    // moves — and its real volley spin is gameplay state the art does not
    // see, so this is a stand-in that reads the same: always rotating.
    c.save();
    c.translate(0, -0.30);
    c.rotate(p.breath * 0.35);

    final barrel = p.solid(p.tool);
    for (var i = 0; i < barrels; i++) {
      c.save();
      c.rotate(i * math.pi * 2 / barrels);
      c.drawRRect(
        RRect.fromRectXY(
          const Rect.fromLTRB(-0.11, -1.05, 0.11, -0.45),
          0.07,
          0.07,
        ),
        barrel,
      );
      // A muzzle cap in the team colour, so the ring reads as loaded.
      if (!p.outlinePass && !p.flashPass) {
        c.drawCircle(const Offset(0, -1.02), 0.10, p.solid(p.body));
      }
      c.restore();
    }

    // Hub.
    c.drawCircle(Offset.zero, 0.56, p.solid(p.body));
    _underShade(c, p, Offset.zero, 0.56);
    c.drawCircle(Offset.zero, 0.24, p.solid(p.dark));
    c.restore();
  }
}

/// Barricade: a wall of set paint, chipping as it takes hits.
class _Barricade extends UnitArt {
  const _Barricade();

  @override
  void draw(Canvas c, UnitPose p) {
    _shadow(c, p, 2.3);

    // Two courses of blocks, offset like brickwork.
    const top = -0.62;
    const mid = 0.16;
    const bottom = 0.96;

    for (final row in const [(top, mid, 0.0), (mid, bottom, 0.36)]) {
      final (y0, y1, offset) = row;
      for (var i = -1; i <= 1; i++) {
        final x = i * 0.72 + offset;
        if (x.abs() > 1.25) continue;
        c.drawRRect(
          RRect.fromRectXY(
            Rect.fromLTRB(x - 0.36, y0, x + 0.36, y1),
            0.08,
            0.08,
          ),
          p.solid(p.body),
        );
      }
    }

    if (p.outlinePass || p.flashPass) return;
    // A shaded band along the foot, so it sits on the ground rather than
    // floating over it.
    c.drawRRect(
      RRect.fromRectXY(
        const Rect.fromLTRB(-1.25, 0.66, 1.25, bottom),
        0.08,
        0.08,
      ),
      p.solid(p.dark.withValues(alpha: 0.3)),
    );
  }
}

/// Whatever a troop with no art of its own gets: a plain body, so a new card
/// is visible on the field the moment it exists.
class _Generic extends UnitArt {
  const _Generic();

  @override
  void draw(Canvas c, UnitPose p) =>
      _biped(c, p, bodyW: 1.05, bodyH: 0.98, headR: 0.48);
}

// --- Cached paths --------------------------------------------------------
// Fixed sub-shapes, built once. Anything that animates is drawn from
// primitives instead, so no path is rebuilt on a frame.

/// Nozzle's bell mouth, opening along +x.
final Path _bell = Path()
  ..moveTo(-0.10, -0.24)
  ..lineTo(0.62, -0.50)
  ..lineTo(0.62, 0.50)
  ..lineTo(-0.10, 0.24)
  ..close();

/// Sniper Nib's tip, pointing along +x.
final Path _nib = Path()
  ..moveTo(-0.10, -0.19)
  ..lineTo(0.30, 0)
  ..lineTo(-0.10, 0.19)
  ..close();

/// Bucket Bot's body: wide at the rim, narrow at the base.
final Path _bucket = Path()
  ..moveTo(-0.98, -0.92)
  ..lineTo(0.98, -0.92)
  ..lineTo(0.70, 0.62)
  ..lineTo(-0.70, 0.62)
  ..close();

// --- Registry ------------------------------------------------------------

/// The art for each troop in `cards.json`, keyed by card id.
///
/// Ids are spelled out rather than pulled from the type classes: this file
/// draws pictures and has no business importing twelve components to do it.
/// `unit_art_test.dart` holds the two sides together.
const Map<String, UnitArt> unitArt = <String, UnitArt>{
  'dab': _Dab(),
  'roller': _Roller(),
  'brusher': _Brusher(),
  'kite': _Kite(),
  'pin': _Pin(),
  'sprayer': _Sprayer(),
  'nozzle': _Nozzle(),
  'sniper_nib': _SniperNib(),
  'swarmlets': _Swarmlets(),
  'bucket_bot': _BucketBot(),
  'warden': _Warden(),
  'whirl': _Whirl(),

  // Buildings.
  'turret': _Turret(),
  'sprinkler': _Sprinkler(),
  'barricade': _Barricade(),
  'beamer': _Beamer(),
  'scatter': _Scatter(),
};

/// The art for [cardId], or a plain body if it has none yet.
UnitArt artFor(String cardId) => unitArt[cardId] ?? const _Generic();
