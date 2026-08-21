import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../arena/deploy_zone.dart';
import '../cards/card_model.dart';
import '../cards/hand_controller.dart';
import '../match/match_side.dart';
import '../splatfront_game.dart';
import '../units/unit.dart';
import 'bot_difficulty.dart';

/// A decision the brain has committed to but has not carried out yet.
class _PendingPlay {
  _PendingPlay(this.slot, this.position, this.delay);

  final int slot;
  final Vector2 position;
  double delay;
}

/// The opponent.
///
/// One brain, three tiers: everything that separates Easy from Hard lives in
/// [BotDifficulty], not in branches here. It thinks on a fixed tick, then
/// waits out its reaction delay before actually playing, so a slow bot reads
/// as slow rather than as stupid.
class BotBrain extends Component with HasGameReference<SplatfrontGame> {
  BotBrain({
    required this.side,
    required this.difficulty,
    math.Random? random,
  }) : _random = random ?? math.Random();

  final MatchSide side;
  final BotDifficulty difficulty;
  final math.Random _random;

  /// Set false during the countdown and after the final whistle.
  bool active = true;

  double _tick = 0;
  _PendingPlay? _pending;

  /// Whether the hand was locked the last time the brain thought, so it can
  /// tell a fresh turn from another tick inside the one it is already in.
  /// Starts true so the opening turn gets rolled for like any other.
  bool _handWasLocked = true;

  /// Seconds left of a turn the waste roll has thrown away.
  double _wasteTimer = 0;

  /// Coverage gap that counts as "behind", from section 8 rule 3.
  static const double _behindBy = 0.15;

  /// A push is this many enemy units past the mid line.
  static const int _pushSize = 2;

  /// Rule 1 drops its answer this far behind its own front line.
  static const double _counterSetback = 2.0;

  /// Section 8 rule 2: the elixir at which the bot spends unprompted. Only
  /// applies when there is no hand lockout to make banking pointless.
  static const double _surplus = 8.0;

  Team get team => side.team;

  /// The bot defends the edge the player is walking toward.
  double get _baseY => team == game.arena.playerTeam
      ? ArenaSpec.worldHeight
      : 0.0;

  /// Positive y is "forward" for the side defending y = 0.
  double get _forward => _baseY == 0 ? 1.0 : -1.0;

  @override
  void update(double dt) {
    if (!active || !side.hasHand) return;

    // A committed play waits out the reaction delay before it lands.
    final pending = _pending;
    if (pending != null) {
      pending.delay -= dt;
      if (pending.delay <= 0) {
        _pending = null;
        // Re-check on the way out: the target may be dead and the elixir may
        // be gone since the decision was taken.
        final played = game.playFromHand(side, pending.slot, pending.position);
        // A refused play used to cost a whole decision cycle on top of the
        // reaction delay it had already waited out. The usual reason is that
        // the ground it aimed at was repainted while it waited, which is
        // common when the player is pushing — exactly when the bot going
        // quiet is most obvious. Decide again on the next frame instead.
        if (!played) _tick = Timings.botTick;
      }
      return;
    }

    _tick += dt;
    if (_tick < Timings.botTick) return;
    _tick = 0;
    _decide();
  }

  void _decide() {
    // Wasting elixir is the main thing that makes an easy bot easy.
    if (_wastesThisTurn()) return;

    final play = _counterPush() ?? _spendSurplus() ?? _catchUpOnPaint();
    if (play == null) return;

    // Jitter of 0..reactionDelay on every decision, so it never feels
    // metronomic.
    play.delay =
        difficulty.reactionDelay + _random.nextDouble() * difficulty.reactionDelay;
    _pending = play;
  }

