import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/audio.dart';
import '../core/constants.dart';
import '../core/palette.dart';
import 'arena/arena_component.dart';
import 'arena/arena_layout.dart';
import 'arena/deploy_overlay.dart';
import 'cards/card_model.dart';
import 'cards/card_registry.dart';
import 'bot/bot_brain.dart';
import 'bot/bot_difficulty.dart';
import 'cards/elixir_bar.dart';
import 'cards/hand_controller.dart';
import 'match/match_controller.dart';
import 'match/match_result.dart';
import 'fx/particles.dart';
import 'fx/screen_shake.dart';
import 'fx/splatter.dart';
import 'match/match_side.dart';
import 'spells/spell.dart';
import 'units/projectile.dart';
import 'units/building.dart';
import 'units/unit.dart';
import 'units/units_registry.dart';

/// Which debug sandbox, if any, is layered over the match.
enum SandboxMode {
  /// A real match.
  off,

  /// Phase 1: tap or drag to stamp paint, ignoring every game rule.
  paint,

  /// Phase 2: tap to spawn the selected unit and watch it fight.
  units,
}

/// Root of the running match.
///
/// The camera is fixed: the whole 16x24 arena is always visible, no scrolling
/// and no zoom, so world coordinates and arena coordinates are the same thing.
class SplatfrontGame extends FlameGame {
  SplatfrontGame({
    required this.layout,
    required this.cards,
    this.deck,
    this.botDeck,
    this.botDifficulty,
    this.botRandom,
    this.trophyRules,
    this.botTier = BotTier.normal,
    this.startingTrophies = 0,
    this.levels = const CardLevels(),
    this.botLevels = const CardLevels(),
    this.economy = MatchRules.flat,
    this.playerTeam = Team.blue,
    this.sandbox = SandboxMode.off,
  }) : super(
         camera: CameraComponent.withFixedResolution(
           width: ArenaSpec.worldWidth,
           height: ArenaSpec.worldHeight,
         ),
       );

  final ArenaLayout layout;
  final CardRegistry cards;

  /// The player's eight. Null in the debug sandboxes, which have no hand.
  final Deck? deck;

  /// The opponent's eight, and how well it plays them. Both null means no
  /// opponent at all, which is what the sandboxes want.
  final Deck? botDeck;
  final BotDifficulty? botDifficulty;

  /// Seedable so a test can compare two tiers on the same roll sequence.
  final math.Random? botRandom;

  /// Trophy maths for the end screen. Null runs the arena with no clock at
  /// all, which is what the debug sandboxes want.
  final TrophyRules? trophyRules;
  final BotTier botTier;

  /// Trophies the player brought in, which the result is scored against.
  final int startingTrophies;

  final CardLevels levels;

  /// The opponent's card levels. Level 1 everywhere on the ladder; the
  /// campaign raises it as the levels climb, which is what keeps the back
  /// half getting harder after the brain has run out of room to improve.
  final CardLevels botLevels;

  /// Match economy. Defaults to flat so the sandboxes and any test that is
  /// not about income behave exactly as they always did.
  final MatchRules economy;

  final Team playerTeam;
  final SandboxMode sandbox;

  /// Troop stats and components, which the card registry owns.
  UnitsRegistry get registry => cards.units;

  /// Every living unit on the field. Joined in [spawnUnit] and left in
  /// [Unit.removeFromParent], so membership never waits on Flame mount
  /// callbacks. Targeting and separation walk this list every tick, so it is a
  /// plain list rather than a per-frame children.query allocation.
  final List<Unit> units = <Unit>[];

  /// Built with the game, not in [onLoad], so the HUD can bind to
  /// [ArenaComponent.coverage] the moment the widget tree is laid out — the
  /// GameWidget mounts before the game finishes loading.
  late final ArenaComponent arena = ArenaComponent(
    layout: layout,
    playerTeam: playerTeam,
  );

  /// Which side the sandbox acts for: the brush colour, and the team a
  /// spawned unit joins.
  final ValueNotifier<Team> sandboxTeam = ValueNotifier(Team.red);
  final ValueNotifier<double> brushRadius = ValueNotifier(1.2);
  final ValueNotifier<String> sandboxUnit = ValueNotifier('brusher');

