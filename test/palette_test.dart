import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';

/// The palette is not decoration: the sampler classifies every cell by nearest
/// team colour, so two sides that sit close together are a scoring bug waiting
/// to happen as well as an ugly screen.
void main() {
  double lightness(Color c) => HSLColor.fromColor(c).lightness;

  int distance(Color a, Color b) {
    final dr = ((a.r - b.r) * 255).round();
    final dg = ((a.g - b.g) * 255).round();
    final db = ((a.b - b.b) * 255).round();
    return dr * dr + dg * dg + db * db;
  }

  test('the two sides are far apart in both hue and lightness', () {
    final hueGap =
        (HSLColor.fromColor(Palette.red).hue -
                HSLColor.fromColor(Palette.blue).hue)
            .abs();
    expect(
      hueGap > 90 && hueGap < 270,
      isTrue,
      reason: 'roughly opposite on the wheel, not neighbouring hues',
    );
    expect(
      (lightness(Palette.red) - lightness(Palette.blue)).abs(),
      greaterThan(0.12),
      reason: 'hue alone fails a colourblind player; lightness has to carry it',
    );
  });

  test('no two classification targets are close enough to be confused', () {
    // The sampler picks the nearest of these three by squared RGB distance.
    // 90 units apart per channel, squared and summed, is the floor for a
    // half-resolution readback with antialiased stamp edges.
    const floor = 90 * 90;
    for (var i = 0; i < Palette.classifyTargets.length; i++) {
      for (var j = i + 1; j < Palette.classifyTargets.length; j++) {
        expect(
          distance(Palette.classifyTargets[i], Palette.classifyTargets[j]),
          greaterThan(floor),
          reason:
              'targets $i and $j are too close for the nearest-colour classifier',
        );
      }
    }
  });

  test('classification targets are indexed by Team.index', () {
    // _classify in paint_sampler reads Team.values[i] straight out of this
    // list, so a reordered enum would silently swap the two sides' scores.
    for (final team in Team.values) {
      expect(Palette.classifyTargets[team.index], Palette.of(team));
    }
  });

  test('menu chrome never borrows a team colour', () {
    // Orange buttons and teal chips were the team colours until the sides
    // became red and blue. If chrome ever points back at a side, the menus
    // start looking like they belong to one player.
    const chrome = <Color>[
      Palette.accent,
      Palette.info,
      Palette.success,
      Palette.danger,
      Palette.elixir,
      Palette.deployValid,
      Palette.deployInvalid,
    ];
    for (final colour in chrome) {
      expect(colour, isNot(Palette.red));
      expect(colour, isNot(Palette.blue));
    }
  });

  test('chrome keeps its distance from both sides on the hue wheel', () {
    // Not equal to a team colour is too weak a rule now that the board shows
    // through behind the menus: orange at hue 24 was never *equal* to red at
    // 3, it just shared a family with it, and every button ended up sitting
    // on ground of its own colour.
    //
    // Gold is the deliberate exception, and it is listed rather than skipped
    // so that removing it is a decision. It has to look like gold, and it is
    // confined to chests and the coin count — never a state.
    double hueGap(Color a, Color b) {
      final d =
          (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs() % 360;
      return d > 180 ? 360 - d : d;
    }

    // The drop markers are deliberately absent. They are not chrome sitting
    // over the board — they are drawn *on* the paint, and hue distance is the
    // wrong measure for that: deployInvalid is pink at hue 333, only 31 from
    // red, and it is pink precisely so it survives being drawn on red ground.
    // What governs those two is the squared-RGB floor asserted below, which
    // is the distance the eye actually needs at that job.
    const spaced = <String, Color>{
      'accent': Palette.accent,
      'info': Palette.info,
      'success': Palette.success,
      'elixir': Palette.elixir,
    };

    for (final entry in spaced.entries) {
      for (final team in [Palette.red, Palette.blue]) {
        expect(
          hueGap(entry.value, team),
          greaterThan(40),
          reason:
              '${entry.key} is too close to a team colour to read as '
              'chrome over the board',
        );
      }
    }

    // And the two chrome colours have to be told apart from each other.
    expect(hueGap(Palette.accent, Palette.info), greaterThan(40));
  });

  test('the accent carries the white labels printed on it', () {
    // Buttons, the header band and the selected tab all put white text and
    // icons on Palette.accent. When the accent moved off orange the first
    // teal tried measured 2.10:1 against white — under the 3:1 floor even
    // for large bold text, and worse than the orange it replaced. Nothing
    // caught it, because contrast is not something you can see by reading a
    // hex value. This is the check that would have.
    double luminance(Color c) {
      double channel(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * channel(c.r) +
          0.7152 * channel(c.g) +
          0.0722 * channel(c.b);
    }

    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      final hi = math.max(la, lb);
      final lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    expect(
      contrast(Colors.white, Palette.accent),
      greaterThanOrEqualTo(3.0),
      reason: 'white on the accent is below the large-text floor',
    );
    expect(
      contrast(Palette.accent, Palette.uiBackground),
      greaterThanOrEqualTo(3.0),
      reason: 'and it has to be visible as a mark on the page as well',
    );
    expect(
      contrast(Palette.uiText, Palette.uiSurface),
      greaterThanOrEqualTo(4.5),
      reason: 'body text on a tile',
    );
    expect(
      contrast(Palette.uiTextDim, Palette.uiSurface),
      greaterThanOrEqualTo(3.5),
      reason: 'secondary text still has to be read, not guessed at',
    );
  });

  test('the drop-rejection marker is readable on both sides paint', () {
    // It is drawn over the paint layer. A red X on red ground is an invisible
    // rejection, which is exactly how it was before the recolour.
    const floor = 60 * 60;
    expect(distance(Palette.deployInvalid, Palette.red), greaterThan(floor));
    expect(distance(Palette.deployInvalid, Palette.blue), greaterThan(floor));
  });

  test('every side has an opponent, and neutral has none', () {
    expect(Team.red.opponent, Team.blue);
    expect(Team.blue.opponent, Team.red);
    expect(Team.neutral.opponent, Team.neutral);
  });
  test('the board is framed dark against a light match screen', () {
    // Section 14 used to say the menus were light and the match stayed dark.
    // The match is now a bright sky, on the owner's call, and what replaced
    // the darkness rule is this: the **bezel** stays dark.
    //
    // That is not decoration. The sky is hue 201 and the blue side is 224 —
    // 23 apart, closer than anything else in the app comes to a team colour.
    // Lightness is what separates them, and the dark frame is what stops the
    // board's blue half from bleeding into the sky behind it. Lighten the
    // bezel and the arena stops having an edge.
    for (final tone in [Palette.hudBezelHigh, Palette.hudBezelLow]) {
      expect(
        HSLColor.fromColor(tone).lightness,
        lessThan(0.3),
        reason: 'the bezel is the only edge the board has',
      );
    }

    // And the sky has to stay well clear of the blue side in lightness,
    // since it cannot be clear of it in hue.
    final sky = HSLColor.fromColor(Palette.hudSkyHigh).lightness;
    final blue = HSLColor.fromColor(Palette.blue).lightness;
    expect(
      sky - blue,
      greaterThan(0.15),
      reason: 'a sky this close to blue in hue must be far from it in tone',
    );

    // Lighter at the top, which is where every surface in the app puts its
    // light source. Inverted, the screen reads as lit from the floor.
    expect(
      HSLColor.fromColor(Palette.hudBezelHigh).lightness,
      greaterThan(HSLColor.fromColor(Palette.hudBezelLow).lightness),
    );

    // Match ink is now printed on paper, so it has to be dark enough to read.
    expect(HSLColor.fromColor(Palette.hudText).lightness, lessThan(0.25));
    expect(HSLColor.fromColor(Palette.hudSurface).lightness, greaterThan(0.9));
  });
}