  /// The elixir-waste roll: does the bot throw this turn away?
  ///
  /// Rolled once per turn, not once per think. [BotDifficulty.elixirWasteRate]
  /// is documented as the chance of skipping a decision it could have acted
  /// on, and that reading only held while the bot could play whenever it had
  /// the elixir. With the hand lockout it thinks ten times per turn, so a
  /// skipped think cost it nothing at all — it simply thought again half a
  /// second later and still played inside the same window.
  ///
  /// Measured over ninety seconds that left Easy playing eleven cards against
  /// Hard's fifteen, a 27% gap from rates that differ seventeen-fold. Rolled
  /// per turn the number means what it says, and an easy bot idles.
  bool _wastesThisTurn() {
    final refill = side.hand!.refillSeconds;

    // No lockout means no turns, so every think really is its own chance.
    if (refill <= 0) return _random.nextDouble() < difficulty.elixirWasteRate;

    if (_wasteTimer > 0) {
      _wasteTimer -= Timings.botTick;
      return true;
    }

    final locked = side.hand!.hasCooldowns;
    // A turn has just opened.
    if (!locked && _handWasLocked) {
      _handWasLocked = false;
      if (_random.nextDouble() < difficulty.elixirWasteRate) {
        // Sit the turn out rather than skipping a think, then play again.
        // Without the timer the hand would never lock, no new turn would ever
        // open, and the bot would be silent for the rest of the match.
        _wasteTimer = refill;
        return true;
      }
      return false;
    }

    _handWasLocked = locked;
    return false;
  }

  /// Rule 1: answer a push with the cheapest card that can actually hit it.
  _PendingPlay? _counterPush() {
    if (!difficulty.countersThreats) return null;

    final threats = _threatsPastMidLine();
    if (threats.length < _pushSize) return null;

    // Biggest threat is the one with the most health left: the tank at the
    // front of the push is what has to be answered.
    threats.sort((a, b) => b.hp.compareTo(a.hp));
    final biggest = threats.first;

    final slot = _cheapestAffordableThatHits(flying: biggest.stats.flying);
    if (slot == null) return null;

    // A spell goes on the push itself; a troop goes behind its own line
    // rather than on top of it.
    final position = _cardAt(slot).isSpell
        ? biggest.position.clone()
        : _legalSpotNear(
            biggest.position.x,
            biggest.position.y - _forward * _counterSetback,
          );
    if (position == null) return null;

    return _PendingPlay(slot, position, 0);
  }

  /// Rule 2: sitting on a surplus, spend the most expensive thing available
  /// in whichever lane it has painted least.
  ///
  /// Section 8 sets the surplus at 8, which assumed a bot that could play
  /// whenever it had the elixir. With the hand lockout it gets one play every
  /// [HandController.refillSeconds], so banking elixir past what it can spend
  /// costs it whole windows — it sat at seven and a half doing nothing while
  /// its turn ticked away, which is what "the blue side never comes" looked
  /// like. With a lockout in force it spends whatever it can afford instead.
  _PendingPlay? _spendSurplus() {
    final locked = side.hand!.refillSeconds > 0;
    if (!locked && side.elixir.amount < _surplus) return null;

    final slot = _mostExpensiveAffordable();
    if (slot == null) return null;

    final position = _spotForCard(slot, _chooseLane());
    if (position == null) return null;

    return _PendingPlay(slot, position, 0);
  }

  /// Rule 3: behind on coverage, push paint rather than bodies.
  _PendingPlay? _catchUpOnPaint() {
    if (side.elixir.amount < 5) return null;
    if (game.arena.coverage.value.leadFor(team) > -_behindBy) return null;

    final slot = _highestPaintAffordable();
    if (slot == null) return null;

    final position = _spotForCard(slot, _chooseLane());
    if (position == null) return null;

    return _PendingPlay(slot, position, 0);
  }

  // --- Reading the board ---------------------------------------------------