  /// Live unit count, for the debug readout.
  final ValueNotifier<int> unitCount = ValueNotifier(0);

  /// What the player did this match, for the daily quests.
  int cardsPlayed = 0;
  int spellsPlayed = 0;

  final math.Random _random = math.Random();

  @override
  Color backgroundColor() => Palette.hudBackground;

  @override
  Future<void> onLoad() async {
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..position = Vector2.zero();

    await world.add(arena);
    await world.add(deployOverlay);

    await add(screenShake);

    // The player's economy is worth a chime; the bot's is not.
    player.elixir.onFull = () => Audio.play(Sfx.elixirFull);

    final match = _match;
    if (match != null) await add(match);

    final difficulty = botDifficulty;
    if (opponent.hasHand && difficulty != null) {
      _bot = BotBrain(
        side: opponent,
        difficulty: difficulty,
        random: botRandom,
      );
      await add(_bot!);
    }

    switch (sandbox) {
      case SandboxMode.paint:
        await world.add(_PaintHarness(game: this));
      case SandboxMode.units:
        await world.add(_UnitSandbox(game: this));
      case SandboxMode.off:
        break;
    }
  }

  // --- Cards, elixir and deploying --------------------------------------

  /// The two sides. Both are the same shape, so the deploy rule, the elixir
  /// cost and the rotation run through one path for the player and the bot
  /// alike — the bot gets no discount and no special case.
  ///
  /// Built with the game, like [arena], so the HUD can bind before loading
  /// finishes.
  late final MatchSide player = MatchSide(
    team: playerTeam,
    deck: _validated(deck),
    levels: levels,
    cardRefillSeconds: economy.cardRefillSeconds,
  );

  late final MatchSide opponent = MatchSide(
    team: playerTeam.opponent,
    deck: _validated(botDeck),
    levels: botLevels,
    // The bot lives under the same brake as the player.
    cardRefillSeconds: economy.cardRefillSeconds,
  );

  /// A deck naming a card with no component behind it should fail here, not
  /// silently do nothing when it comes up in hand.
  Deck? _validated(Deck? deck) {
    deck?.validateAgainst(cards);
    return deck;
  }

  /// The player's rotation and pool, which is all the HUD cares about.
  HandController? get hand => player.hand;
  ElixirBar get elixir => player.elixir;

  BotBrain? _bot;
  BotBrain? get bot => _bot;

  /// Built here rather than in [onLoad], and only added to the tree there.
  ///
  /// The HUD reads [match] the first time it builds, which happens before an
  /// async `onLoad` has run: creating it there left the timer reading `--:--`
  /// for the whole match and the result screen never appearing at all.
  late final MatchController? _match = switch (trophyRules) {
    final rules? => MatchController(
      trophyRules: rules,
      botTier: botTier,
    )..playerTrophies = startingTrophies,
    null => null,
  };

  /// The clock. Null in the sandboxes, which never end.
  MatchController? get match => _match;

  /// True when cards may actually be played: not during the countdown, and
  /// not after the final whistle. A sandbox has no clock, so it is always on.
  bool get acceptsInput => _match?.isLive ?? true;

  late final DeployOverlay deployOverlay = DeployOverlay(
    deployZone: arena.deployZone,
  );

  /// Set while the player is dragging a card over the arena, so the HUD can
  /// dim the card it came from.
  final ValueNotifier<int?> draggingSlot = ValueNotifier(null);

  /// Starts a drag from hand [slot]. Returns false if the match is not
  /// accepting input, or the card is unaffordable.
  bool beginDeploy(int slot) {
    if (!acceptsInput) return false;
    final controller = hand;
    if (controller == null) return false;
    final card = cards.at(
      controller.cardIdAt(slot),
      controller.levelOf(controller.cardIdAt(slot)),
    );
    if (!elixir.canAfford(card.cost)) return false;
    // A slot that has just been spent is still cooling down.
    if (!controller.isReady(slot)) return false;
    draggingSlot.value = slot;
    return true;
  }

