// Draws the 512x512 achievement icons the Play Console asks for.
//
// Run with: flutter test tool/generate_achievement_icons.dart
//
// Not `dart run`, and not a test despite how it is invoked — same reasoning
// as `generate_icons.dart` next to it: this needs a real `dart:ui` canvas and
// `flutter test` is the only headless way to get one. It sits in `tool/` so a
// normal test run does not rewrite fourteen PNGs.
//
// Output goes to `build/achievements/`, beside the CSV, so
// `build_achievements_zip.dart` picks the icons up and writes the mapping
// file. That is why they land there and not in `assets/`: these are never
// bundled into the app. Play Games serves them.
//
// **The icons are code, not binaries.** Fourteen hand-drawn PNGs would be
// fourteen files nobody can diff and nobody can restyle when the palette
// moves. These are a few dozen lines of paths against `Palette`, so a colour
// change is a re-run.
//
// Two constraints shape every one of them:
//
//   * **Play Games masks the icon to a circle.** Everything has to live
//     inside the circle inscribed in the square — radius 0.5 — and the
//     corners are thrown away. Nothing important goes past 0.44.
//   * **They are shown at about 32 dp in a list.** So: one idea per icon, no
//     text, no fine detail, and flat hard-edged colour the same way the arena
//     paints. Anything that needs a second look has already failed.
//
// The platform draws the locked state itself by desaturating these, so there
// is one file per achievement rather than a pair.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';

/// Rendered at 2x and area-averaged down, so edges get their smoothing from
/// real coverage rather than from a filter guessing at it.
const int _master = 1024;

/// What Play Games wants. Documented as 512x512.
const int _output = 512;

// --- The shared look -----------------------------------------------------

/// The ground every icon stands on.
///
/// One ground across the whole set, deliberately: fourteen icons in a list
/// want to look like one game's achievements, and the glyph is what should be
/// carrying the difference. It is the arena's own bezel colour, the darkest
/// thing in the app, which is what lets cream and gold read at 32 dp.
const Color _ground = Palette.hudBezelLow;
const Color _groundRim = Palette.hudBezelHigh;
const Color _cream = Palette.arenaFloor;
const Color _ink = Palette.hudOutline;

void main() {
  test('generate the achievement icons', () async {
    final source = File('assets/data/achievements.json');
    final json = jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
    final keys = [
      for (final a in (json['achievements'] as List))
        (a as Map<String, dynamic>)['key'] as String,
    ];

    // An achievement with no drawing would ship as a blank circle, which
    // reads as a loading state rather than as a mistake. Fail here instead.
    expect(
      keys.where((k) => !_glyphs.containsKey(k)),
      isEmpty,
      reason: 'no icon drawn for these',
    );
    expect(
      _glyphs.keys.where((k) => !keys.contains(k)),
      isEmpty,
      reason: 'icons drawn for achievements that no longer exist',
    );

    final out = Directory('build/achievements')..createSync(recursive: true);
    for (final key in keys) {
      final pixels = _resize(await _render(_glyphs[key]!), _output);
      _writePng('${out.path}/$key.png', pixels);
    }

    final boards = Directory('build/leaderboards')..createSync(recursive: true);
    for (final entry in _leaderboardGlyphs.entries) {
      final pixels = _resize(await _render(entry.value), _output);
      _writePng('${boards.path}/${entry.key}.png', pixels);
    }

    stdout.writeln(
      'Wrote ${keys.length} achievement icons and '
      '${_leaderboardGlyphs.length} leaderboard icons at '
      '${_output}x$_output to ${out.path} and ${boards.path}',
    );
  });
}

typedef Glyph = void Function(Canvas canvas, Paint brush);

/// One drawing per achievement, keyed the same way the JSON is.
final Map<String, Glyph> _glyphs = <String, Glyph>{
  // The campaign ladder is one family: the board filling up with your colour.
  // Six steps of the same picture, because they *are* six steps of the same
  // thing, and someone reading down the list should see a bar chart.
  'first_coat': (c, b) => _tiles(c, b, 1),
  'primer': (c, b) => _tiles(c, b, 2),
  'undercoat': (c, b) => _tiles(c, b, 4),
  'topcoat': (c, b) => _tiles(c, b, 6),
  'gloss_finish': (c, b) => _tiles(c, b, 8),
  // The capstone gets a gold ring. It is the only one that ends the campaign.
  'the_whole_yard': (c, b) => _tiles(c, b, 9, crowned: true),

  'three_star_job': (c, b) => _stars(c, b, 1),
  'snagging_list': (c, b) => _stars(c, b, 3),

  'whitewash': _whitewash,
  'overtime': _clock,
  'frontier': _flag,
  'break_the_seal': _chest,
  'fully_loaded': _upgrade,
  'full_set': _cardFan,
};