  /// Enemy units that have crossed into this side's own half.
  ///
  /// "Past the mid line" is measured from the defender's point of view: the
  /// bot's half lies *behind* it, on the far side of the mid line from the
  /// direction it attacks in.
  List<Unit> _threatsPastMidLine() {
    const mid = ArenaSpec.worldHeight / 2;
    final threats = <Unit>[];
    for (final unit in game.units) {
      if (unit.team == team || !unit.isAlive) continue;
      final inOurHalf =
          _forward > 0 ? unit.position.y < mid : unit.position.y > mid;
      if (inOurHalf) threats.add(unit);
    }
    return threats;
  }

  /// Which third of the arena to play into.
  ///
  /// Reinforcing the lane you already own is the classic bad habit, and
  /// picking the one you are losing is most of what good play *is* in a game
  /// scored on ground. Every tier used to pick the weakest lane every time —
  /// the strongest available play — which is why, measured over five
  /// ninety-second duels, an Easy bot beat a Hard one as often as it lost to
  /// it. Card tempo was never the thing deciding these matches; placement is.
  int _chooseLane() {
    const lanes = 3;
    if (_precise(difficulty.lanePrecision)) return _weakestLane();
    return _random.nextInt(lanes);
  }

  /// Does the bot get this judgement call right?
  ///
  /// A precision of 1 short-circuits rather than rolling. `nextDouble` returns
  /// values in [0, 1), so a roll would do for a real generator, but a test
  /// double pinned at 1.0 would send a Hard bot down the careless branch every
  /// time — and "1.0 means always" should not depend on which generator is in
  /// the seat.
  bool _precise(double precision) =>
      precision >= 1.0 || _random.nextDouble() < precision;

  /// The third of the arena where this side holds the least ground.
  int _weakestLane() {
    const lanes = 3;
    final counts = List<int>.filled(lanes, 0);
    final zone = game.arena.deployZone;
    final perLane = ArenaSpec.gridCols ~/ lanes;

    for (var row = 0; row < ArenaSpec.gridRows; row++) {
      for (var col = 0; col < ArenaSpec.gridCols; col++) {
        if (zone.ownerOf(col, row) != team) continue;
        counts[math.min(col ~/ perLane, lanes - 1)]++;
      }
    }

    var weakest = 0;
    for (var i = 1; i < lanes; i++) {
      if (counts[i] < counts[weakest]) weakest = i;
    }
    return weakest;
  }

  // --- Choosing a card -----------------------------------------------------

  CardModel _cardAt(int slot) {
    final hand = side.hand!;
    final id = hand.cardIdAt(slot);
    return game.cards.at(id, hand.levelOf(id));
  }

  /// Whether the bot may play the card in [slot] right now.
  ///
  /// The slot matters as well as the card: a slot that has just been spent is
  /// on cooldown, and picking it would burn a whole decision on a play that
  /// [SplatfrontGame.playFromHand] is going to refuse.
  bool _playable(int slot, CardModel card) {
    if (!side.hand!.isReady(slot)) return false;
    if (card.isSpell && !difficulty.playsSpells) return false;
    return side.elixir.canAfford(card.cost);
  }

  int? _cheapestAffordableThatHits({required bool flying}) {
    int? best;
    var bestCost = 1 << 30;
    for (var slot = 0; slot < side.hand!.handSize; slot++) {
      final card = _cardAt(slot);
      if (!_playable(slot, card)) continue;
      // A spell answers anything; a troop has to be able to reach it.
      // isUnit, not isTroop: a building has a targeting mask too, and
      // treating one as a spell let the bot answer a flyer with a wall.
      if (card.isUnit && !card.unit!.targets.canHit(flying: flying)) continue;
      if (card.cost < bestCost) {
        bestCost = card.cost;
        best = slot;
      }
    }
    return best;
  }

