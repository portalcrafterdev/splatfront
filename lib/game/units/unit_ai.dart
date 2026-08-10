import 'dart:math' as math;

import 'package:flame/components.dart';

import '../arena/arena_layout.dart';
import 'unit.dart';

/// Targeting and steering. No navmesh, no A*, on purpose: units are supposed
/// to read as simple and predictable so players can plan a push.
///
/// Every helper writes into a caller-owned vector rather than returning a new
/// one, because steering runs per unit per frame.
class UnitAi {
  const UnitAi._();

  /// How hard a unit is pushed out of a blocker it has walked into.
  static const double _blockerPush = 2.0;

  /// How hard it slides sideways along the blocker face while pushed out.
  /// Without this a unit walking head-on just stalls against the wall.
  static const double _blockerSlide = 1.6;

  /// How hard allies push each other apart, so they do not stack into one
  /// pixel. Deliberately soft: it should loosen a clump, not scatter a push.
  static const double _separationPush = 0.9;

  /// Clearance kept around a blocker's edge.
  static const double _blockerMargin = 0.12;

  /// Nearest enemy this unit is allowed to shoot at, within its aggro range.
  ///
  /// Returns null when there is nothing to fight, which sends the unit walking
  /// up its lane toward the enemy base instead.
  static Unit? findTarget(Unit self, List<Unit> units) {
    if (self.stats.aggroRange <= 0) {
      // "Walks straight": never diverts to chase. It still hits whatever is
      // already standing in its way, which the melee check below covers.
      return _firstInReach(self, units);
    }

    Unit? best;
    var bestDistSq = self.stats.aggroRange * self.stats.aggroRange;

    for (var i = 0; i < units.length; i++) {
      final other = units[i];
      if (!_isValidTarget(self, other)) continue;

      final distSq = self.position.distanceToSquared(other.position);
      if (distSq <= bestDistSq) {
        bestDistSq = distSq;
        best = other;
      }
    }
    return best;
  }

  /// Anything already within attack reach, for units that do not chase.
  static Unit? _firstInReach(Unit self, List<Unit> units) {
    for (var i = 0; i < units.length; i++) {
      final other = units[i];
      if (!_isValidTarget(self, other)) continue;
      if (self.isInReachOf(other)) return other;
    }
    return null;
  }

  static bool _isValidTarget(Unit self, Unit other) =>
      other.team != self.team &&
      other.isAlive &&
      self.stats.targets.canHit(flying: other.stats.flying);

  /// Pushes [self] out of any blocker it is overlapping or about to clip.
  ///
  /// Air units never call this: they fly over blockers and ground units alike.
  static void avoidBlockers(Unit self, List<Blocker> blockers, Vector2 out) {
    final clearance = self.stats.radius + _blockerMargin;

    for (var i = 0; i < blockers.length; i++) {
      final rect = blockers[i].rect;

      // Closest point on the rectangle to the unit.
      final cx = self.position.x.clamp(rect.left, rect.right);
      final cy = self.position.y.clamp(rect.top, rect.bottom);
      final dx = self.position.x - cx;
      final dy = self.position.y - cy;
      final dist = math.sqrt(dx * dx + dy * dy);

      if (dist >= clearance) continue;

      if (dist < 1e-4) {
        // Dead centre of the blocker: shove it out the nearest side.
        final toLeft = self.position.x - rect.left;
        final toRight = rect.right - self.position.x;
        final toTop = self.position.y - rect.top;
        final toBottom = rect.bottom - self.position.y;
        final smallest = math.min(
          math.min(toLeft, toRight),
          math.min(toTop, toBottom),
        );
        if (smallest == toLeft) {
          out.x -= _blockerPush;
        } else if (smallest == toRight) {
          out.x += _blockerPush;
        } else if (smallest == toTop) {
          out.y -= _blockerPush;
        } else {
          out.y += _blockerPush;
        }
        continue;
      }

      final strength = (clearance - dist) / clearance * _blockerPush;
      out.x += dx / dist * strength;
      out.y += dy / dist * strength;

      // Radial push alone just jams a unit against the face it walked into:
      // the push and its goal cancel out and it stops dead. A tangential
      // slide toward the nearer corner is what actually gets it around.
      if (dy.abs() >= dx.abs()) {
        final exitLeft = self.position.x - (rect.left - clearance);
        final exitRight = (rect.right + clearance) - self.position.x;
        out.x += (exitLeft < exitRight ? -1 : 1) * strength * _blockerSlide;
      } else {
        final exitTop = self.position.y - (rect.top - clearance);
        final exitBottom = (rect.bottom + clearance) - self.position.y;
        out.y += (exitTop < exitBottom ? -1 : 1) * strength * _blockerSlide;
      }
    }
  }

  /// Soft separation from allies, so a stack of Swarmlets spreads out instead
  /// of occupying one point.
  static void separateFromAllies(Unit self, List<Unit> units, Vector2 out) {
    for (var i = 0; i < units.length; i++) {
      final other = units[i];
      if (identical(other, self) || other.team != self.team) continue;
      if (!other.isAlive) continue;
      // Ground and air units occupy different space and never jostle.
      if (other.stats.flying != self.stats.flying) continue;

      final dx = self.position.x - other.position.x;
      final dy = self.position.y - other.position.y;
      final wanted = self.stats.radius + other.stats.radius;
      final distSq = dx * dx + dy * dy;
      if (distSq >= wanted * wanted) continue;

      final dist = math.sqrt(distSq);
      if (dist < 1e-4) {
        // Perfectly co-located: nudge apart deterministically by spawn order.
        out.x += self.hashCode.isEven ? _separationPush : -_separationPush;
        continue;
      }

      final strength = (wanted - dist) / wanted * _separationPush;
      out.x += dx / dist * strength;
      out.y += dy / dist * strength;
    }
  }
}