  /// Moves the drop ghost. [worldPosition] is in arena units.
  void updateDeploy(Vector2 worldPosition) {
    final slot = draggingSlot.value;
    if (slot == null) return;
    final card = _cardInSlot(slot);
    if (card == null) return;

    deployOverlay.preview = DeployPreview(
      worldPosition: worldPosition,
      radius: card.previewRadius,
      team: playerTeam,
      valid: canDeployHere(card, worldPosition),
      // Spells land anywhere, so there is no zone to light up for them — and
      // neither is there when everything can be dropped anywhere, where the
      // glow would just be the whole board.
      showValidCells: card.obeysDeployZone && !economy.deployAnywhere,
    );
  }

  /// The deploy rule for the player.
  bool canDeployHere(CardModel card, Vector2 worldPosition) =>
      canDeployFor(playerTeam, card, worldPosition);

  /// The deploy rule. The bot goes through this too, so neither side can
  /// bend it.
  ///
  /// With [MatchRules.deployAnywhere] on, anywhere inside the arena will do
  /// and the drop claims the ground it lands on. With it off, the original
  /// section 3 rule applies: a body may only land on [team]'s own colour, so
  /// painting forward is what extends your reach.
  bool canDeployFor(Team team, CardModel card, Vector2 worldPosition) {
    if (worldPosition.x < 0 ||
        worldPosition.y < 0 ||
        worldPosition.x > ArenaSpec.worldWidth ||
        worldPosition.y > ArenaSpec.worldHeight) {
      return false;
    }
    if (card.isBuilding && buildingsStandingFor(team) >= buildingCap) {
      return false;
    }
    if (!card.obeysDeployZone) return true;
    if (economy.deployAnywhere) return true;

    // The other half of the midline rule.
    //
    // Holding units at the middle achieves nothing on its own, and this is
    // the measurement that proved it: the deploy line follows the paint, so
    // the moment a side painted past the middle it could drop the next card
    // there, and that card advanced from *there*. Paint forward, deploy
    // forward, walk forward — the loop marched to the far wall whatever the
    // leash said, which is why units still reached y=0.4 out of 24 with the
    // hold switched on.
    //
    // With bodies barred from the far half, ground beyond the middle is
    // taken by the things that can reach across it: spells, and the ranged
    // cards and buildings that shell or burn past their own feet.
    if (registry.tuning.holdAtMidline && !_inOwnHalf(team, worldPosition.y)) {
      return false;
    }
    return arena.deployZone.canDeploy(worldPosition, team);
  }

  /// Whether [y] is on [team]'s own side of the halfway line.
  ///
  /// The player's side walks toward y=0, so the player's own half is the
  /// bottom one. Keyed to the side rather than the colour, like everything
  /// else that has to know which end of the board is whose.
  bool _inOwnHalf(Team team, double y) {
    const mid = ArenaSpec.worldHeight / 2;
    return team == playerTeam ? y >= mid : y <= mid;
  }

  /// The live-building cap for one side, or a very large number when the
  /// rules set none.
  int get buildingCap =>
      economy.maxLiveBuildings > 0 ? economy.maxLiveBuildings : 1 << 30;

  /// How many of [team]'s buildings are standing right now.
  ///
  /// Dying ones do not count: a building on its death animation is already
  /// gone as far as the board is concerned, and counting it would leave the
  /// cap stuck for the length of the animation.
  int buildingsStandingFor(Team team) {
    var standing = 0;
    for (final unit in units) {
      if (unit is Building && unit.team == team && unit.isAlive) standing++;
    }
    return standing;
  }

  /// Whether [team] is at its building cap. Read by the HUD so a card that
  /// cannot be placed can say why.
  bool atBuildingCap(Team team) =>
      economy.maxLiveBuildings > 0 &&
      buildingsStandingFor(team) >= economy.maxLiveBuildings;

