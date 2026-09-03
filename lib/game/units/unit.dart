import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/audio.dart';
import '../../core/constants.dart';
import '../../core/palette.dart';
import '../splatfront_game.dart';
import 'unit_ai.dart';
import 'unit_art.dart';
import 'unit_stats.dart';

/// Base for every troop on the field.
///
/// Behaviour is entirely stat-driven, so the three Phase 2 units and the
/// thirteen that follow share this one loop. Subclasses in `types/` exist for
/// the pieces that are genuinely code — Rive wiring, auras, splash — not to
/// restate numbers that belong in `cards.json`.
class Unit extends PositionComponent with HasGameReference<SplatfrontGame> {
  Unit({required this.stats, required this.team, required Vector2 position})
    : hp = stats.hp,
      lane = position.x,
      _lastStampPos = position.clone(),
      super(
        position: position,
        anchor: Anchor.center,
        size: Vector2.all(stats.radius * 2),
        priority: stats.flying ? 20 : 10,
      );

  final UnitStats stats;
  final Team team;

  /// The x it was deployed on. With nothing to fight, it walks straight up
  /// this lane toward the enemy base.
  final double lane;

  double hp;

  bool get isAlive => hp > 0 && !_dying;
  bool get isDying => _dying;
  double get healthFraction => (hp / stats.hp).clamp(0.0, 1.0);

  Unit? get target => _target;

  bool _dying = false;
  double _deathTimer = 0;

  Unit? _target;

  /// Primed so the first update acquires a target, rather than walking blind
  /// for a fifth of a second after landing.
  double _aiTimer = Timings.aiTick;
  double _stampTimer = 0;
  double _attackTimer = 0;

  final Vector2 _lastStampPos;

  /// Where it was dropped. It works this post rather than the far wall.
  late final Vector2 _home = position.clone();

  /// The row its push is measured from: the frontier in its column at the
  /// moment it landed, which is where its own side's ground stops.
  ///
  /// Null until the first update, and null for good when the frontier could
  /// not be read — see [_startLine].
  double? _pushFrom;
  bool _pushFromResolved = false;

  /// Scratch vectors. Steering runs for every unit every frame, so none of it
  /// is allowed to allocate.
  final Vector2 _desired = Vector2.zero();
  final Vector2 _steer = Vector2.zero();

  /// Caps how much ground one stamp tick may cover, so a frame spike cannot
  /// turn into hundreds of stamps.
  static const int _maxTrailSteps = 6;

  // --- Animation state ---------------------------------------------------
  // Read by [UnitArt] and nothing else. None of it feeds back into gameplay,
  // so a dropped frame costs a wobble and never a hit.

  /// Radians through the walk cycle. Advances with distance covered, so a
  /// Roller plods and a Dab scurries without either being told to.
  double _walkPhase = 0;

  /// Idle breathing, on the clock rather than on distance covered, so a unit
  /// standing still still moves.
  double _breath = 0;

  /// 1 the instant a swing lands, decaying to 0 over [_swingTime].
  double _attackAnim = 0;

  /// Which way the character is drawn facing, smoothed: a unit shouldering
  /// past an ally should not flip round twice on the way.
  double _faceX = 0;
  double _faceY = 0;

  bool _walking = false;

  /// 1 the frame a hit lands, fading over [_flashTime]. Feedback only — the
  /// damage itself has already been applied.
  double _flash = 0;

  static const double _swingTime = 0.22;
  static const double _flashTime = 0.12;

  /// Characters are drawn this much bigger than their collision radius.
  static const double _artScale = 1.15;

  late final UnitArt _art = artFor(stats.id);

  /// One pose, shared by every unit. Rendering is sequential on one thread,
  /// so forty units can take turns with it instead of allocating forty.
  static final UnitPose _pose = UnitPose();

