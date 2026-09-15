import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two bundled faces load, and their weight axis actually moves.
///
/// Both are **variable** fonts — the only form Google ships Baloo 2 and
/// Lexend in — so one file carries every weight on a `wght` axis rather than
/// one file per weight. Flutter is supposed to drive that axis from
/// [TextStyle.fontWeight], but if it does not, the failure is silent: every
/// weight in the app renders as the font's default instance, the layout is
/// unchanged, and the only symptom is that nothing ever looks bold. Headings
/// set at w800 would come out the same as body text.
///
/// So this measures ink. A heavier weight puts down more of it.
///
/// Note the [FontLoader]: `flutter test` does **not** read the `fonts:`
/// section of pubspec.yaml. Without loading the file by hand every test in
/// the suite measures a fallback face, which is why nothing else in the suite
/// can see a font problem.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> loadFont(String family, String path) async {
    final loader = FontLoader(family)..addFont(rootBundle.load(path));
    await loader.load();
  }

  setUpAll(() async {
    await loadFont('Baloo2', 'assets/fonts/Baloo2.ttf');
    await loadFont('Lexend', 'assets/fonts/Lexend.ttf');
  });

  /// How many pixels the word puts down, drawn in [family] at [weight].
  Future<int> ink(String family, FontWeight weight) async {
    final painter = TextPainter(
      text: TextSpan(
        text: 'SPLATFRONT',
        style: TextStyle(
          fontFamily: family,
          fontSize: 48,
          fontWeight: weight,
          color: const Color(0xFF000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const w = 512, h = 96;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    image.dispose();

    var lit = 0;
    for (var i = 0; i < w * h; i++) {
      if (bytes!.getUint8(i * 4 + 3) > 128) lit++;
    }
    return lit;
  }

  for (final family in ['Baloo2', 'Lexend']) {
    test('$family is a real family, not a fallback', () async {
      // A missing family falls back, and the fallback is the same face for
      // both — so if these two ever measure identically, neither loaded.
      expect(await ink(family, FontWeight.w400), greaterThan(0));
    });

    test('$family gets heavier when asked to', () async {
      final light = await ink(family, FontWeight.w400);
      final heavy = await ink(family, FontWeight.w800);

      // 5% is a floor, not a target: the measured spread is far wider. It is
      // set low enough that only a genuinely dead axis trips it.
      expect(
        heavy,
        greaterThan(light * 1.05),
        reason:
            '$family w800 put down $heavy pixels against w400\'s $light. The '
            'variable weight axis is not being driven, so every heading in '
            'the app is rendering at the default instance. The fix is '
            'fontVariations, not a heavier fontWeight.',
      );
    });
  }

  test('the two faces are actually different faces', () async {
    // Guards the case where one asset path is wrong and both families
    // resolve to the same loaded font.
    final baloo = await ink('Baloo2', FontWeight.w400);
    final lexend = await ink('Lexend', FontWeight.w400);
    expect(baloo, isNot(lexend));
  });
}
