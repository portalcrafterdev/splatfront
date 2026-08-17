import 'dart:typed_data';

import 'package:flame/components.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';

/// "Can I place here?"
///
/// A troop may only be dropped on a cell that is currently **your** colour.
/// Neutral (solvent-wiped) ground belongs to nobody, so it blocks both sides.
/// Spells ignore all of this and may target anywhere.
class DeployZone {
  DeployZone();

  /// [Team.index] per grid cell, row-major. Refreshed by the coverage sampler
  /// every [Timings.coverageSampleTick]; a half-second-stale deploy map is
  /// both cheap and stable under the finger.
  Uint8List _owners = Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows)
    ..fillRange(0, ArenaSpec.gridCols * ArenaSpec.gridRows, Team.neutral.index);

  Uint8List _blocked = Uint8List(ArenaSpec.gridCols * ArenaSpec.gridRows);

  Uint8List get owners => _owners;

  /// Bumped on every resample. The deploy glow caches its geometry and uses
  /// this to know when the map underneath it actually changed.
  int get version => _version;
  int _version = 0;

  void updateOwners(Uint8List owners) {
    _owners = owners;
    _hasOwners = true;
    _version++;
  }

  void updateBlocked(Uint8List blocked) {
    _blocked = blocked;
    _version++;
  }

  static int cellIndex(int col, int row) => row * ArenaSpec.gridCols + col;

  static int colAt(double worldX) =>
      (worldX / ArenaSpec.worldWidth * ArenaSpec.gridCols).floor();

  static int rowAt(double worldY) =>
      (worldY / ArenaSpec.worldHeight * ArenaSpec.gridRows).floor();

  static bool inBounds(int col, int row) =>
      col >= 0 &&
      col < ArenaSpec.gridCols &&
      row >= 0 &&
      row < ArenaSpec.gridRows;

  /// Centre of a grid cell in world units.
  static Vector2 cellCentre(int col, int row) => Vector2(
    (col + 0.5) / ArenaSpec.gridCols * ArenaSpec.worldWidth,
    (row + 0.5) / ArenaSpec.gridRows * ArenaSpec.worldHeight,
  );

  Team ownerOf(int col, int row) {
    if (!inBounds(col, row)) return Team.neutral;
    return Team.values[_owners[cellIndex(col, row)]];
  }

  Team ownerAt(Vector2 worldPos) =>
      ownerOf(colAt(worldPos.x), rowAt(worldPos.y));

  bool isBlocked(int col, int row) =>
      inBounds(col, row) && _blocked[cellIndex(col, row)] != 0;

  /// The deploy rule itself.
  bool canDeploy(Vector2 worldPos, Team team) {
    final col = colAt(worldPos.x);
    final row = rowAt(worldPos.y);
    if (!inBounds(col, row)) return false;
    if (isBlocked(col, row)) return false;
    return _owners[cellIndex(col, row)] == team.index;
  }

  /// Whether a real sample has landed yet.
  ///
  /// The grid starts all-neutral, which reads as "nobody owns anything" — and
  /// a unit asking where the frontier is would be told it is standing on it.
  /// Callers fall back to something sane until the first readback arrives.
  bool get hasOwners => _hasOwners;
  bool _hasOwners = false;

  /// How far up its lane a unit of [team] should walk: the first ground in
  /// this column that the team does not already own.
  ///
  /// This is the objective in a game scored on coverage. There is no base to
  /// reach and nothing at the far edge to break, so a unit that marched to the
  /// end walked off the only ground worth fighting over. Walking to the near
  /// side of enemy paint instead puts it exactly where its own paint stops.
  ///
  /// A single column scan, at most [ArenaSpec.gridRows] reads and usually far
  /// fewer, run once per AI tick rather than per frame.
  double frontierY(double worldX, Team team, double fromY, double forward) {
    final col = colAt(worldX).clamp(0, ArenaSpec.gridCols - 1);
    final step = forward > 0 ? 1 : -1;
    var row = rowAt(fromY).clamp(0, ArenaSpec.gridRows - 1);

    while (row >= 0 && row < ArenaSpec.gridRows) {
      final i = cellIndex(col, row);
      // A wall is not ground anybody can take, so it is not a destination.
      if (_blocked[i] == 0 && _owners[i] != team.index) {
        return (row + 0.5) / ArenaSpec.gridRows * ArenaSpec.worldHeight;
      }
      row += step;
    }

    // It owns this whole column. Nothing left to take here, so it keeps going.
    return forward > 0 ? ArenaSpec.worldHeight : 0.0;
  }

  /// Every cell [team] may currently drop on, for the soft glow shown while
  /// dragging a card.
  void forEachValidCell(Team team, void Function(int col, int row) visit) {
    for (var row = 0; row < ArenaSpec.gridRows; row++) {
      final base = row * ArenaSpec.gridCols;
      for (var col = 0; col < ArenaSpec.gridCols; col++) {
        if (_blocked[base + col] != 0) continue;
        if (_owners[base + col] == team.index) visit(col, row);
      }
    }
  }
}
