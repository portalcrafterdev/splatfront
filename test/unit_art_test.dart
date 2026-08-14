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
