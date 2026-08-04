/// Global tuning values that are structural rather than balance.
///
/// Balance numbers (card stats, upgrade costs, bot decks) live in
/// `assets/data/*.json` and must never be hardcoded here.
library;

class ArenaSpec {
  const ArenaSpec._();

  /// Arena size in world units. One world unit is roughly one unit body width.
  static const double worldWidth = 16.0;
  static const double worldHeight = 24.0;

  /// Paint grid used for coverage scoring. Matches the 2:3 arena aspect.
  static const int gridCols = 64;
  static const int gridRows = 96;

  /// Backing paint image resolution: half the nominal arena resolution.
  static const int paintImageWidth = 512;
  static const int paintImageHeight = 768;

  /// Rows of the arena, in world units, owned by each side at match start.
  ///
  /// The two halves meet in the middle and there is no neutral strip: the
  /// board starts 50/50, so the coverage bar starts level and every cell
  /// belongs to somebody. Neutral ground still exists, but only where the
  /// Solvent spell makes it.
  static const double startBandPlayer = worldHeight / 2;
  static const double startBandBot = worldHeight / 2;

  /// Paint grid cells per world unit. The grid is 2:3 like the arena, so this
  /// is the same on both axes — 64/16 == 96/24 == 4.
  static const double cellsPerUnit = gridCols / worldWidth;

  /// Pixels of the paint image per grid cell. 512/64 == 768/96 == 8, so a
  /// cell is a whole number of pixels and paint lines up exactly with the
  /// grid it is scored on.
  static const int pixelsPerCellX = paintImageWidth ~/ gridCols;
  static const int pixelsPerCellY = paintImageHeight ~/ gridRows;

  /// Pixels of the paint image per world unit.
  static double get pixelsPerUnitX => paintImageWidth / worldWidth;
  static double get pixelsPerUnitY => paintImageHeight / worldHeight;
}

class Timings {
  const Timings._();

  /// Painting units stamp on a fixed tick, not every frame.
  static const double stampTick = 0.1; // 10 Hz

  /// Coverage readback cadence.
  static const double coverageSampleTick = 0.5;

  /// How often the paint layer burns its queued stamps into the image.
  ///
  /// Baking allocates a fresh 1.5 MB texture, so it is deliberately slower
  /// than the frame rate. Anything queued since the last bake is drawn live
  /// on top, so nothing looks delayed — see [PaintLayer.renderPending].
  static const double paintBakeTick = 0.05; // 20 Hz

  /// Coverage bar lerp so the split slides instead of jumping.
  static const Duration coverageLerp = Duration(milliseconds: 300);

  /// Unit AI re-target cadence.
  static const double aiTick = 0.2;

  /// Bot decision cadence.
  static const double botTick = 0.5;

  /// Match phases.
  static const double countdown = 3.0;
  static const double normalTime = 90.0;
  static const double suddenDeathTime = 30.0;

  /// Coverage gap under which the match goes to sudden death.
  static const double suddenDeathThreshold = 0.05;

  /// Instant win: hold this coverage for [instantWinHold] continuous seconds.
  static const double instantWinCoverage = 0.95;
  static const double instantWinHold = 3.0;

  /// Corpse lingers this long after the die animation starts.
  static const double deathFadeOut = 0.6;
}

class ElixirSpec {
  const ElixirSpec._();

  static const double max = 10.0;
  static const double start = 5.0;

  /// Seconds per elixir.
  static const double regenNormal = 2.0;
  static const double regenSuddenDeath = 1.0;

  static const int deckSize = 8;
  static const int handSize = 4;
}

class PerfBudget {
  const PerfBudget._();

  static const int maxLiveParticles = 300;

  /// Section 13: 60fps with this many units on a mid-range device.
  static const int targetFps = 60;
  static const int unitBudget = 40;
}
