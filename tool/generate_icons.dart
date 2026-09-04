// Generates every launcher icon from scratch.
//
// Run with: flutter test tool/generate_icons.dart
//
// Not `dart run`, and not a test either despite how it is invoked: it needs a
// real `dart:ui` canvas to draw on, and `flutter test` is the only headless
// way to get one. It lives in `tool/` rather than `test/` so a normal test
// run does not rewrite the app icon.
//
// Same reasoning as `generate_audio.dart`: the icon is a few lines of maths in
// version control rather than a binary blob, so nudging the paint line is a
// code review instead of a file swap.
//
// The design is the game in one square. Red holds the top, blue holds the
// bottom, they meet along a torn paint edge, and a Turret stands on blue
// ground with its barrel up, having just put a splat of blue paint into red
// territory. That is the whole loop in one picture: you shoot, the ground
// changes hands, and the ground is the score.
//
// **The Turret is the game's own art**, drawn by the same `unitArt` painter
// the arena and the card tiles use. Nobody has to keep an icon in step with a
// unit that gets redrawn — this is the same seam `UnitArtView` sits on.
//
// Flat, hard-edged, no gradients and no blur: the arena paints in whole grid
// cells with no soft blob, and the icon is painted the same way.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/units/unit_art.dart';

// --- The palette ---------------------------------------------------------
// The two sides come straight from `Palette`. Section 14 pins them: opposite
// on the hue wheel *and* 13 points apart in lightness, which is what keeps
// them apart at thumbnail size and for a colourblind player. A launcher icon
// is the smallest this pair is ever asked to work at.

/// The cool off-white the arena floor is painted in, used for the rim around
/// the splat.
///
/// The rim is not decoration. A blue splat on the blue half is invisible
/// without it — it is the same trick every unit on the field uses, drawn once
/// as a fat pale stroke and then again on top.
const Color _cream = Palette.arenaFloor;

/// Which unit stands on the icon.
const String _subject = 'turret';

/// Master render size. Every output is area-averaged down from this, so the
/// small sizes get their antialiasing from real coverage rather than from a
/// filter guessing at it.
const int _master = 1024;

/// How much of an adaptive icon's 108 dp layer is actually visible: launchers
/// mask it down to roughly 72 dp, with 66 dp guaranteed. The design is drawn
/// zoomed by this so the visible middle matches the legacy square.
const double _adaptiveZoom = 108 / 72;