  /// Plays hand [slot] for [side] at [position], if it is legal and paid for.
  ///
  /// The single place a card ever becomes units. The player's drag and the
  /// bot's brain both end up here, so neither can bend the rules.
  bool playFromHand(MatchSide side, int slot, Vector2 position) {
    if (!acceptsInput) return false;
    final hand = side.hand;
    if (hand == null || slot < 0 || slot >= hand.handSize) return false;

    final id = hand.cardIdAt(slot);
    final card = cards.at(id, hand.levelOf(id));

    if (!canDeployFor(side.team, card, position)) return false;
    if (!side.elixir.spend(card.cost)) return false;

    if (card.isUnit) {
      spawnCard(
        card.id,
        team: side.team,
        position: position,
        level: card.level,
      );
      // Landing claims the ground. This is what makes dropping on enemy
      // colour worth doing rather than merely allowed: the circle under the
      // arriving bodies turns your colour on the spot.
      if (economy.deployAnywhere && economy.deployClaimRadius > 0) {
        arena.paintLayer.stamp(position, economy.deployClaimRadius, side.team);
      }
      // A puff under the arriving bodies, so a card landing has weight even
      // when the troop itself paints nothing.
      burst(position, side.team, count: 6, spread: 1.4, duration: 0.35);
      Audio.play(Sfx.deploy);
    } else {
      castSpell(card, side.team, position);
    }

    if (side == player) {
      cardsPlayed++;
      if (card.isSpell) spellsPlayed++;
    }

    hand.play(slot);
    return true;
  }

  /// Ends the player's drag. Places the card if the drop is legal and
  /// affordable, otherwise rejects it, having spent nothing.
  ///
  /// Returns true when something was actually deployed.
  bool endDeploy(Vector2? worldPosition) {
    final slot = draggingSlot.value;
    draggingSlot.value = null;
    deployOverlay.preview = null;
    if (slot == null || worldPosition == null) return false;
    return playFromHand(player, slot, worldPosition);
  }

  void cancelDeploy() {
    draggingSlot.value = null;
    deployOverlay.preview = null;
  }

  CardModel? _cardInSlot(int slot) {
    final controller = hand;
    if (controller == null || slot < 0 || slot >= controller.handSize) {
      return null;
    }
    final id = controller.cardIdAt(slot);
    return cards.at(id, controller.levelOf(id));
  }

  /// Components that finished — units done dying, shots that have landed —
  /// and are waiting to leave the tree.
  final List<Component> _despawned = <Component>[];

  /// Components waiting to join the world.
  ///
  /// Both spawning and despawning are queued for the same reason: a unit
  /// swinging or the bot playing a card happens inside the tree walk, and
  /// touching the world's child set from in there throws a concurrent
  /// modification. Everything joins and leaves at the top of the next frame.
  final List<Component> _pendingSpawns = <Component>[];

  /// Note this hooks [updateTree], not `update`: on a root [FlameGame] the
  /// latter is never called, because `update` is what kicks the tree walk off.
  @override
  void updateTree(double dt) {
    // Reaping here, before the walk, keeps removals outside the child
    // iteration — mutating the tree mid-update throws.
    if (_despawned.isNotEmpty) {
      for (final component in _despawned) {
        component.removeFromParent();
      }
      _despawned.clear();
    }
    if (_pendingSpawns.isNotEmpty) {
      for (final component in _pendingSpawns) {
        world.add(component);
      }
      _pendingSpawns.clear();
    }

    _applyTerritoryIncome();
    player.elixir.update(dt);
    opponent.elixir.update(dt);
    player.hand?.update(dt);
    opponent.hand?.update(dt);
    super.updateTree(dt);

    if (unitCount.value != units.length) unitCount.value = units.length;
  }

  /// Takes a unit off the field.
  ///
  /// It leaves the roster at once so nothing targets it, and leaves the
  /// component tree at the top of the next frame.
  void despawn(Unit unit) {
    units.remove(unit);
    despawnComponent(unit);
  }

  /// Takes anything else off the field at the top of the next frame — a shot
  /// that has landed, say. Removing during the tree walk throws.
  void despawnComponent(Component component) {
    if (!_despawned.contains(component)) _despawned.add(component);
  }