/// Leaderboard icons, drawn the same way and into `build/leaderboards/`.
///
/// Separate from the achievement set because leaderboards are not in
/// `achievements.json` and have their own ids, but the same ground and the
/// same palette: they sit next to each other in the Play Games app, and two
/// visual families there would just look like two games.
final Map<String, Glyph> _leaderboardGlyphs = <String, Glyph>{
  'total_stars': _podium,
  'levels_cleared': _steps,
};

// --- The drawings --------------------------------------------------------

/// A podium with a star over the winner: ranking, by stars.
///
/// A star on its own is what two of the achievements already are, and the
/// leaderboard sits in the same list as those — so the podium is doing the
/// work of saying *ranking*, and the star says what is being ranked.
void _podium(Canvas canvas, Paint brush) {
  const base = 0.762;

  // The floor, so the three columns stand on something rather than float.
  canvas.drawRRect(
    RRect.fromRectXY(
      const Rect.fromLTWH(0.195, base, 0.610, 0.032),
      0.016,
      0.016,
    ),
    brush..color = _cream,
  );

  // Second, first, third — the arrangement everyone already reads as a
  // podium, and the only one where the middle being tallest means something.
  void column(double centre, double height, Color colour) {
    canvas.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(centre - 0.0875, base - height, 0.175, height),
        0.022,
        0.022,
      ),
      brush..color = colour,
    );
  }

  column(0.303, 0.205, _cream);
  column(0.697, 0.150, _cream);
  column(0.500, 0.300, Palette.blue);

  canvas.drawPath(_star(0.500, 0.330, 0.128), brush..color = Palette.gold);
}

/// A staircase climbing to the right: how far up the campaign you are.
///
/// Deliberately *asymmetric*, because it sits next to the podium and the two
/// must not read as the same picture at 32 dp. A podium is symmetric with a
/// winner in the middle; a climb only goes one way and has no top.
///
/// Cream for the steps behind you and gold for the one you are on, which is
/// the same grammar the campaign list already uses.
void _steps(Canvas canvas, Paint brush) {
  const base = 0.762;
  const width = 0.145;
  const gap = 0.016;
  const left = 0.186;

  canvas.drawRRect(
    RRect.fromRectXY(
      const Rect.fromLTWH(left, base, width * 4 + gap * 3, 0.030),
      0.015,
      0.015,
    ),
    brush..color = _cream,
  );

  for (var i = 0; i < 4; i++) {
    final height = 0.145 + i * 0.080;
    canvas.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(left + i * (width + gap), base - height, width, height),
        0.020,
        0.020,
      ),
      brush..color = i == 3 ? Palette.gold : _cream,
    );
  }
}

/// A 3x3 board with [filled] cells taken, counting from the bottom left.
///
/// Bottom-up because that is the direction the player pushes: blue holds the
/// bottom of the arena and takes ground upward.
void _tiles(Canvas canvas, Paint brush, int filled, {bool crowned = false}) {
  // Sized off the *diagonal*, not the width. A 3x3 grid 0.65 wide puts its
  // corner tiles 0.46 from the centre, outside the circle the platform masks
  // to — so the first pass had the top row clipped on a real device and
  // looked fine in the square PNG. Span 0.60 lands the corners at 0.42.
  const cell = 0.185;
  const gap = 0.022;
  const span = cell * 3 + gap * 2;
  const left = (1 - span) / 2;

  var placed = 0;
  for (var row = 2; row >= 0; row--) {
    for (var col = 0; col < 3; col++) {
      final taken = placed < filled;
      placed++;
      final rect = Rect.fromLTWH(
        left + col * (cell + gap),
        left + row * (cell + gap),
        cell,
        cell,
      );
      canvas.drawRRect(
        RRect.fromRectXY(rect, 0.03, 0.03),
        brush..color = taken ? Palette.blue : _cream,
      );
    }
  }

  if (crowned) {
    canvas.drawCircle(
      const Offset(0.5, 0.5),
      0.452,
      brush
        ..color = Palette.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.034,
    );
    brush.style = PaintingStyle.fill;
  }
}

