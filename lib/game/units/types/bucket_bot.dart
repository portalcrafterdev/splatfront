import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// The tank. Soaks damage at the front while a Roller paints behind it.
///
/// Fully stat-driven: everything that makes it distinct lives in
/// `cards.json`. This type names it and gives its Rive artboard a home.
class BucketBot extends Unit {
  BucketBot({
    required super.stats,
    required super.team,
    required super.position,
  });

  static const String id = 'bucket_bot';
  static const String riveArtboard = 'bucket_bot';

  static BucketBot spawn(UnitStats stats, Team team, Vector2 position) =>
      BucketBot(stats: stats, team: team, position: position);
}