  /// Puts a loose component on the field at the top of the next frame.
  ///
  /// The counterpart to [despawnComponent], and required for the same reason:
  /// effects are spawned from inside `update` — a unit swinging, the bot
  /// playing a card — and `world.add` from in there mutates the child set
  /// Flame is part-way through walking, which throws and takes the match
  /// down with it.
  void spawnComponent(Component component) => _pendingSpawns.add(component);

  /// Sets both sides' income from how much of the board they hold.
  ///
  /// Reads the arena's latest coverage sample, which lands at 2 Hz, so this
  /// costs two multiplications a frame and never a readback.
  void _applyTerritoryIncome() {
    if (economy.territorySpread <= 0) return;
    final coverage = arena.coverage.value;
    player.elixir.rateMultiplier = economy.multiplierFor(
      coverage.forTeam(player.team),
    );
    opponent.elixir.rateMultiplier = economy.multiplierFor(
      coverage.forTeam(opponent.team),
    );
  }

  /// The camera kick, owned in one place so overlapping impacts do not fight
  /// over the viewfinder. Added in [onLoad].
  final ScreenShake screenShake = ScreenShake();

  /// Kicks the camera. Safe to call from anywhere, including before load.
  void shake({required double amplitude, double seconds = 0.25}) =>
      screenShake.shake(amplitude: amplitude, seconds: seconds);

  /// Throws paint droplets from [at] in [team]'s colour.
  ///
  /// Silently does nothing once the particle budget is spent — a splash that
  /// costs frames is worse than no splash.
  void burst(
    Vector2 at,
    Team team, {
    int count = 8,
    double spread = 2.4,
    double duration = 0.45,
  }) {
    final splatter = Splatter.maybe(
      at: at,
      team: team,
      random: _random,
      count: count,
      spread: spread,
      duration: duration,
    );
    if (splatter != null) _pendingSpawns.add(splatter);
  }

  /// Sends a shot from [from] to [at]. Paints where it lands if
  /// [paintRadius] is set.
  Projectile fireProjectile({
    required Vector2 from,
    required Vector2 at,
    required Team team,
    double paintRadius = 0,
    double speed = 11.0,
    double size = 0.16,
    double arcHeight = 0,
  }) {
    final shot = Projectile(
      from: from,
      destination: at.clone(),
      team: team,
      speed: speed,
      paintRadius: paintRadius,
      size2: size,
      arcHeight: arcHeight,
    );
    _pendingSpawns.add(shot);
    return shot;
  }

  /// Puts one body on the field. Deploy legality is the caller's problem;
  /// this is the raw spawn that cards, the bot and the sandbox all go through.
  Unit spawnUnit(
    String id, {
    required Team team,
    required Vector2 position,
    int level = 1,
  }) {
    final unit = registry.create(
      id,
      team: team,
      position: position,
      level: level,
    );
    unit.owner = this;
    units.add(unit);
    _pendingSpawns.add(unit);
    return unit;
  }

  /// Lands a spell at [position] for [team].
  ///
  /// Spells ignore the deploy rule entirely, so this is reachable anywhere on
  /// the arena — which is the whole point of Paint Bomb.
  void castSpell(CardModel card, Team team, Vector2 position) {
    final stats = card.spell;
    if (stats == null) return;

    final spell = spellsByEffect[stats.effect];
    if (spell == null) {
      // An effect in the JSON this build does not understand. Better to do
      // nothing visibly than to silently swallow it.
      assert(false, 'No implementation for spell effect ${stats.effect}');
      return;
    }

    spell.cast(game: this, caster: team, at: position, stats: stats);

    final wipes = stats.effect == SpellEffect.wipeToNeutral;
    spawnComponent(
      BurstEffect(
        at: position.clone(),
        radius: stats.radius,
        colour: wipes ? Palette.neutral : Palette.of(team),
      ),
    );

    // Spells are the biggest thing that happens in a match, so they get the
    // biggest reaction: droplets scaled to the radius and a real camera kick.
    burst(
      position,
      wipes ? Team.neutral : team,
      count: 14,
      spread: stats.radius * 0.8,
      duration: 0.55,
    );
    shake(amplitude: 0.10 + stats.radius * 0.055, seconds: 0.30);
    Audio.play(Sfx.splat);
  }