/// One star, or the classic three with the middle one raised.
void _stars(Canvas canvas, Paint brush, int count) {
  brush.color = Palette.gold;
  if (count == 1) {
    canvas.drawPath(_star(0.5, 0.5, 0.30), brush);
    return;
  }
  canvas.drawPath(_star(0.235, 0.560, 0.150), brush);
  canvas.drawPath(_star(0.765, 0.560, 0.150), brush);
  canvas.drawPath(_star(0.500, 0.470, 0.195), brush);
}

/// The board all but taken: blue everywhere and the last sliver of red left.
///
/// The frontier is torn rather than ruled. A straight strip of red across a
/// blue rectangle read as a design element — a header bar — and not as paint
/// at all. The whole point of the picture is that somebody pushed the line up
/// there, and a ruled line is the one thing that never happens in this game.
void _whitewash(Canvas canvas, Paint brush) {
  final board = _board();
  canvas.save();
  canvas.clipRRect(board);
  canvas.drawRRect(board, brush..color = Palette.red);

  final taken = Path();
  for (var i = 0; i <= 120; i++) {
    final x = i / 120;
    // Three harmonics with unrelated phases: the slow one gives it a lean,
    // the fast one stops it reading as a wave.
    final y =
        0.232 +
        0.022 * math.sin(x * 6.3 + 0.7) +
        0.013 * math.sin(x * 12.1 + 2.4) +
        0.007 * math.sin(x * 21.0 + 4.3);
    i == 0 ? taken.moveTo(x, y) : taken.lineTo(x, y);
  }
  taken
    ..lineTo(1, 1)
    ..lineTo(0, 1)
    ..close();
  canvas.drawPath(taken, brush..color = Palette.blue);
  canvas.restore();
  _frame(canvas, brush, board);
}

/// A clock run down to the last of its face: sudden death.
void _clock(Canvas canvas, Paint brush) {
  const centre = Offset(0.5, 0.5);
  canvas.drawCircle(centre, 0.325, brush..color = _cream);
  // The overtime wedge, at the top of the dial where the clock runs out.
  final wedge = Path()
    ..moveTo(centre.dx, centre.dy)
    ..arcTo(
      Rect.fromCircle(center: centre, radius: 0.325),
      -math.pi / 2 - 0.62,
      0.62,
      false,
    )
    ..close();
  canvas.drawPath(wedge, brush..color = Palette.danger);
  canvas.drawCircle(
    centre,
    0.325,
    brush
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.048,
  );
  brush
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 0.045;
  // Both hands near the top: the time is almost gone.
  canvas.drawLine(centre, const Offset(0.500, 0.245), brush);
  canvas.drawLine(centre, const Offset(0.365, 0.360), brush);
  brush.style = PaintingStyle.fill;
  canvas.drawCircle(centre, 0.038, brush);
}

/// A flag planted in the opponent's half, with the halfway line under it.
void _flag(Canvas canvas, Paint brush) {
  final board = _board();
  canvas.save();
  canvas.clipRRect(board);
  canvas.drawRRect(board, brush..color = Palette.red);
  canvas.drawRect(const Rect.fromLTRB(0, 0.615, 1, 1), brush..color = Palette.blue);
  // The halfway line, dashed the way a boundary is drawn in the arena.
  brush.color = _cream;
  for (var x = 0.145; x < 0.86; x += 0.104) {
    canvas.drawRect(Rect.fromLTWH(x, 0.604, 0.062, 0.022), brush);
  }
  // The splat it landed in, then the pole and pennant over it.
  canvas.drawCircle(const Offset(0.455, 0.398), 0.108, brush);
  canvas.drawCircle(
    const Offset(0.455, 0.398),
    0.084,
    brush..color = Palette.blue,
  );
  canvas.drawRect(
    const Rect.fromLTWH(0.428, 0.185, 0.038, 0.235),
    brush..color = _cream,
  );
  final pennant = Path()
    ..moveTo(0.466, 0.196)
    ..lineTo(0.700, 0.252)
    ..lineTo(0.466, 0.312)
    ..close();
  canvas.drawPath(pennant, brush..color = Palette.blue);
  canvas.drawPath(
    pennant,
    brush
      ..color = _cream
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.026,
  );
  brush.style = PaintingStyle.fill;
  canvas.restore();
  _frame(canvas, brush, board);
}

