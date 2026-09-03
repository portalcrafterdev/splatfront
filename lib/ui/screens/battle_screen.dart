import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio.dart';
import '../../core/frame_log.dart';
import '../../core/palette.dart';
import '../../game/arena/arena_layout.dart';
import '../../game/bot/bot_difficulty.dart';
import '../../game/cards/card_registry.dart';
import '../../game/match/match_controller.dart';
import '../../game/match/match_result.dart';
import '../../game/splatfront_game.dart';
import '../../meta/campaign.dart';
import '../../meta/quests.dart';
import '../../game/units/units_registry.dart';
import '../widgets/card_tile.dart';
import '../widgets/match_background.dart';
import '../widgets/match_header.dart';
import '../widgets/elixir_meter.dart';
import '../widgets/frame_stats.dart';
import '../widgets/match_overlays.dart';
import '../widgets/responsive.dart';

/// The match screen. Only the arena and the HUD live in Flame; everything
/// around them is plain Flutter.
class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    required this.layout,
    required this.cards,
    this.deck,
    this.botDeck,
    this.botDifficulty,
    this.botTier = BotTier.normal,
    this.trophyRules,
    this.levels = const CardLevels(),
    this.botLevels = const CardLevels(),
    this.campaign,
    this.economy = MatchRules.flat,
    this.startingTrophies = 0,
    this.onFinished,
    this.playerTeam = Team.blue,
    this.sandbox = SandboxMode.off,
  });

  final ArenaLayout layout;
  final CardRegistry cards;

  /// The player's eight. Null in the debug sandboxes, which have no hand.
  final Deck? deck;

  /// The opponent. Null means an empty arena with no one to fight.
  final Deck? botDeck;
  final BotDifficulty? botDifficulty;
  final BotTier botTier;

  /// Trophy maths. Null runs the arena with no clock, which is what the
  /// debug sandboxes want.
  final TrophyRules? trophyRules;

  /// The player's card levels, so upgrades actually show up in the arena.
  final CardLevels levels;

  /// The opponent's card levels. The campaign scales these with the level
  /// number; a ladder match leaves the bot at level 1.
  final CardLevels botLevels;

  /// Set when this match is a campaign level, which swaps the trophy change
  /// on the end screen for the stars the level was worth.
  final CampaignBattle? campaign;

  /// Elixir income scaling. Flat in the sandboxes.
  final MatchRules economy;

  /// Trophies going in, which the end screen's change is measured against.
  final int startingTrophies;

  /// Called once when the match ends, so the meta layer can bank the
  /// trophies, the chest and the quest progress. Null in the sandboxes.
  /// Returns whether the chest the win earned was actually stored, so the
  /// end screen can tell the truth about it.
  final bool Function(MatchResult result, MatchTally tally)? onFinished;

  final Team playerTeam;

  /// Which debug sandbox to layer over the arena, if any.
  final SandboxMode sandbox;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  /// Anchors the world-coordinate conversion for drag-to-deploy.
  final GlobalKey _arenaKey = GlobalKey();

  late final SplatfrontGame _game = SplatfrontGame(
    layout: widget.layout,
    cards: widget.cards,
    deck: widget.deck,
    botDeck: widget.botDeck,
    botDifficulty: widget.botDifficulty,
    botTier: widget.botTier,
    trophyRules: widget.trophyRules,
    levels: widget.levels,
    botLevels: widget.botLevels,
    economy: widget.economy,
    startingTrophies: widget.startingTrophies,
    playerTeam: widget.playerTeam,
    sandbox: widget.sandbox,
  );

  /// Whether the match is held. A notifier rather than setState, because
  /// everything else on this screen is driven the same way and a rebuild of
  /// the whole battle screen would rebuild the GameWidget with it.
  final ValueNotifier<bool> _paused = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    FrameLog.start(widget.sandbox == SandboxMode.off ? 'match' : 'sandbox');
    // In an arena, so the fight is audible. The sandboxes count too: they
    // have no clock and no whistle, and they are still somewhere you watch
    // units hit each other.
    Audio.gameplayMuted = false;
    if (widget.sandbox == SandboxMode.off) {
      Audio.playMusic(Track.match);
      _game.match?.timeRemaining.addListener(_watchClock);
      _game.match?.phase.addListener(_watchPhase);
      _game.arena.coverage.addListener(_watchLead);
    }
  }

  @override
  void dispose() {
    FrameLog.stop();
    // Leaving the arena, by any route: the whistle, the back button, or a
    // rematch replacing this screen. Whatever is still moving down there
    // stops being audible the moment it is off screen.
    Audio.gameplayMuted = true;
    _game.match?.timeRemaining.removeListener(_watchClock);
    _game.match?.phase.removeListener(_watchPhase);
    // The arena disposes its own notifier on teardown, so this has to come
    // off before the game does.
    _game.arena.coverage.removeListener(_watchLead);
    if (widget.sandbox == SandboxMode.off) Audio.playMusic(Track.menu);
    _paused.dispose();
    super.dispose();
  }

  /// Drops the match loop at the whistle rather than when the screen goes.
  ///
  /// The match music used to play under the result screen until the player
  /// pressed a button to leave, which could be a while. Silencing the fight
  /// itself is [MatchController]'s job, since that is a match event rather
  /// than a screen one.
  void _watchPhase() {
    final match = _game.match;
    if (match == null || !match.phase.value.isOver) return;
    // The calm loop, not silence: the result screen has no clock on it and
    // can sit there as long as the player likes.
    Audio.playMusic(Track.menu);
  }

  /// Swaps to the percussion layer for the closing stretch, per section 12.
  void _watchClock() {
    final match = _game.match;
    if (match == null) return;
    if (match.phase.value == MatchPhase.finished) return;
    final closing = match.timeRemaining.value <= _finalPushSeconds;
    Audio.playMusic(closing ? Track.matchFinal : Track.match);
  }

  /// Who is ahead, last time we looked. Null until the first sample lands.
  bool? _playerAhead;

  void _watchLead() {
    final coverage = _game.arena.coverage.value;
    final mine = coverage.forTeam(widget.playerTeam);
    final theirs = coverage.forTeam(widget.playerTeam.opponent);

    // A dead heat is nobody's lead: without this the chime machine-guns while
    // the two shares trade places a fraction of a percent at a time.
    if ((mine - theirs).abs() < 0.02) return;

    final ahead = mine > theirs;
    if (_playerAhead == null) {
      _playerAhead = ahead;
      return;
    }
    if (_playerAhead == ahead) return;
    _playerAhead = ahead;
    Audio.play(Sfx.leadChange);
  }

  static const double _finalPushSeconds = 20;

  /// Screen point to arena units. Returns null only if the arena is not laid
  /// out yet; a point outside the arena maps to out-of-range coordinates,
  /// which the deploy check rejects on its own.
  Vector2? _toWorld(Offset globalPosition) {
    final box = _arenaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalPosition);
    return Vector2(
      local.dx / box.size.width * 16.0,
      local.dy / box.size.height * 24.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.hudSkyLow,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        // Dark icons on open sky.
        //
        // A dark bar was tried behind the phone's strip and looked like a
        // hole cut in the top of the screen — the sky has to run all the way
        // up or the page has a lid on it. What makes that safe is keeping
        // cloud out of the strip: see _Clouds. On bare sky a dark icon has
        // all the contrast it needs.
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Palette.hudTrayLow,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Stack(
          children: [
            // Behind everything, outside the SafeArea so it runs under the
            // status bar and the gesture bar rather than stopping in a hard
            // line at each.
            Positioned.fill(
              child: MatchBackground(playerTeam: _game.playerTeam),
            ),

            SafeArea(
              child: Stack(
                children: [
                  ResponsiveBuilder(
                    builder: (context, layout) => layout.handIsSideRail
                        ? _wideLayout(layout)
                        : _stackedLayout(layout),
                  ),
                  // Both of these sit over the whole thing, arena included.
                  // Pause goes under the result: if the whistle somehow lands
                  // in the same frame, the match is over and that is the
                  // screen that matters.
                  Positioned.fill(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _paused,
                      builder: (context, paused, _) => paused
                          ? PauseOverlay(
                              playerTeam: widget.playerTeam,
                              onResume: _resume,
                              onQuit: () => Navigator.of(context).pop(),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Positioned.fill(child: _resultOverlay()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Guards against banking the same match twice: the overlay rebuilds
  /// freely, but the profile may only be written once.
  bool _banked = false;

  /// Whether the win's chest went into a slot. Set the moment the match is
  /// banked, read by the end screen in the same build.
  bool _chestKept = false;

  /// Trophies, the chest a win earns, and quest progress — all in one call,
  /// the moment the match ends.
  void _bankResult(MatchResult result) {
    if (_banked || widget.onFinished == null) return;
    _banked = true;
    Audio.play(result.won ? Sfx.victory : Sfx.defeat);
    _chestKept = widget.onFinished!(
      result,
      MatchTally(
        won: result.won,
        cardsPlayed: _game.cardsPlayed,
        spellsPlayed: _game.spellsPlayed,
        paintSharePercent: (result.playerShare * 100).round(),
      ),
    );
  }

  Widget _resultOverlay() {
    final match = _game.match;
    if (match == null) return const SizedBox.shrink();

    return ValueListenableBuilder<MatchResult?>(
      valueListenable: match.result,
      builder: (context, result, _) {
        if (result == null) return const SizedBox.shrink();
        _bankResult(result);
        return ResultOverlay(
          result: result,
          chestKept: _chestKept,
          campaign: widget.campaign,
          onRematch: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => BattleScreen(
                layout: widget.layout,
                cards: widget.cards,
                deck: widget.deck,
                botDeck: widget.botDeck,
                botDifficulty: widget.botDifficulty,
                botTier: widget.botTier,
                trophyRules: widget.trophyRules,
                levels: widget.levels,
                botLevels: widget.botLevels,
                campaign: widget.campaign,
                economy: widget.economy,
                startingTrophies: widget.startingTrophies,
                onFinished: widget.onFinished,
                playerTeam: widget.playerTeam,
                sandbox: widget.sandbox,
              ),
            ),
          ),
          onHome: () => Navigator.of(context).pop(),
        );
      },
    );
  }

  /// Name plates, score, clock. The sandboxes have no opponent to name.
  Widget _header() => MatchHeader(
    coverage: _game.arena.coverage,
    match: _game.match,
    playerTeam: widget.playerTeam,
    botTier: widget.botTier,
    showPlates: widget.sandbox == SandboxMode.off,
    // The sandboxes have no clock to stop.
    onPause: widget.sandbox == SandboxMode.off ? _pause : null,
  );

  /// Holds the match.
  ///
  /// Flame's own [pauseEngine] rather than a flag the components check: the
  /// clock, the elixir bar, the hand cooldowns, the bot's decision timer and
  /// every unit's step all run off `update`, so stopping the loop stops all
  /// of them at once and none of them can be forgotten. A flag would have to
  /// be honoured in five places and would be wrong in the sixth.
  void _pause() {
    if (_paused.value) return;
    _game.cancelDeploy();
    _game.pauseEngine();
    // Whatever was mid-swing down there goes quiet, the same as it does at
    // the whistle and on the way out. The interface still speaks.
    Audio.gameplayMuted = true;
    _paused.value = true;
  }

  void _resume() {
    if (!_paused.value) return;
    Audio.gameplayMuted = false;
    _game.resumeEngine();
    _paused.value = false;
  }

  /// Phone and tablet portrait: header, arena, elixir, hand.
  Widget _stackedLayout(LayoutClass layout) {
    return Column(
      children: [
        _header(),
        Expanded(child: Center(child: _arena())),
        if (_game.hand != null) _tray(layout),
        _sandboxControls(),
      ],
    );
  }

  /// The elixir bar and the hand, on one raised deck at the foot of the
  /// screen.
  ///
  /// They were two loose rows floating on the background. Everything a player
  /// touches during a match is down here and none of it was grouped, so the
  /// bottom third of the screen had no structure at all — the cards read as
  /// stickers on the wallpaper. A single surface underneath makes it a
  /// console: the arena is the world, this is the panel you drive it from.
  ///
  /// Rounded and lit along the top edge only. The bottom runs off the screen,
  /// so a bottom edge would be a line the phone crops rather than a shape.
  Widget _tray(LayoutClass layout) => Container(
    padding: const EdgeInsets.only(top: 8),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Palette.hudTrayHigh, Palette.hudTrayLow],
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      border: Border(top: BorderSide(color: Palette.hudOutline, width: 2)),
      boxShadow: [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 14,
          offset: Offset(0, -4),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElixirMeter(elixir: _game.elixir, height: layout.elixirBarHeight),
        _Hand(game: _game, layout: layout, toWorld: _toWorld),
      ],
    ),
  );

  /// Wide: arena centred and letterboxed, hand on a right-side vertical rail
  /// with the elixir bar stood on its end beside it.
  Widget _wideLayout(LayoutClass layout) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _header(),
              Expanded(child: Center(child: _arena())),
              _sandboxControls(),
            ],
          ),
        ),
        if (_game.hand != null)
          SizedBox(
            width: layout.handCardWidth + 72,
            child: Row(
              children: [
                RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: 260,
                    child: ElixirMeter(
                      elixir: _game.elixir,
                      height: layout.elixirBarHeight,
                    ),
                  ),
                ),
                Expanded(
                  child: _Hand(
                    game: _game,
                    layout: layout,
                    toWorld: _toWorld,
                    vertical: true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sandboxControls() => switch (widget.sandbox) {
    SandboxMode.off => const SizedBox.shrink(),
    SandboxMode.paint => _PaintControls(game: _game),
    SandboxMode.units => _UnitControls(game: _game),
  };

  /// The arena keeps its 2:3 aspect at every size and is never stretched past
  /// [Breakpoints.maxArenaWidth] — a wider arena changes every deploy distance.
  Widget _arena() {
    final match = _game.match;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Breakpoints.maxArenaWidth),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // A bezel, not an outline.
            //
            // This was a 3px near-white rim, which made the brightest thing
            // on a dark screen a *border* — the eye went to the edge of the
            // board instead of to the board. A moulded surround does the same
            // job better: the gradient puts a light source overhead, the
            // hairline catches it along the top, and the board sits down
            // inside the frame rather than being ringed by it.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Palette.hudBezelHigh, Palette.hudBezelLow],
            ),
            border: Border.all(color: const Color(0x33FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            // Inside the bezel, so the paint does not bleed over it.
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GameWidget(key: _arenaKey, game: _game),
                ),
                // A shadow cast by the bezel onto the board along the top
                // edge, which is what sells the board as recessed. Kept to
                // the top only and very low: any more and it reads as dirt on
                // the paint, and the paint is the score.
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 10,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x3D000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
                if (match != null) ...[
                  Positioned.fill(child: WipeOverlay(match: match)),
                  Positioned.fill(child: CountdownOverlay(match: match)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four playable slots plus the next-card preview.
///
/// Deploying is a drag rather than a tap: press a card, drag over the arena to
/// aim, release to place. The ghost and the valid-cell glow are drawn inside
/// Flame; this widget only feeds it world coordinates.
class _Hand extends StatelessWidget {
  const _Hand({
    required this.game,
    required this.layout,
    required this.toWorld,
    this.vertical = false,
  });

  final SplatfrontGame game;
  final LayoutClass layout;
  final Vector2? Function(Offset globalPosition) toWorld;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final hand = game.hand!;

    return ValueListenableBuilder<List<String>>(
      valueListenable: hand.hand,
      builder: (context, slots, _) {
        return ValueListenableBuilder<double>(
          valueListenable: game.elixir.value,
          builder: (context, elixir, _) {
            return ValueListenableBuilder<int?>(
              valueListenable: game.draggingSlot,
              builder: (context, dragging, _) {
                if (vertical) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var slot = 0; slot < slots.length; slot++)
                        _slot(
                          slot,
                          slots[slot],
                          elixir,
                          dragging,
                          layout.handCardWidth,
                        ),
                      _nextPreview(layout.handCardWidth),
                    ],
                  );
                }

                // The spec asks for cards of "about 78 dp". On a 360 dp phone
                // four of those plus the next-card preview do not fit, so the
                // width is capped by what is actually available rather than
                // overflowing off the edge.
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final previewWidth = layout.handCardWidth * 0.6 + 10;
                    final forCards =
                        constraints.maxWidth -
                        previewWidth -
                        layout.handGap * slots.length;
                    final cardWidth = math.min(
                      layout.handCardWidth,
                      forCards / slots.length,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _nextPreview(cardWidth),
                          // The preview is not a fifth slot, and at a glance
                          // it looked like one: same art, same shape, sitting
                          // in the same row. A rule between them says where
                          // the hand starts.
                          Container(
                            width: 1,
                            height: cardWidth * 0.9,
                            margin: const EdgeInsets.only(right: 2),
                            color: Palette.hudTextDim.withValues(alpha: 0.22),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var slot = 0; slot < slots.length; slot++)
                                  _slot(
                                    slot,
                                    slots[slot],
                                    elixir,
                                    dragging,
                                    cardWidth,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _slot(
    int slot,
    String cardId,
    double elixir,
    int? dragging,
    double width,
  ) {
    final card = game.cards.at(cardId, game.hand!.levelOf(cardId));
    final affordable = elixir >= card.cost;

    return Padding(
      padding: EdgeInsets.all(layout.handGap / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          if (!game.beginDeploy(slot)) return;
          final world = toWorld(details.globalPosition);
          if (world != null) game.updateDeploy(world);
        },
        onPanUpdate: (details) {
          final world = toWorld(details.globalPosition);
          if (world != null) game.updateDeploy(world);
        },
        onPanEnd: (details) => game.endDeploy(toWorld(details.globalPosition)),
        onPanCancel: game.cancelDeploy,
        child: CardTile(
          card: card,
          width: width,
          team: game.playerTeam,
          affordable: affordable,
          dragging: dragging == slot,
          // Read straight off the controller rather than through a notifier:
          // the elixir bar already rebuilds this hand every frame, so the
          // countdown is current without a second stream pushing rebuilds.
          cooldown: game.hand!.cooldownFraction(slot),
          cooldownSeconds: game.hand!.secondsLeft(slot),
        ),
      ),
    );
  }

  /// The card that will fill whichever slot is played next, at 60%.
  Widget _nextPreview(double cardWidth) => ValueListenableBuilder<String>(
    valueListenable: game.hand!.next,
    builder: (context, nextId, _) {
      if (nextId.isEmpty) return const SizedBox.shrink();
      final card = game.cards.at(nextId, game.hand!.levelOf(nextId));
      return Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Next',
              style: TextStyle(
                color: Palette.hudTextDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            CardTile(
              card: card,
              width: cardWidth * 0.6,
              scale: 0.6,
              team: game.playerTeam,
            ),
          ],
        ),
      );
    },
  );
}

/// Shared chrome for the debug bars.
class _SandboxBar extends StatelessWidget {
  const _SandboxBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Palette.hudSurface,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// Picks the side the sandbox acts for.
class _TeamPicker extends StatelessWidget {
  const _TeamPicker({required this.selection, this.includeNeutral = true});

  final ValueNotifier<Team> selection;
  final bool includeNeutral;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Team>(
    valueListenable: selection,
    builder: (context, current, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final team in Team.values)
          if (includeNeutral || team != Team.neutral)
            GestureDetector(
              onTap: () => selection.value = team,
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: Palette.of(team),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: current == team
                        ? Palette.hudText
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

const TextStyle _labelStyle = TextStyle(
  color: Palette.hudTextDim,
  fontSize: 11,
  letterSpacing: 0.5,
);

/// Phase 1: drive the paint layer with no cards, no units and no rules.
class _PaintControls extends StatelessWidget {
  const _PaintControls({required this.game});

  final SplatfrontGame game;

  @override
  Widget build(BuildContext context) => _SandboxBar(
    children: [
      Row(
        children: [
          const Text('Brush', style: _labelStyle),
          const SizedBox(width: 10),
          _TeamPicker(selection: game.sandboxTeam),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: game.brushRadius,
              builder: (context, radius, _) => Slider(
                value: radius,
                min: 0.3,
                max: 3.5,
                activeColor: Palette.accent,
                onChanged: (v) => game.brushRadius.value = v,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Phase 2: spawn units and watch them fight. Tap the arena to place the
/// selected unit for the selected side.
class _UnitControls extends StatelessWidget {
  const _UnitControls({required this.game});

  final SplatfrontGame game;

  @override
  Widget build(BuildContext context) {
    return _SandboxBar(
      children: [
        Row(
          children: [
            const Text('Spawn', style: _labelStyle),
            const SizedBox(width: 10),
            _TeamPicker(selection: game.sandboxTeam, includeNeutral: false),
            const Spacer(),
            ValueListenableBuilder<int>(
              valueListenable: game.unitCount,
              builder: (context, count, _) =>
                  Text('$count units', style: _labelStyle),
            ),
          ],
        ),
        const Align(alignment: Alignment.centerLeft, child: FrameStats()),
        const SizedBox(height: 6),
        ValueListenableBuilder<String>(
          valueListenable: game.sandboxUnit,
          builder: (context, selected, _) => Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final id in game.registry.implemented)
                _Chip(
                  label: game.registry[id].name,
                  selected: id == selected,
                  onTap: () => game.sandboxUnit.value = id,
                ),
              _Chip(
                label: '+40 stress',
                selected: false,
                onTap: () => game.stressTest(),
              ),
              _Chip(
                label: 'Clear',
                selected: false,
                onTap: () => game.clearUnits(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Palette.accent : Palette.hudBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected
              ? Palette.accent
              : Palette.hudTextDim.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Palette.hudTextDim,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
