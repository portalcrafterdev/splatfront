import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/cards/card_model.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/units/unit_art.dart';
import 'package:splatfront/game/units/units_registry.dart';
import 'package:splatfront/ui/widgets/card_tile.dart';
import 'package:splatfront/ui/widgets/unit_art_view.dart';

/// Every troop has a character, and drawing one never throws.
void main() {
  late UnitsRegistry troops;
  late CardRegistry cards;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    troops = await UnitsRegistry.load();
    cards = await CardRegistry.load();
  });

  test('every troop in cards.json has its own art', () {
    for (final stats in troops.all) {
      expect(
        unitArt.containsKey(stats.id),
        isTrue,
        reason: '${stats.id} falls back to the generic body',
      );
    }
  });

  test('the art registry has no ids that are not troops', () {
    for (final id in unitArt.keys) {
      expect(troops.contains(id), isTrue, reason: '$id is not a troop');
    }
  });

  test('an unknown id still gets something to draw', () {
    expect(artFor('not_a_card'), isNotNull);
  });

  test('every character draws in every pose without throwing', () {
    // The whole state space the arena can put a unit in: either team, walking
    // or standing, facing the camera or away, mid-swing, and part-faded on
    // the way out.
    for (final id in unitArt.keys) {
      for (final team in [Team.red, Team.blue]) {
        for (final facingY in [1.0, -1.0]) {
          for (final attack in [0.0, 0.5, 1.0]) {
            for (final moving in [true, false]) {
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder);
              final pose = UnitPose()
                ..team = team
                ..facingY = facingY
                ..facingX = facingY * 0.4
                ..walk = 1.2
                ..attack = attack
                ..moving = moving
                ..alpha = attack == 1.0 ? 0.4 : 1.0;

              expect(
                () => artFor(id).draw(canvas, pose),
                returnsNormally,
                reason: '$id, ${team.name}, facingY $facingY',
              );
              recorder.endRecording().dispose();
            }
          }
        }
      }
    }
  });

  test('a pose picks up the colours of the team it is set to', () {
    final pose = UnitPose()..team = Team.red;
    final redBody = pose.body;
    pose.team = Team.blue;
    final blueBody = pose.body;

    expect(redBody, isNot(blueBody), reason: 'the sides must be told apart');
    // Deliberately a shade under the paint: a body the exact colour of the
    // ground it is standing on cannot be seen at all.
    expect(redBody, isNot(Palette.red));
    expect(blueBody, isNot(Palette.blue));
    // Still recognisably the team's colour, not a repaint of it.
    expect(
      HSLColor.fromColor(blueBody).hue,
      closeTo(HSLColor.fromColor(Palette.blue).hue, 1.0),
    );
    // The shade and the highlight have to differ from the body, or the whole
    // character flattens into one silhouette.
    expect(pose.dark, isNot(pose.body));
    expect(pose.light, isNot(pose.body));
  });

  test('no two bipeds share a silhouette', () async {
    final shapes = <String, ({double aspect, double fill})>{};
    for (final id in _bipeds) {
      shapes[id] = await _silhouette(id);
    }

    // The measured spread, for anyone moving these numbers:
    //
    //   pin        0.411   the tall lean one
    //   brusher    0.602   short and solid
    //   sprayer    0.744   squat and round
    //   warden     0.824   broad, with the shield
    //   sniper_nib 1.062   crouched behind the longest gun
    //
    // The tightest pair is sprayer/warden at 0.080, which is the two broad
    // bodies. 0.07 is therefore the floor, and it is a floor rather than a
    // target: the three that actually collided sit 0.14 and 0.19 apart.
    const floor = 0.07;

    for (final a in _bipeds) {
      for (final b in _bipeds) {
        if (a.compareTo(b) >= 0) continue;
        final gap = (shapes[a]!.aspect - shapes[b]!.aspect).abs();
        expect(
          gap,
          greaterThanOrEqualTo(floor),
          reason:
              '$a and $b are the same shape (aspect ${shapes[a]!.aspect
                  .toStringAsFixed(3)} against ${shapes[b]!.aspect
                  .toStringAsFixed(3)}). At hand-card size that makes them '
              'the same card. Change one body, not one tool — the tool is '
              'the smallest mark on the drawing.',
        );
      }
    }
  });

  testWidgets('a troop card draws the character it deploys', (tester) async {
    final roller = cards['roller'];
    expect(roller.kind, CardKind.troop);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: CardTile(card: roller, width: 78)),
      ),
    );

    expect(find.byType(UnitArtView), findsOneWidget);
    expect(find.text('Roller'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a spell card shows its own mark, not a body', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: CardTile(card: cards['freeze'], width: 78)),
      ),
    );

    expect(find.byType(UnitArtView), findsNothing);
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
  });
}

/// The bipeds, and how far apart their bodies are.
///
/// Five cards share [_biped]'s body, and the tool each one carries is the
/// smallest mark on the drawing. At the 60dp a hand card gets, a shared
/// silhouette means a shared card: Brusher, Pin and Sprayer once sat inside
/// 20% of each other on every proportion, and read as one blue figure three
/// times.
///
/// This measures what the eye actually gets — the drawn silhouette — rather
/// than the numbers passed to [_biped], which are private and which a tool
/// can widen without widening the shape.
const _bipeds = ['brusher', 'pin', 'sprayer', 'sniper_nib', 'warden'];

/// Width over height of [id]'s drawn silhouette, and how much of its
/// bounding box it fills.
Future<({double aspect, double fill})> _silhouette(String id) async {
  const size = 160;
  const scale = 34.0;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(size / 2, size / 2 + scale * 0.5);
  canvas.scale(scale);
  artFor(id).draw(canvas, UnitPose()..team = Team.blue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();

  var minX = size, minY = size, maxX = -1, maxY = -1, lit = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // Alpha only. The shadow under the feet is part of the drawing but not
      // part of the body, and it is the one mark every character shares.
      if (bytes!.getUint8((y * size + x) * 4 + 3) < 128) continue;
      lit++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  final w = (maxX - minX + 1).toDouble();
  final h = (maxY - minY + 1).toDouble();
  return (aspect: w / h, fill: lit / (w * h));
}