  /// Turns the character toward ([dx], [dy]). Ignores a zero vector, and
  /// snaps rather than eases on the first call so a unit is never drawn
  /// facing nowhere on its first frame.
  void _faceToward(double dx, double dy, double dt) {
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-4) return;
    final tx = dx / length;
    final ty = dy / length;
    if (_faceX == 0 && _faceY == 0) {
      _faceX = tx;
      _faceY = ty;
      return;
    }
    final k = (dt * 8).clamp(0.0, 1.0);
    _faceX += (tx - _faceX) * k;
    _faceY += (ty - _faceY) * k;
  }

  /// True once it has pushed its whole advance past the line it started from.
  ///
  /// Measured from the **frontier**, not from the drop point. Crossing your
  /// own paint costs a unit nothing and gains it nothing, so charging that
  /// walk against the leash meant where you dropped a card decided whether it
  /// ever reached the fighting: dropped in the middle of your own half, six
  /// units of advance ran out exactly on the halfway line and the unit stood
  /// there. Measured from the frontier, [advanceRange] is what it says it is
  /// — how deep into contested ground one card pushes.
  bool get _hasAdvanced {
    if (_atMidline) return true;
    final line = _startLine;
    if (line == null) {
      // No frontier to measure from: the column is entirely this side's, so
      // there is nothing ahead to take. Fall back to the drop point, which
      // keeps a winning side's units from walking off to the far wall.
      return position.distanceToSquared(_home) >= _advanceRangeSquared;
    }
    final pushed = goalY < line ? line - position.y : position.y - line;
    return pushed >= game.registry.tuning.advanceRange;
  }

  /// True once a unit that started on its own side has reached the middle.
  ///
  /// The halfway line rather than a distance, because a distance was never
  /// what bounded depth — see [UnitTuning.holdAtMidline]. A unit dropped
  /// beyond the middle already is exempt: its side painted its way there,
  /// and a card played on that ground has to be allowed to do something.
  bool get _atMidline {
    if (!game.registry.tuning.holdAtMidline) return false;
    if (_startedPastMid) return false;
    const mid = ArenaSpec.worldHeight / 2;
    return goalY < mid ? position.y <= mid : position.y >= mid;
  }

  /// Resolved on the first update, while the unit still stands where it was
  /// dropped. Latched, so a unit cannot re-qualify by drifting.
  ///
  /// **Strictly past, with a cell of slack.** Standing *on* the line is not
  /// being beyond it, and the difference is not academic: the frontier starts
  /// exactly on the halfway row, so a card played at the very front of its
  /// own half lands at y=12.0 — and an inclusive test read that as "already
  /// deep, exempt from the rule". It let one side walk to the far wall while
  /// the other held, which measured as an 87.7% board rather than a 50% one.
  bool get _startedPastMid {
    if (_pastMidResolved) return _startedPastMidValue;
    _pastMidResolved = true;
    const mid = ArenaSpec.worldHeight / 2;
    const slack = 0.5;
    return _startedPastMidValue = goalY < mid
        ? position.y < mid - slack
        : position.y > mid + slack;
  }

  bool _pastMidResolved = false;
  bool _startedPastMidValue = false;

  /// The row the push is measured from, resolved once on the first update
  /// while the unit is still standing where it was dropped.
  ///
  /// A unit that lands ahead of its own frontier — dropped into a pocket, or
  /// spawned by a card played at the very edge of the deploy zone — pushes
  /// from where it stands rather than from behind itself.
  double? get _startLine {
    if (_pushFromResolved) return _pushFrom;
    _pushFromResolved = true;
    final zone = game.arena.deployZone;
    if (!zone.hasOwners) return _pushFrom = null;
    final forward = goalY > position.y ? 1.0 : -1.0;
    final frontier = zone.frontierY(position.x, team, position.y, forward);
    // frontierY hands back the far edge when this side owns the whole column.
    if (frontier == goalY) return _pushFrom = null;
    _pushFrom = forward < 0
        ? math.min(frontier, position.y)
        : math.max(frontier, position.y);
    return _pushFrom;
  }

  double get _advanceRangeSquared {
    final r = game.registry.tuning.advanceRange;
    return r * r;
  }

  /// How close counts as standing on the frontier.
  ///
  /// Without a deadband a unit oscillates across the boundary: it steps onto
  /// unowned ground, paints it, and the next tick finds the frontier half a
  /// cell further on. One grid cell is 0.25 world units.
  static const double _atFrontier = 0.3;

  /// The far edge, used as the fallback bearing before the owner grid has
  /// been sampled and when a side owns a whole column outright.
  double get goalY =>
      team == game.arena.playerTeam ? 0.0 : ArenaSpec.worldHeight;

  /// True when [other] is close enough to hit.
  bool isInReachOf(Unit other) {
    final reach = stats.range + stats.radius + other.stats.radius;
    return position.distanceToSquared(other.position) <= reach * reach;
  }

  /// Roster bookkeeping.
  ///
  /// Joining happens in [SplatfrontGame.spawnUnit] rather than in onMount,
  /// because Flame only fires mount callbacks once the whole tree is attached
  /// to a live surface — a unit must be targetable the instant it is spawned.
  /// Leaving is handled on every exit path, and both sides are idempotent.
  @override
  void removeFromParent() {
    _leaveRoster();
    super.removeFromParent();
  }

  @override
  void onRemove() {
    _leaveRoster();
    super.onRemove();
  }

  /// Whoever spawned it, set by [SplatfrontGame.spawnUnit].
  SplatfrontGame? owner;

  /// The game this unit belongs to.
  ///
  /// [owner] first, and the component tree only as a fallback: a unit joins
  /// the roster the instant it is spawned but does not reach the tree until
  /// the top of the next frame, and it has to be targetable, damageable and
  /// killable in between. Asking Flame for the game in that window throws.
  @override
  SplatfrontGame get game => owner ?? super.game;

  void _leaveRoster() => owner?.units.remove(this);

  // --- Spell effects -----------------------------------------------------

  double _stunTimer = 0;
  double _buffTimer = 0;
  double _speedMultiplier = 1;
  double _paintMultiplier = 1;

  /// Frozen solid: no moving, no swinging, no painting.
  bool get isStunned => _stunTimer > 0;

  bool get isBuffed => _buffTimer > 0;

  /// World units per second, after any buff.
  double get effectiveSpeed => stats.speed * (isBuffed ? _speedMultiplier : 1);

  /// Seconds between stamps, after any buff. A faster paint rate means a
  /// shorter gap, not a bigger blob.
  double get effectiveStampTick =>
      Timings.stampTick / (isBuffed ? _paintMultiplier : 1);

  void stun(double seconds) {
    if (_dying) return;
    // A second Freeze extends rather than restarts, so overlapping spells
    // cannot shorten a stun.
    _stunTimer = math.max(_stunTimer, seconds);
  }

  void applyBuff({
    required double seconds,
    double speed = 1,
    double paintRate = 1,
  }) {
    if (_dying) return;
    _buffTimer = math.max(_buffTimer, seconds);
    _speedMultiplier = math.max(_speedMultiplier, speed);
    _paintMultiplier = math.max(_paintMultiplier, paintRate);
  }

  void _tickEffects(double dt) {
    if (_stunTimer > 0) _stunTimer = math.max(0, _stunTimer - dt);
    if (_buffTimer > 0) {
      _buffTimer = math.max(0, _buffTimer - dt);
      if (_buffTimer == 0) {
        _speedMultiplier = 1;
        _paintMultiplier = 1;
      }
    }
  }

  @override
  void update(double dt) {
    // Outside the dying guard: a unit that takes its last hit should still
    // flash white on the frame it dies.
    if (_flash > 0) _flash = math.max(0, _flash - dt / _flashTime);
    _breath = (_breath + dt * 2.2) % (math.pi * 2);

    if (_dying) {
      _deathTimer += dt;
      if (_deathTimer >= Timings.deathFadeOut) game.despawn(this);
      return;
    }

    _tickEffects(dt);
    if (_attackAnim > 0) {
      _attackAnim = math.max(0, _attackAnim - dt / _swingTime);
    }

    if (isStunned) {
      _walking = false;
      return; // Frozen: nothing else happens this frame.
    }

    // Resolved on the first update, while it is still standing where it was
    // dropped. Left to resolve lazily it would re-base on wherever a unit
    // happened to finish a fight, and a unit that kept finding targets would
    // push six more units of ground after every kill, all the way up.
    _startLine;

    _retargetOnTick(dt);
    _moveAndFight(dt);
    _paintTrail(dt);
  }

  void _retargetOnTick(double dt) {
    _aiTimer += dt;
    if (_aiTimer < Timings.aiTick) return;
    _aiTimer -= Timings.aiTick;
    _target = UnitAi.findTarget(this, game.units);
    if (_target == null) _refreshFrontier();
  }

  /// Where to walk when there is nothing to fight.
  ///
  /// Refreshed on the AI tick rather than per frame: it costs a column scan
  /// of the owner grid, and the grid itself only changes twice a second.
  double _frontierY = 0;

  void _refreshFrontier() {
    final zone = game.arena.deployZone;
    // Until the first readback lands the grid is all-neutral, which would tell
    // every unit it is already standing on the frontier and freeze the board.
    _frontierY = zone.hasOwners
        ? zone.frontierY(
            position.x,
            team,
            position.y,
            goalY > position.y ? 1 : -1,
          )
        : goalY;
  }

  void _moveAndFight(double dt) {
    final target = _target;

    if (target != null && target.isAlive) {
      if (isInReachOf(target)) {
        _walking = false;
        _faceToward(
          target.position.x - position.x,
          target.position.y - position.y,
          dt,
        );
        _attack(target, dt);
        return; // Standing still to swing.
      }
      // Chasing is deliberately **not** leashed.
      //
      // It was, briefly, on the theory that a unit following a runner was
      // how bodies ended up at the far wall. Two things killed it. It did not
      // measure — with the leash on the chase, units still reached the same
      // depth, because depth was never coming from chasing. And it made a
      // unit at the end of its leash stand and watch an enemy walk up to it,
      // which is a worse game than the one being fixed. The leash stops a
      // unit *marching*; the midline stops it *advancing*; neither should
      // stop it fighting.
      _desired
        ..setFrom(target.position)
        ..sub(position);
    } else if (_hasAdvanced) {
      // At the end of its leash with nothing to fight: hold the post. Still
      // painting where it stands, still swinging at anything that walks into
      // aggro range — just not marching off the board.
      _walking = false;
      return;
    } else {
      // Nothing to fight: walk up the lane toward where its own paint runs
      // out. There is no base at the far edge and nothing to break when it
      // arrives — the ground itself is the objective, so a unit that marched
      // to the end left the only thing worth holding behind it.
      //
      // The frontier alone will not stop it, which is the trap here: a
      // painting unit lays its own colour about a radius ahead of itself, so
      // it manufactures the very frontier it is walking to and never arrives.
      // [_hasAdvanced] is what actually bounds it.
      // Standing on the frontier is not arriving. The ground ahead is the
      // objective, so once the unit has caught up with its own paint edge it
      // keeps marching in the direction that edge pointed — [_hasAdvanced] is
      // what stops it, not the frontier.
      //
      // Setting the step to zero here instead is what made a push look like a
      // single-file stripe: the unit parked on the boundary and crept forward
      // only as fast as its own stamp widened the edge, so its advance ran at
      // the paint rate rather than its walking speed and it never entered
      // enemy ground as a body.
      final dy = _frontierY - position.y;
      final forward = goalY > position.y ? 1.0 : -1.0;
      _desired.setValues(
        lane - position.x,
        dy.abs() < _atFrontier ? forward : dy,
      );
    }

    if (_desired.length2 > 0) _desired.normalize();

    // Faced before steering is folded in, so a unit sidestepping a blocker
    // still looks where it is going rather than where it is dodging.
    _faceToward(_desired.x, _desired.y, dt);

    _steer.setZero();
    UnitAi.separateFromAllies(this, game.units, _steer);
    // Air units skip blocker avoidance entirely: they fly over.
    if (!stats.flying) {
      UnitAi.avoidBlockers(this, game.arena.layout.blockers, _steer);
    }
    _desired.add(_steer);

    if (_desired.length2 > 0) {
      _desired.normalize();
      final step = effectiveSpeed * dt;
      position.addScaled(_desired, step);
      _clampToArena();
      _walking = true;
      // Driven by ground covered rather than by the clock, so the legs match
      // the pace without any unit being told its own cadence.
      _walkPhase = (_walkPhase + step * 5.0) % (math.pi * 2);
    } else {
      _walking = false;
    }

    // The attack timer keeps running down while closing, so a unit that
    // arrives in range swings promptly instead of pausing a full interval.
    _attackTimer = math.max(0, _attackTimer - dt);
  }

  void _attack(Unit target, double dt) {
    _attackTimer -= dt;
    if (_attackTimer > 0) return;
    _attackTimer = stats.attackInterval;
    _attackAnim = 1;
    onAttack(target);
    dealDamage(target);
  }

  /// Applies this unit's hit to [target].
  ///
  /// Overridable so a splash unit can widen one swing into many. Everything
  /// still lands through [takeDamage], so auras apply either way.
  void dealDamage(Unit target) => target.takeDamage(stats.damage);

  void takeDamage(double amount) {
    if (_dying) return;
    hp -= amount * (1 - auraReduction());
    _flash = 1;
    Audio.play(Sfx.hit);
    if (hp <= 0) _die();
  }

  /// Warden's aura: friendly units within its radius take less damage.
  ///
  /// Read on the receiving end rather than pushed out by the Warden, so it
  /// covers every source of damage — melee, ranged and spells alike — without
  /// any of them needing to know Wardens exist.
  double auraReduction() {
    var best = 0.0;
    for (final other in game.units) {
      if (other.team != team || !other.isAlive) continue;
      if (!other.stats.hasAura) continue;
      final radius = other.stats.auraRadius;
      if (position.distanceToSquared(other.position) > radius * radius) {
        continue;
      }
      // Auras do not stack: the strongest one wins.
      best = math.max(best, other.stats.auraDamageReduction);
    }
    return best.clamp(0.0, 0.9);
  }

  /// Paints the ground it has walked over.
  ///
  /// Stamps fire on a fixed 10 Hz tick rather than every frame, and the gap
  /// since the last stamp is filled in, so a fast unit leaves a continuous
  /// trail instead of a dotted line.
  void _paintTrail(double dt) {
    if (!stats.paints) return;

    _stampTimer += dt;
    final tick = effectiveStampTick;
    if (_stampTimer < tick) return;
    _stampTimer -= tick;

    final layer = game.arena.paintLayer;
    final travelled = _lastStampPos.distanceTo(position);
    final step = stats.paint * 0.6;

    if (travelled > step) {
      final steps = math.min((travelled / step).ceil(), _maxTrailSteps);
      for (var i = 1; i <= steps; i++) {
        layer.stamp(
          _lastStampPos + (position - _lastStampPos) * (i / steps),
          stats.paint,
          team,
        );
      }
    } else {
      layer.stamp(position, stats.paint, team);
    }

    _lastStampPos.setFrom(position);
  }

  void _die() {
    if (_dying) return;
    _dying = true;
    _deathTimer = 0;
    _target = null;

    // A death leaves a splash in the unit's colour, so trades still move the
    // score. Its size is balance data, not a magic number.
    final tuning = game.registry.tuning;
    final splash = math.max(
      stats.paint * tuning.deathSplashMultiplier,
      tuning.deathSplashMin,
    );
    game.arena.paintLayer.stamp(position, splash, team);

    // Droplets sized off the splash, so a Bucket Bot goes down harder than a
    // Swarmlet does. Only a real tank is worth shaking the screen for.
    game.burst(position, team, count: (4 + splash * 3).round(), spread: splash);
    if (stats.hp >= 600) {
      game.shake(amplitude: 0.10 + stats.radius * 0.12, seconds: 0.20);
    }
    Audio.play(Sfx.death);

    onDeath();
  }

  /// Ends this unit with no damage event.
  ///
  /// For anything whose end is a rule rather than a fight — a building's
  /// lifetime running out. It still leaves its splash and its droplets,
  /// because the ground it held should change hands, but it does not flash
  /// or play a hit.
  @protected
  void expire() {
    if (_dying) return;
    hp = 0;
    _die();
  }

  /// Hook for subclasses: fire the Rive attack state, spawn a projectile.
  void onAttack(Unit target) {}

  /// Hook for subclasses: fire the Rive die state, drop an aura.
  void onDeath() {}

  void _clampToArena() {
    position.x = position.x.clamp(
      stats.radius,
      ArenaSpec.worldWidth - stats.radius,
    );
    position.y = position.y.clamp(
      stats.radius,
      ArenaSpec.worldHeight - stats.radius,
    );
  }

  // --- Rendering ---------------------------------------------------------
  // The character itself is drawn by [UnitArt]; what happens here is the
  // framing around it — the scale into art space, the lunge, the death
  // squash, the frost while stunned, and the health bar.

  static final Paint _hpBack = Paint()..color = const Color(0xCC1C1A17);
  static final Paint _hpFill = Paint();
  static final Paint _frost = Paint()
    ..color = const Color(0x66CFF3FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.12;

  @override
  void render(Canvas canvas) {
    final centre = Offset(stats.radius, stats.radius);
    final dyingFraction = _dying
        ? (_deathTimer / Timings.deathFadeOut).clamp(0.0, 1.0)
        : 0.0;

    _pose
      ..team = team
      ..alpha = 1 - dyingFraction
      ..walk = _walkPhase
      ..breath = _breath
      ..attack = _attackAnim
      ..facingX = _faceX
      ..facingY = _faceY
      ..moving = _walking;

    canvas.save();
    // Into art space: origin at the unit's centre, 1.0 == its radius. Drawn
    // a little over life size, because a body exactly the width of its own
    // collision circle reads as a dot at phone scale.
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(stats.radius * _artScale);

    if (_dying) {
      // Collapses onto its own feet rather than shrinking toward its middle.
      canvas.translate(0, 1);
      canvas.scale(1 + dyingFraction * 0.4, 1 - dyingFraction * 0.65);
      canvas.translate(0, -1);
    } else if (_attackAnim > 0) {
      final lunge = math.sin(_attackAnim * math.pi) * 0.22;
      canvas.translate(_faceX * lunge, _faceY * lunge);
    }

    // Two passes: a fat cream rim, then the character over it. Without the
    // rim a unit standing on its own fresh paint is the same colour as the
    // ground it is standing on.
    _pose.outlinePass = true;
    _art.draw(canvas, _pose);
    _pose.outlinePass = false;
    _art.draw(canvas, _pose);

    if (_flash > 0) {
      _pose
        ..flashPass = true
        ..flash = _flash;
      _art.draw(canvas, _pose);
      _pose
        ..flashPass = false
        ..flash = 0;
    }
    canvas.restore();

    if (isStunned && !_dying) {
      canvas.drawCircle(centre, stats.radius * 1.35, _frost);
    }
    if (!_dying && hp < stats.hp) _renderHealthBar(canvas);
  }

  void _renderHealthBar(Canvas canvas) {
    const height = 0.1;
    // Clear of the head: the art reaches about 1.6 radii above the centre,
    // and the centre sits one radius down the component box.
    final top = -stats.radius * 0.6 - 0.24;
    final width = stats.radius * 2;

    canvas.drawRRect(
      RRect.fromRectXY(Rect.fromLTWH(0, top, width, height), 0.05, 0.05),
      _hpBack,
    );
    _hpFill.color = Palette.of(team);
    canvas.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(0, top, width * healthFraction, height),
        0.05,
        0.05,
      ),
      _hpFill,
    );
  }
}