void main() {
  test('generate the launcher icons', () async {
    final legacy = await _render(subject: true, round: true);
    final opaque = await _render(subject: true, round: false);
    final adaptiveBg = await _render(subject: false, zoom: _adaptiveZoom);
    final adaptiveFg = await _render(
      subject: true,
      ground: false,
      zoom: _adaptiveZoom,
    );

    // --- Android ---------------------------------------------------------
    const densities = <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    densities.forEach((density, size) {
      final dir = 'android/app/src/main/res/mipmap-$density';
      Directory(dir).createSync(recursive: true);
      _writePng('$dir/ic_launcher.png', _resize(legacy, size), alpha: true);
      // Adaptive layers are 108 dp against the legacy 48, so they scale by
      // the same 108/48 at every density.
      final layer = size * 108 ~/ 48;
      _writePng(
        '$dir/ic_launcher_background.png',
        _resize(adaptiveBg, layer),
        alpha: false,
      );
      _writePng(
        '$dir/ic_launcher_foreground.png',
        _resize(adaptiveFg, layer),
        alpha: true,
      );
    });

    const anyDpi = 'android/app/src/main/res/mipmap-anydpi-v26';
    Directory(anyDpi).createSync(recursive: true);
    // No `ic_launcher_round.xml`. The manifest declares no `android:roundIcon`,
    // and an adaptive icon is masked to whatever shape the launcher wants —
    // circle included — so a second copy of the same two layers would be an
    // unreferenced resource.
    File('$anyDpi/ic_launcher.xml').writeAsStringSync(
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
      '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
      '</adaptive-icon>\n',
    );

    // --- iOS -------------------------------------------------------------
    // Written without an alpha channel at all. iOS rejects a transparent icon
    // at submission and masks the corners itself, so these are square, opaque
    // and unrounded on purpose.
    const iosSizes = <String, int>{
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    Directory(iosDir).createSync(recursive: true);
    iosSizes.forEach((name, size) {
      _writePng('$iosDir/$name', _resize(opaque, size), alpha: false);
    });
  });
}

// --- The drawing ---------------------------------------------------------

/// Where red gives way to blue, as a y for a given x, in design space.
///
/// A tilt plus three harmonics. The tilt is what stops it reading as a
/// horizon; the fastest harmonic is what stops it reading as a wave.
double _frontier(double x) =>
    0.560 -
    0.230 * (x - 0.5) +
    0.030 * math.sin(x * 7.1 + 0.6) +
    0.017 * math.sin(x * 13.7 + 2.2) +
    0.009 * math.sin(x * 23.0 + 4.1);

/// A splat: a circle pushed out of round by four harmonics.
///
/// The frequencies are 2, 3, 5 and 7 with unrelated phases, and that is the
/// whole trick — **irregularity is what makes it read as paint.** Shallow
/// harmonics gave a lumpy potato; five even lobes gave a starfish. A splat is
/// round-ish with a few uneven bulges, and nothing about it repeats.
class _Blob {
  const _Blob(this.cx, this.cy, this.r, this.phase, {this.wobble = 1.0});
  final double cx;
  final double cy;
  final double r;
  final double phase;

  /// How far out of round. Droplets are nearly circular — a thrown speck is
  /// small enough that surface tension wins.
  final double wobble;

  /// How far the cream rim stands out past this blob.
  ///
  /// Proportional, not constant. A flat rim wide enough to read around the
  /// main splat was wider than the droplets themselves, which turned them
  /// into little white flowers.
  double get rim => math.max(0.008, r * 0.20);

  /// The outline, with the edge pushed out by [grow].
  Path path(double grow) {
    final path = Path();
    const steps = 240;
    for (var i = 0; i <= steps; i++) {
      final theta = i * 2 * math.pi / steps;
      final edge =
          r *
              (1 +
                  wobble *
                      (0.15 * math.cos(2 * theta + phase) +
                          0.11 * math.cos(3 * theta + phase * 2.3 + 1.1) +
                          0.07 * math.cos(5 * theta + phase * 0.7 + 2.9) +
                          0.04 * math.cos(7 * theta + phase * 1.9 + 0.4))) +
          grow;
      final x = cx + edge * math.cos(theta);
      final y = cy + edge * math.sin(theta);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }
}

/// The shell's splat and the droplets thrown off it.
///
/// Up and to the right, which is where the barrel is pointing: the Turret
/// aims its props to its right whenever it is not facing left. The splat sits
/// in red ground, so the icon shows paint being *taken*, which is the thing
/// the whole game is about.
///
/// Every one of these is kept **within 0.47 of the centre**, because a round
/// launcher masks an adaptive icon to a circle inscribed in the design square
/// — radius 0.5 — and the first pass put two droplets outside it. Squares and
/// squircles are forgiving; circles are what actually crop this artwork.
const List<_Blob> _splat = <_Blob>[
  _Blob(0.690, 0.285, 0.128, 2.25),
  _Blob(0.512, 0.155, 0.028, 2.1, wobble: 0.35),
  _Blob(0.815, 0.190, 0.020, 4.4, wobble: 0.35),
  _Blob(0.855, 0.410, 0.024, 1.2, wobble: 0.30),
];

/// Corner radius of the legacy square, as a fraction of its width.
const double _cornerRadius = 0.205;

/// How tall the character stands, as a fraction of the icon.
///
/// The art is authored with its feet on y = 1.0 and the Turret's barrel tip
/// near y = -1.6, so it is about 2.6 art units of character.
const double _subjectHeight = 0.66;

/// Where the character's feet rest, down the icon.
const double _subjectFeet = 0.845;

/// Renders one master layer as premultiplied RGBA, 0..1 per channel.
Future<Float64List> _render({
  required bool subject,
  bool ground = true,
  bool round = false,
  double zoom = 1.0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const double n = _master + 0.0;

  // Everything below is authored in a unit square, so the numbers in this
  // file are fractions of the icon and do not change with the output size.
  canvas.scale(n);
  if (round) {
    canvas.clipRRect(
      RRect.fromRectXY(
        const Rect.fromLTWH(0, 0, 1, 1),
        _cornerRadius,
        _cornerRadius,
      ),
    );
  }
  // Adaptive layers draw the same design smaller, so that the middle a
  // launcher actually shows matches the legacy square.
  canvas.translate(0.5, 0.5);
  canvas.scale(1 / zoom);
  canvas.translate(-0.5, -0.5);

  final brush = Paint()..isAntiAlias = true;

  if (ground) {
    // Red first, over everything including the overscan an adaptive layer
    // needs, then blue laid over the bottom along the torn edge.
    canvas.drawRect(const Rect.fromLTRB(-1, -1, 2, 2), brush..color = Palette.red);
    final below = Path()..moveTo(-1, _frontier(-1));
    for (var i = 0; i <= 400; i++) {
      final x = -1 + i * 3 / 400;
      below.lineTo(x, _frontier(x));
    }
    below
      ..lineTo(2, 2)
      ..lineTo(-1, 2)
      ..close();
    canvas.drawPath(below, brush..color = Palette.blue);
  }

  if (subject) {
    for (final blob in _splat) {
      canvas.drawPath(blob.path(blob.rim), brush..color = _cream);
      canvas.drawPath(blob.path(0), brush..color = Palette.blue);
    }

    // The game's own painter, drawn the way the arena draws it: a fat cream
    // rim first, then the character over it.
    final art = artFor(_subject);
    final pose = UnitPose()
      ..team = Team.blue
      ..facingX = 0.4
      ..facingY = 1
      ..moving = false
      // Mid-swing, so the barrel is recoiling and the muzzle has flashed —
      // which is what put the splat up there.
      ..attack = 0.45;

    canvas.save();
    // Art space: 1.0 is the unit's collision radius, feet on y = 1.0.
    final scale = _subjectHeight / 2.6;
    canvas.translate(0.5, _subjectFeet - scale);
    canvas.scale(scale);
    pose.outlinePass = true;
    art.draw(canvas, pose);
    pose.outlinePass = false;
    art.draw(canvas, pose);
    canvas.restore();
  }

  final image = await recorder.endRecording().toImage(_master, _master);
  // rawRgba is premultiplied, which is what the resampler wants: averaging
  // straight colour across a transparent edge drags black into it.
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final bytes = data!.buffer.asUint8List();
  final out = Float64List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] / 255;
  }
  return out;
}

/// Area-averages the master down to [size] square.
///
/// A box filter over the exact source rectangle each output pixel covers, so
/// the 48 px icon is a real average of 21x21 master pixels rather than a
/// point sample of one of them.
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

// --- PNG -----------------------------------------------------------------

/// Writes [pixels] (premultiplied, 0..1) as a PNG.
///
/// With [alpha] off it writes a three-channel file with no alpha channel at
/// all, which is what iOS requires — not an RGBA file that happens to be
/// opaque. Anything part-transparent is composited onto the arena floor
/// colour first, so a rounded corner never lands as black.
void _writePng(String path, Float64List pixels, {required bool alpha}) {
  final size = math.sqrt(pixels.length / 4).round();
  final channels = alpha ? 4 : 3;
  final stride = size * channels + 1;
  final raw = Uint8List(stride * size);

  for (var y = 0; y < size; y++) {
    final row = y * stride;
    raw[row] = 0; // Filter type 0: none.
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final a = pixels[i + 3];
      final o = row + 1 + x * channels;
      if (alpha) {
        // Back out of premultiplied, which is how PNG stores it.
        final inv = a > 0 ? 1 / a : 0.0;
        raw[o] = _byte(pixels[i] * inv);
        raw[o + 1] = _byte(pixels[i + 1] * inv);
        raw[o + 2] = _byte(pixels[i + 2] * inv);
        raw[o + 3] = _byte(a);
      } else {
        raw[o] = _byte(pixels[i] + _cream.r / 255 * (1 - a));
        raw[o + 1] = _byte(pixels[i + 1] + _cream.g / 255 * (1 - a));
        raw[o + 2] = _byte(pixels[i + 2] + _cream.b / 255 * (1 - a));
      }
    }
  }

  final png = BytesBuilder();
  png.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final header = BytesBuilder()
    ..add(_uint32(size))
    ..add(_uint32(size))
    ..add([8, alpha ? 6 : 2, 0, 0, 0]);
  png.add(_chunk('IHDR', header.takeBytes()));
  png.add(
    _chunk('IDAT', Uint8List.fromList(ZLibCodec(level: 9).encode(raw))),
  );
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
