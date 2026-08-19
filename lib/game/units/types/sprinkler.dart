import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../building.dart';
import '../unit_stats.dart';

/// Paints, and does nothing else.
///
/// No damage and no attack at all — its `damage` is zero in `cards.json`, so
/// the ordinary combat loop has nothing to do for it. What it does have is
/// the widest stamp in the game, laid down in place every tick, which turns a
/// patch of ground your colour and keeps it that way while it lasts. Cheap,
/// defenceless, and the fastest coverage in the set.
class Sprinkler extends Building {
  Sprinkler({
    required super.stats,
    required super.team,
    required super.position,
  });

  static const String id = 'sprinkler';
  static const String riveArtboard = 'sprinkler';

  static Sprinkler spawn(UnitStats stats, Team team, Vector2 position) =>
      Sprinkler(stats: stats, team: team, position: position);
}