/// A chest, lid up.
///
/// Two things do the work of saying "open", and the first pass had neither:
/// the **dark mouth** between lid and body, which is the only part that says
/// there is an inside, and rays that read as light rather than as sticks. A
/// gold box with a gold lid resting on it is a box.
void _chest(Canvas canvas, Paint brush) {
  const lit = Color(0xFFF0B429);
  const inside = Color(0xFF3E2B06);

  // Light coming out. Translucent on purpose — these fade into the ground
  // instead of ending, which is what separates a glow from a fan of spokes.
  // The file is written opaque, so the alpha is resolved here against the
  // ground and nothing carries it out of the canvas.
  brush.color = const Color(0x5AF0B429);
  for (var i = -2; i <= 2; i++) {
    canvas.save();
    canvas.translate(0.5, 0.455);
    canvas.rotate(i * 0.40);
    canvas.drawPath(
      Path()
        ..moveTo(-0.030, -0.075)
        ..lineTo(0.030, -0.075)
        ..lineTo(0.014, -0.310)
        ..lineTo(-0.014, -0.310)
        ..close(),
      brush,
    );
    canvas.restore();
  }

  // The open mouth, drawn first so the lid and body sit over its ends.
  canvas.drawRect(
    const Rect.fromLTWH(0.235, 0.470, 0.530, 0.115),
    brush..color = inside,
  );

  final body = RRect.fromRectXY(
    const Rect.fromLTWH(0.215, 0.545, 0.570, 0.230),
    0.040,
    0.040,
  );
  canvas.drawRRect(body, brush..color = Palette.gold);
  // A band across the body, so it reads as a chest rather than a crate.
  canvas.drawRect(
    const Rect.fromLTWH(0.215, 0.615, 0.570, 0.048),
    brush..color = lit,
  );

  // The lid, tipped back: wider at the front edge than at the back.
  final lidPath = Path()
    ..moveTo(0.215, 0.495)
    ..lineTo(0.785, 0.495)
    ..lineTo(0.735, 0.355)
    ..lineTo(0.265, 0.355)
    ..close();
  canvas.drawPath(lidPath, brush..color = lit);

  // The clasp, straddling the mouth. A keyhole in it is what makes a pale
  // square read as a lock instead of a label.
  canvas.drawRRect(
    RRect.fromRectXY(
      const Rect.fromLTWH(0.443, 0.505, 0.114, 0.150),
      0.024,
      0.024,
    ),
    brush..color = _cream,
  );
  canvas.drawCircle(const Offset(0.500, 0.565), 0.026, brush..color = inside);
  canvas.drawRect(
    const Rect.fromLTWH(0.486, 0.565, 0.028, 0.054),
    brush,
  );
}

/// A card being taken up: three chevrons climbing it.
void _upgrade(Canvas canvas, Paint brush) {
  final card = RRect.fromRectXY(
    const Rect.fromLTWH(0.290, 0.175, 0.420, 0.650),
    0.060,
    0.060,
  );
  canvas.drawRRect(card, brush..color = _cream);
  brush
    ..color = Palette.success
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.062
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (var i = 0; i < 3; i++) {
    final y = 0.395 + i * 0.170;
    canvas.drawPath(
      Path()
        ..moveTo(0.392, y)
        ..lineTo(0.500, y - 0.096)
        ..lineTo(0.608, y),
      brush,
    );
  }
  brush
    ..color = _ink
    ..strokeWidth = 0.038;
  canvas.drawRRect(card, brush);
  brush.style = PaintingStyle.fill;
}

/// Three cards fanned: the whole collection.
void _cardFan(Canvas canvas, Paint brush) {
  const stripes = <Color>[Palette.red, Palette.gold, Palette.blue];
  const angles = <double>[-0.34, 0.34, 0.0];
  const offsets = <Offset>[
    Offset(-0.135, 0.045),
    Offset(0.135, 0.045),
    Offset(0, -0.015),
  ];
  for (var i = 0; i < 3; i++) {
    canvas.save();
    canvas.translate(0.5 + offsets[i].dx, 0.56 + offsets[i].dy);
    canvas.rotate(angles[i]);
    final card = RRect.fromRectXY(
      const Rect.fromLTWH(-0.150, -0.285, 0.300, 0.470),
      0.045,
      0.045,
    );
    canvas.drawRRect(card, brush..color = _cream);
    canvas.save();
    canvas.clipRRect(card);
    canvas.drawRect(
      const Rect.fromLTWH(-0.150, -0.285, 0.300, 0.125),
      brush..color = stripes[i],
    );
    canvas.restore();
    brush
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.034;
    canvas.drawRRect(card, brush);
    brush.style = PaintingStyle.fill;
    canvas.restore();
  }
}

// --- Shared shapes -------------------------------------------------------

/// The arena, as a rounded rect that fits inside the circular mask.
RRect _board() => RRect.fromRectXY(
  const Rect.fromLTWH(0.145, 0.145, 0.710, 0.710),
  0.075,
  0.075,
);

