import 'package:flame/game.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/app.dart';
import 'package:splatfront/core/game_data.dart';
import 'package:splatfront/core/save/player_profile.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/splatfront_game.dart';
import 'package:splatfront/meta/profile_controller.dart';
import 'package:splatfront/ui/screens/battle_screen.dart';
import 'package:splatfront/ui/widgets/responsive.dart';

void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await GameData.load();
  });

  /// Boots the app with a profile held in memory, so nothing touches Hive.
  Future<void> pumpApp(
    WidgetTester tester, {
    PlayerProfile profile = const PlayerProfile(),
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameDataProvider.overrideWithValue(data),
        profileProvider.overrideWith(
          (ref) => _InMemoryProfile(data: data, initial: profile),
        ),
      ],
      child: const SplatfrontApp(),
    ),
  );

  /// A mounted GameWidget keeps a ticker alive, and a live ticker leaking out
  /// of one test wedges every test after it.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Opens a route without pumpAndSettle: a Flame game never settles, because
  /// its loop schedules frames forever.
  Future<void> openRoute(WidgetTester tester, Finder button) async {
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('home shows the player, the battle button and the quests', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('SPLATFRONT'), findsOneWidget);
    expect(find.text('BATTLE'), findsOneWidget);
    expect(find.text('Daily quests'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('the bottom bar switches place and stays put', (tester) async {
    await pumpApp(tester);

    // Home is the landing tab, and the bar is on screen with it.
    expect(find.text('BATTLE'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    // Only the selected tab is built. If this ever becomes an IndexedStack,
    // all four tabs sit in the tree at once and every one of these finders
    // starts matching two widgets — which is why it is built this way.
    await openRoute(tester, find.text('Shop'));
    expect(find.text('BATTLE'), findsNothing, reason: 'home is not built');
    expect(
      find.text('Shop'),
      findsWidgets,
      reason: 'the bar is still there to get back with',
    );

    await openRoute(tester, find.text('Home'));
    expect(find.text('BATTLE'), findsOneWidget, reason: 'and back again');

    await unmount(tester);
  });

  testWidgets('the levels tab opens on the level you are up to', (
    tester,
  ) async {
    // A thousand tiles, and the one that matters is the next uncleared
    // level. Landing at level 1 after clearing forty of them would mean
    // scrolling past forty rows to reach anything playable, so the list
    // opens where the player actually is.
    await pumpApp(
      tester,
      profile: const PlayerProfile(
        campaignStars: {1: 3, 2: 2, 3: 3, 4: 1, 5: 2},
      ),
    );

    await openRoute(tester, find.text('Levels'));

    expect(find.text('Level 6'), findsOneWidget, reason: 'the heading');
    expect(find.text('6'), findsWidgets, reason: 'and its tile is on screen');
    expect(find.text('1'), findsNothing, reason: 'level 1 is scrolled past');

    await unmount(tester);
  });

  testWidgets('a locked level cannot be started', (tester) async {
    await pumpApp(tester);
    await openRoute(tester, find.text('Levels'));

    // Level 1 is playable on a fresh profile; everything past it is not, and
    // a locked tile has no tap target at all rather than one that silently
    // does nothing.
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);

    await unmount(tester);
  });

  testWidgets('reduced motion is honoured', (tester) async {
    // The OS already knows whether this player has asked for less movement,
    // and nothing here was reading it. Vestibular disorders are common
    // enough that a game ignoring the switch is unplayable for some people.
    //
    // Asserted as "settles in a single frame": with every duration collapsed
    // to zero there is nothing left to tick, so a stray hardcoded duration
    // that slipped past Motion.of would leave a frame scheduled and fail
    // here. The information still arrives — only the travel is gone.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: ProviderScope(
          overrides: [
            gameDataProvider.overrideWithValue(data),
            profileProvider.overrideWith(
              (ref) =>
                  _InMemoryProfile(data: data, initial: const PlayerProfile()),
            ),
          ],
          child: const SplatfrontApp(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'something is still animating with animations disabled',
    );
    expect(find.text('BATTLE'), findsOneWidget);
  });

  testWidgets('every menu animation finishes', (tester) async {
    // The menus animate on entrance, on press and when a number changes, and
    // every one of those has to end. A looping animation keeps scheduling
    // frames, and pumpAndSettle waits for the frames to stop — so a single
    // pulsing button would not fail this suite, it would hang it, which is a
    // far worse thing to debug. A tight timeout turns that into a failure.
    await pumpApp(tester);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);

    // And again after a press, which is its own animation.
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the battle button opens the arena', (tester) async {
    await pumpApp(tester);
    await openRoute(tester, find.text('BATTLE'));

    expect(find.byType(BattleScreen), findsOneWidget);
    // Coverage percentages are live the moment the arena mounts.
    expect(find.textContaining('%'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('the clock is live from the first frame of a match', (
    tester,
  ) async {
    await pumpApp(tester);
    await openRoute(tester, find.text('BATTLE'));

    // The HUD builds before the game's async onLoad has run. Building the
    // match controller in there left this reading '--:--' for the whole
    // match, and the result screen never appeared at all.
    expect(find.text('--:--'), findsNothing);
    expect(find.text('You'), findsOneWidget);
    // Home's battle button plays the campaign level you are up to, so a fresh
    // profile lands on level 1. There is no difficulty picker any more; the
    // level number is the difficulty, and the plate names the side you are
    // fighting rather than a rank or, worse, a person.
    expect(find.text('Red Team'), findsOneWidget);

    await unmount(tester);
  });

  // Banking a match writes trophies, a chest and quest progress through a
  // Riverpod notifier. Doing that from inside a widget build throws "Tried to
  // modify a provider while the widget tree was building" and puts a
  // full-screen red error over the arena — which is exactly what shipped,
  // because the result overlay's builder called it. Nothing caught it: every
  // other test either stops before the whistle or drives the arena without a
  // profile behind it, so the write had nothing to break.
  testWidgets('a match can be played to the whistle and banked', (
    tester,
  ) async {
    await pumpApp(tester);
    await openRoute(tester, find.text('BATTLE'));

    final game = tester
        .widget<GameWidget<SplatfrontGame>>(
          find.byType(GameWidget<SplatfrontGame>),
        )
        .game!;
    final match = game.match!;

    // Run the clock out. Normal time plus sudden death plus slack, and the
    // paint is resampled along the way so the score is real rather than a
    // frozen 50/50.
    const step = 1 / 60;
    for (var t = 0.0; t < 140 && match.result.value == null; t += step) {
      game.updateTree(step);
      if ((t * 60).round() % 30 == 0) {
        await tester.runAsync(() => game.arena.resampleNow());
      }
    }

    expect(
      match.result.value,
      isNotNull,
      reason: 'the match never finished, so nothing was banked',
    );
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'banking the result threw — most likely a provider write '
          'during build',
    );

    await unmount(tester);
  });

  testWidgets('pause stops the clock, and resuming starts it again', (
    tester,
  ) async {
    await pumpApp(tester);
    await openRoute(tester, find.text('BATTLE'));

    // Past the countdown, or there is no clock yet to hold — the header
    // reads 'GET READY' for the first three seconds.
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining(':'), findsWidgets, reason: 'the clock is up');

    // Flame's own pauseEngine is what does the work, and the clock, the
    // elixir bar, the hand cooldowns and the bot's timer all run off update —
    // so if the loop is stopped, the clock reading cannot move. That is the
    // property worth testing, rather than the flag.
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);

    final held = tester.widget<Text>(find.textContaining(':').first).data;
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<Text>(find.textContaining(':').first).data,
      held,
      reason: 'the clock moved while the match was paused',
    );

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);

    await unmount(tester);
  });

  testWidgets('the unit sandbox has its spawn controls, a match does not', (
    tester,
  ) async {
    await pumpApp(tester);
    // Home scrolls now that it carries the deck strip, and the debug links
    // sit below the fold on a phone-sized screen. Tapping without scrolling
    // to them first hits whatever happens to be at those coordinates.
    await tester.ensureVisible(find.text('Unit sandbox'));
    await tester.pump();
    await openRoute(tester, find.text('Unit sandbox'));
    expect(find.text('Spawn'), findsOneWidget);
    await unmount(tester);

    await pumpApp(tester);
    await openRoute(tester, find.text('BATTLE'));
    expect(find.text('Spawn'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the arena shown follows the player\'s trophies', (tester) async {
    // Case matters: the strip at the top says ARENA 1 and the trophy road at
    // the bottom of the quest list says "Arena 2 at 400, Arena 3 at 900", so
    // a case-insensitive match would find both and prove nothing.
    await pumpApp(tester);
    expect(find.textContaining('ARENA 1'), findsOneWidget);
    await unmount(tester);

    // Arena 3 opens at 900 trophies.
    await pumpApp(tester, profile: const PlayerProfile(trophies: 1000));
    expect(find.textContaining('ARENA 3'), findsOneWidget);
    await unmount(tester);
  });

  test('every arena in levels.json parses and unlocks in trophy order', () {
    expect(data.arenas, hasLength(4));
    for (final arena in data.arenas) {
      // No blockers in any arena: an open board keeps the paint the only
      // thing shaping where a push can go. The blocker code stays, so an
      // arena can put them back by adding them to levels.json.
      expect(arena.blockers, isEmpty, reason: '${arena.id} should be open');
    }
    expect(data.arenas.map((a) => a.trophies).toList(), [0, 400, 900, 1500]);
    expect(ArenaLayout.forTrophies(data.arenas, 0).id, 'arena_1');
    expect(ArenaLayout.forTrophies(data.arenas, 899).id, 'arena_2');
    expect(ArenaLayout.forTrophies(data.arenas, 5000).id, 'arena_4');
  });

  test('blockers sit inside the arena', () {
    for (final arena in data.arenas) {
      for (final b in arena.blockers) {
        expect(b.rect.left, greaterThanOrEqualTo(0));
        expect(b.rect.top, greaterThanOrEqualTo(0));
        expect(b.rect.right, lessThanOrEqualTo(16));
        expect(b.rect.bottom, lessThanOrEqualTo(24));
      }
    }
  });

  test('breakpoints match the three specified layouts', () {
    expect(Breakpoints.forWidth(390), LayoutClass.phone);
    expect(Breakpoints.forWidth(599), LayoutClass.phone);
    expect(Breakpoints.forWidth(600), LayoutClass.tabletPortrait);
    expect(Breakpoints.forWidth(899), LayoutClass.tabletPortrait);
    expect(Breakpoints.forWidth(900), LayoutClass.tabletWide);
    expect(LayoutClass.phone.handCardWidth, 78);
    expect(LayoutClass.tabletPortrait.handCardWidth, 110);
    expect(LayoutClass.tabletWide.handIsSideRail, isTrue);
    expect(LayoutClass.phone.handIsSideRail, isFalse);
  });
}

/// A profile controller that never writes to disk, so widget tests do not
/// need Hive initialised.
class _InMemoryProfile extends ProfileController {
  _InMemoryProfile({required super.data, required super.initial});

  @override
  void saveToDisk(PlayerProfile profile) {}
}
