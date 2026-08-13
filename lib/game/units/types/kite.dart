import 'package:flame/components.dart';

import '../../../core/palette.dart';
import '../unit.dart';
import '../unit_stats.dart';

/// The set's only flyer: it crosses blockers and ground units alike.
///
/// Fully stat-driven: everything that makes it distinct lives in
/// `cards.json`. This type names it and gives its Rive artboard a home.
class Kite extends Unit {
  Kite({required super.stats, required super.team, required super.position});

  static const String id = 'kite';
  static const String riveArtboard = 'kite';

  static Kite spawn(UnitStats stats, Team team, Vector2 position) =>
      Kite(stats: stats, team: team, position: position);
}