  int? _mostExpensiveAffordable() {
    // A weak bot does not reliably pick the best thing in its hand. Spending
    // two elixir on a Dab where five would have bought a Bucket Bot is the
    // difference between a body and a push, and unlike tempo it is not capped
    // by the hand lockout — every side gets one play per turn whatever it
    // picks, so *which* card is most of what a turn is worth.
    if (!_precise(difficulty.cardPrecision)) return _anyPlayable();

    int? best;
    var bestCost = -1;
    for (var slot = 0; slot < side.hand!.handSize; slot++) {
      final card = _cardAt(slot);
      if (!_playable(slot, card)) continue;
      if (card.cost > bestCost) {
        bestCost = card.cost;
        best = slot;
      }
    }
    return best;
  }

  /// Any card it can legally play, chosen without judgement.
  int? _anyPlayable() {
    final options = <int>[];
    for (var slot = 0; slot < side.hand!.handSize; slot++) {
      if (_playable(slot, _cardAt(slot))) options.add(slot);
    }
    if (options.isEmpty) return null;
    return options[_random.nextInt(options.length)];
  }

  int? _highestPaintAffordable() {
    int? best;
    var bestPaint = -1.0;
    for (var slot = 0; slot < side.hand!.handSize; slot++) {
      final card = _cardAt(slot);
      if (!_playable(slot, card) || !card.isUnit) continue;
      if (card.unit!.paint > bestPaint) {
        bestPaint = card.unit!.paint;
        best = slot;
      }
    }
    return best;
  }

  // --- Finding somewhere legal to stand ------------------------------------

  /// The bot obeys the deploy rule exactly as the player does, so it walks
  /// back toward its own base until it finds ground it actually owns.
  ///
  /// Falls back to the nearest owned cell anywhere if that column is gone.
  /// Walking straight back was the whole search, and a Roller paints a stripe
  /// up an entire lane — which left the bot with no legal cell in the column
  /// it had chosen, so it abandoned the play and stood there doing nothing.
  /// Losing a lane should cost the bot its preferred spot, not its turn.
  Vector2? _legalSpotNear(double x, double preferredY) {
    const step = 0.5;
    final clampedX = x.clamp(1.0, ArenaSpec.worldWidth - 1.0);

    for (var offset = 0.0; offset <= ArenaSpec.worldHeight; offset += step) {
      final y = preferredY - _forward * offset;
      if (y < 0 || y > ArenaSpec.worldHeight) break;
      final candidate = Vector2(clampedX, y);
      if (game.arena.deployZone.canDeploy(candidate, team)) return candidate;
    }
    return _nearestOwnedCell(Vector2(clampedX, preferredY));
  }

  /// The owned cell closest to [target], or null if the bot owns nothing.
  ///
  /// A full grid walk, but only on the frames where the preferred column has
  /// failed, and the bot decides at most twice a second.
  Vector2? _nearestOwnedCell(Vector2 target) {
    Vector2? best;
    var bestDistance = double.infinity;

    game.arena.deployZone.forEachValidCell(team, (col, row) {
      final centre = DeployZone.cellCentre(col, row);
      final distance = centre.distanceToSquared(target);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = centre;
      }
    });
    return best;
  }

  /// Troops need owned ground; spells do not.
  Vector2? _spotForCard(int slot, int lane) => _cardAt(slot).isSpell
      ? _spellSpotInLane(lane)
      : _legalSpotInLane(lane);

  Vector2? _legalSpotInLane(int lane) {
    // Start at the front of its own half and walk back to its base.
    return _legalSpotNear(_laneCentre(lane), ArenaSpec.worldHeight / 2);
  }

  double _laneCentre(int lane) {
    const lanes = 3;
    return ArenaSpec.worldWidth / lanes * (lane + 0.5);
  }

  /// Where to throw a spell in [lane].
  ///
  /// Spells ignore the deploy rule, so unlike a troop they are not walked
  /// back to owned ground: the whole value of a paint spell is landing it
  /// where the bot does *not* already hold the floor.
  Vector2 _spellSpotInLane(int lane) => Vector2(
    _laneCentre(lane),
    // Just past the mid line, into the ground it wants to take.
    ArenaSpec.worldHeight / 2 + _forward * 2.0,
  );
}