  /// Spawns a card's full body count, spread so they do not start stacked.
  List<Unit> spawnCard(
    String id, {
    required Team team,
    required Vector2 position,
    int level = 1,
  }) {
    final stats = registry.at(id, level);
    final spawned = <Unit>[];

    for (var i = 0; i < stats.count; i++) {
      final offset = stats.count == 1
          ? Vector2.zero()
          : _ringOffset(i, stats.count, stats.radius * 2.2);
      spawned.add(
        spawnUnit(
          id,
          team: team,
          position: _clampSpawn(position + offset, stats.radius),
          level: level,
        ),
      );
    }
    return spawned;
  }

  /// Evenly spaced points on a small circle, so a 6-body Swarmlets card lands
  /// as a group rather than a pile.
  Vector2 _ringOffset(int index, int count, double radius) {
    final angle = index / count * math.pi * 2;
    return Vector2(math.cos(angle), math.sin(angle))..scale(radius);
  }

  Vector2 _clampSpawn(Vector2 position, double radius) => Vector2(
    position.x.clamp(radius, ArenaSpec.worldWidth - radius),
    position.y.clamp(radius, ArenaSpec.worldHeight - radius),
  );

  /// Debug: fills the arena with bodies to check the 40-unit frame budget.
  void stressTest({int perSide = 20}) {
    for (var i = 0; i < perSide; i++) {
      final x = 1 + _random.nextDouble() * (ArenaSpec.worldWidth - 2);
      spawnUnit(
        registry.implemented[i % registry.implemented.length],
        team: playerTeam,
        position: Vector2(
          x,
          ArenaSpec.worldHeight - 2 - _random.nextDouble() * 4,
        ),
      );
      spawnUnit(
        registry.implemented[i % registry.implemented.length],
        team: playerTeam.opponent,
        position: Vector2(x, 2 + _random.nextDouble() * 4),
      );
    }
  }

  void clearUnits() {
    for (final unit in units.toList()) {
      despawn(unit);
    }
  }

  @override
  void onRemove() {
    // Bursts still in flight when the arena closes never get an onRemove of
    // their own, and their droplets would stay charged to the particle budget
    // for the life of the app — after enough matches nothing would splash at
    // all. Hand them all back explicitly.
    for (final splatter in world.children.whereType<Splatter>()) {
      splatter.release();
    }

    sandboxTeam.dispose();
    brushRadius.dispose();
    sandboxUnit.dispose();
    unitCount.dispose();
    draggingSlot.dispose();
    player.dispose();
    opponent.dispose();
    super.onRemove();
  }
}

/// Phase 1 harness: a brush covering the whole arena. Exists so the paint
/// layer can be exercised and profiled with no cards and no rules in the way.
class _PaintHarness extends PositionComponent with TapCallbacks, DragCallbacks {
  _PaintHarness({required this.game})
    : super(
        position: Vector2.zero(),
        size: Vector2(ArenaSpec.worldWidth, ArenaSpec.worldHeight),
        priority: 100,
      );

  final SplatfrontGame game;

  void _paint(Vector2 local) => game.arena.paintLayer.stamp(
    local,
    game.brushRadius.value,
    game.sandboxTeam.value,
  );

  @override
  void onTapDown(TapDownEvent event) => _paint(event.localPosition);

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _paint(event.localPosition);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    _paint(event.localStartPosition);
  }
}

/// Phase 2 harness: tap anywhere to drop the selected unit for the selected
/// side. Ignores the deploy rule, which arrives with cards in Phase 3.
class _UnitSandbox extends PositionComponent with TapCallbacks {
  _UnitSandbox({required this.game})
    : super(
        position: Vector2.zero(),
        size: Vector2(ArenaSpec.worldWidth, ArenaSpec.worldHeight),
        priority: 100,
      );

  final SplatfrontGame game;

  @override
  void onTapDown(TapDownEvent event) {
    final team = game.sandboxTeam.value;
    if (team == Team.neutral) return; // Nobody to fight for.
    game.spawnCard(
      game.sandboxUnit.value,
      team: team,
      position: event.localPosition,
    );
  }
}
