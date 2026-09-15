/// The two faces the app is set in.
///
/// **Lexend is the default and is set once, on [ThemeData.fontFamily].**
/// Nothing needs to ask for it — every widget that does not name a family
/// gets it. It is the substantive half of the pair: Lexend was designed and
/// tested to raise reading speed, its letterforms are wide and unambiguous,
/// and it never ligates, which matters when the reader is seven.
///
/// **Baloo 2 is the display face and is always asked for by name.** Round,
/// heavy and slightly bouncy — a toy voice without being a novelty face, and
/// heavy enough to survive the outline every shape in this UI carries. It is
/// for things that are shouted, not read: the wordmark, a level number, a
/// button, a score, the word on a result screen. Prose is never set in it.
///
/// Both are variable fonts, so one file carries every weight and
/// [TextStyle.fontWeight] drives the `wght` axis directly.
/// `fonts_test.dart` proves the axis actually moves — if it ever stops, every
/// heading in the app quietly renders at Regular and nothing else fails.
library;

import 'package:flutter/widgets.dart';

abstract final class Fonts {
  /// The display face. Name it explicitly; it is never the default.
  static const String display = 'Baloo2';

  /// The body face. Set on the theme, so this constant is only needed where
  /// a style is built outside the theme's reach — a `CustomPainter`, or a
  /// `TextPainter` in the arena.
  static const String body = 'Lexend';

  /// A display style, for the shouted things.
  ///
  /// Defaults to w800 because that is what the face is for here; drop to
  /// w600 for a display line that should not be the loudest thing on screen.
  static TextStyle shout({
    required double size,
    Color? colour,
    FontWeight weight = FontWeight.w800,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: weight,
    color: colour,
    letterSpacing: letterSpacing,
    height: height,
    shadows: shadows,
  );
}
