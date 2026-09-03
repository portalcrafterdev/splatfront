import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/arena/deploy_zone.dart';

/// Owner grid split like the match start state: bot on top, player at bottom,
/// meeting in the middle with no neutral ground between them.
Uint8List _startOwners() {
  final owners = Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows);
  const botRows =
      ArenaSpec.gridRows * ArenaSpec.startBandBot ~/ ArenaSpec.worldHeight;
  for (var row = 0; row < ArenaSpec.gridRows; row++) {
    final team = row < botRows ? Team.blue : Team.red;
    for (var col = 0; col < ArenaSpec.gridCols; col++) {
      owners[DeployZone.cellIndex(col, row)] = team.index;
    }
  }
  return owners;
}

void main() {
  late DeployZone zone;

  setUp(() {
    zone = DeployZone()..updateOwners(_startOwners());
  });

  test('you may deploy on your own colour', () {
    expect(zone.canDeploy(Vector2(8, 22), Team.red), isTrue);
    expect(zone.canDeploy(Vector2(8, 2), Team.blue), isTrue);
  });

  test('you may not deploy on the enemy colour', () {
    expect(zone.canDeploy(Vector2(8, 2), Team.red), isFalse);
    expect(zone.canDeploy(Vector2(8, 22), Team.blue), isFalse);
  });

  test('neutral ground blocks both sides', () {
    // A match starts with no neutral ground; Solvent is what makes it. This
    // wipes one cell of the player's own half the same way.
    final wiped = Vector2(8, 22);
    expect(zone.canDeploy(wiped, Team.red), isTrue);

    final owners = _startOwners();
    owners[DeployZone.cellIndex(
          DeployZone.colAt(wiped.x),
          DeployZone.rowAt(wiped.y),
        )] =
        Team.neutral.index;
    zone.updateOwners(owners);

    expect(zone.ownerAt(wiped), Team.neutral);
    expect(zone.canDeploy(wiped, Team.red), isFalse);
    expect(zone.canDeploy(wiped, Team.blue), isFalse);
  });

  test('painting forward extends the deploy line', () {
    final target = Vector2(8, 9);
    expect(zone.canDeploy(target, Team.red), isFalse);

    // Recolour that cell to red, as a Roller walking up would.
    final owners = _startOwners();
    owners[DeployZone.cellIndex(
          DeployZone.colAt(target.x),
          DeployZone.rowAt(target.y),
        )] =
        Team.red.index;
    zone.updateOwners(owners);

    expect(zone.canDeploy(target, Team.red), isTrue);
  });

  test('out of bounds is never deployable', () {
    expect(zone.canDeploy(Vector2(-1, 22), Team.red), isFalse);
    expect(
      zone.canDeploy(Vector2(8, ArenaSpec.worldHeight + 1), Team.red),
      isFalse,
    );
  });

  test('blockers are undeployable even on your own colour', () {
    final layout = ArenaLayout.fromJson({
      'id': 'test',
      'name': 'test',
      'trophies': 0,
      'floor': '#F6F1E7',
      'blockers': [
        {'x': 6.0, 'y': 20.0, 'w': 4.0, 'h': 2.0},
      ],
    });
    zone.updateBlocked(layout.buildBlockedMask());

    final onBlocker = Vector2(8, 21);
    expect(
      zone.ownerOf(DeployZone.colAt(8), DeployZone.rowAt(21)),
      Team.red,
      reason: 'the cell under the blocker is red ground',
    );
    expect(zone.canDeploy(onBlocker, Team.red), isFalse);
    expect(zone.canDeploy(Vector2(2, 21), Team.red), isTrue);
  });

  test('valid cells enumerate only your own unblocked ground', () {
    var count = 0;
    zone.forEachValidCell(Team.red, (col, row) {
      expect(zone.ownerOf(col, row), Team.red);
      count++;
    });
    const expected =
        ArenaSpec.gridCols *
        (ArenaSpec.gridRows *
            ArenaSpec.startBandPlayer ~/
            ArenaSpec.worldHeight);
    expect(count, expected);
  });

  test('cell centres round-trip through the world transform', () {
    for (final cell in [
      [0, 0],
      [63, 95],
      [32, 48],
    ]) {
      final centre = DeployZone.cellCentre(cell[0], cell[1]);
      expect(DeployZone.colAt(centre.x), cell[0]);
      expect(DeployZone.rowAt(centre.y), cell[1]);
    }
  });
}