/// The dark bezel round the board. Section 14: the frame is what stops the
/// blue half bleeding into whatever sits behind it.
void _frame(Canvas canvas, Paint brush, RRect board) {
  canvas.drawRRect(
    board,
    brush
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.048,
  );
  brush.style = PaintingStyle.fill;
}

Path _star(double cx, double cy, double r) {
  final path = Path();
  final inner = r * 0.46;
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? r : inner;
    final theta = -math.pi / 2 + i * math.pi / 5;
    final x = cx + radius * math.cos(theta);
    final y = cy + radius * math.sin(theta);
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  return path..close();
}

// --- Rendering -----------------------------------------------------------

Future<Float64List> _render(Glyph glyph) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const double n = _master + 0.0;

  // Authored in a unit square, so every number above is a fraction of the
  // icon and none of them change with the output size.
  canvas.scale(n);

  final brush = Paint()..isAntiAlias = true;
  // Full bleed rather than a drawn circle: the platform mask makes the
  // circle, and a square opaque to its corners also survives being shown
  // square, which some surfaces do.
  canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), brush..color = _ground);
  canvas.drawCircle(
    const Offset(0.5, 0.5),
    0.478,
    brush
      ..color = _groundRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.022,
  );
  brush.style = PaintingStyle.fill;

  glyph(canvas, brush);

  final image = await recorder.endRecording().toImage(_master, _master);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final bytes = data!.buffer.asUint8List();
  final out = Float64List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] / 255;
  }
  return out;
}

/// Area-averages the master down, the same box filter the launcher icons use.
Float64List _resize(Float64List src, int size) {
  if (size == _master) return src;
  final out = Float64List(size * size * 4);
  final scale = _master / size;
  for (var y = 0; y < size; y++) {
    final y0 = y * scale;
    final y1 = (y + 1) * scale;
    for (var x = 0; x < size; x++) {
      final x0 = x * scale;
      final x1 = (x + 1) * scale;
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0, weight = 0.0;
      for (var sy = y0.floor(); sy < y1.ceil() && sy < _master; sy++) {
        final wy = math.min(y1, sy + 1.0) - math.max(y0, sy.toDouble());
        for (var sx = x0.floor(); sx < x1.ceil() && sx < _master; sx++) {
          final wx = math.min(x1, sx + 1.0) - math.max(x0, sx.toDouble());
          final w = wx * wy;
          final o = (sy * _master + sx) * 4;
          r += src[o] * w;
          g += src[o + 1] * w;
          b += src[o + 2] * w;
          a += src[o + 3] * w;
          weight += w;
        }
      }
      final o = (y * size + x) * 4;
      out[o] = r / weight;
      out[o + 1] = g / weight;
      out[o + 2] = b / weight;
      out[o + 3] = a / weight;
    }
  }
  return out;
}

/// Writes an opaque three-channel PNG.
///
/// No alpha channel at all. The design is full bleed so there is nothing to
/// be transparent, and an icon carrying an alpha channel is one more thing
/// for an uploader to have an opinion about.
void _writePng(String path, Float64List pixels) {
  final size = math.sqrt(pixels.length / 4).round();
  final stride = size * 3 + 1;
  final raw = Uint8List(stride * size);

  for (var y = 0; y < size; y++) {
    final row = y * stride;
    raw[row] = 0; // Filter type 0: none.
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final o = row + 1 + x * 3;
      raw[o] = _byte(pixels[i]);
      raw[o + 1] = _byte(pixels[i + 1]);
      raw[o + 2] = _byte(pixels[i + 2]);
    }
  }

  final png = BytesBuilder();
  png.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final header = BytesBuilder()
    ..add(_uint32(size))
    ..add(_uint32(size))
    ..add([8, 2, 0, 0, 0]);
  png.add(_chunk('IHDR', header.takeBytes()));
  png.add(_chunk('IDAT', Uint8List.fromList(ZLibCodec(level: 9).encode(raw))));
  png.add(_chunk('IEND', Uint8List(0)));
  File(path).writeAsBytesSync(png.takeBytes());
}

int _byte(double v) => (v * 255).round().clamp(0, 255);

Uint8List _uint32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

Uint8List _chunk(String type, Uint8List data) {
  final name = ascii.encode(type);
  final body = Uint8List(name.length + data.length)
    ..setAll(0, name)
    ..setAll(name.length, data);
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...body,
    ..._uint32(_crc32(body)),
  ]);
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
