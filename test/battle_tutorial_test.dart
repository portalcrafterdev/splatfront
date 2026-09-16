import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/match/match_result.dart';
import 'package:splatfront/game/splatfront_game.dart';
import 'package:splatfront/meta/campaign.dart';
import 'package:splatfront/ui/screens/battle_screen.dart';
import 'package:splatfront/ui/tutorial/hand_gesture_indicator.dart';
import 'package:splatfront/ui/tutorial/tutorial_flags.dart';
import 'package:splatfront/ui/widgets/card_tile.dart';

/// The battle screen never settles — a Flame game schedules frames forever —
/// so every wait in here is an explicit pump and never `pumpAndSettle`.
void main() {
  late CardRegistry cards;
  late Deck deck;
  late ArenaLayout layout;
  late CampaignConfig campaign;

  const rules = TrophyRules(
    win: 30,
    loss: -25,
    trophiesPerAdjustment: 25,
    maxAdjustment: 10,
    botTrophyOffset: [0, 0],
  );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    deck = (await Deck.loadStarterDecks()).first;
    layout = (await ArenaLayout.loadAll()).first;
    campaign = await CampaignConfig.load();
    for (final (family, path) in const [
      ('Baloo2', 'assets/fonts/Baloo2.ttf'),
      ('Lexend', 'assets/fonts/Lexend.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  setUp(() => TutorialFlags.debugStore = <String, bool>{});
  tearDown(() => TutorialFlags.debugStore = null);

  /// Opens a real match on a real phone size and runs the countdown out.
  Future<void> pumpBattle(
    WidgetTester tester, {
    SandboxMode sandbox = SandboxMode.off,
    int level = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(393, 873) * 3.0
      ..devicePixelRatio = 3.0
      ..padding = const FakeViewPadding(top: 90, bottom: 72);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BattleScreen(
          layout: layout,
          cards: cards,
          deck: sandbox == SandboxMode.off ? deck : null,
          trophyRules: sandbox == SandboxMode.off ? rules : null,
          campaign: sandbox == SandboxMode.off
              ? CampaignBattle(level: level, config: campaign)
              : null,
          sandbox: sandbox,
        ),
      ),
    );
    await tester.pump();
    // Past the three second countdown, which is when the marks are offered —
    // and deliberately not before, because the hand refuses every card until
    // the whistle, so a "drag a card" step there would ask for something the
    // game itself would reject.
    await _pumpFor(tester, const Duration(seconds: 5));

    if (sandbox != SandboxMode.off) return;
    // The deploy map is refreshed by the coverage sampler, which reads the
    // paint layer back off a `ui.Image` — and that never completes inside
    // `flutter test` unless it is run through `runAsync`. Without this the
    // board reads as neutral ground everywhere and *every* drop is refused,
    // so the drag step below could never be finished. `deploy_test.dart`
    // primes it exactly the same way.
    await tester.runAsync(() => _game(tester).arena.resampleNow());
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('a first match opens with the coach marks up', (tester) async {
    await pumpBattle(tester);

    expect(find.text('Blue is you'), findsOneWidget);
    expect(find.textContaining('painted more of the board'), findsOneWidget);
    // A step that only points has nothing to press, so it takes a tap
    // anywhere — and says so.
    expect(find.text('Tap to carry on'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the clock is held while the marks are up', (tester) async {
    await pumpBattle(tester);

    // The clock is what a new player loses to while they read a caption.
    final before = _clock(tester);
    await _pumpFor(tester, const Duration(seconds: 6));

    expect(
      _clock(tester),
      before,
      reason: 'six seconds of a ninety second match went by while reading',
    );

    await unmount(tester);
  });

  testWidgets('tapping through reaches the drag step', (tester) async {
    await pumpBattle(tester);

    // Tapping the middle of the screen — the arena, which would otherwise do
    // nothing at all — is the "anywhere" contract.
    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Cards cost elixir'), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);

    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Send one in'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);

    // The last step asks for something, so it wears a hand and drops the
    // "tap to carry on" — tapping the board will not get past it.
    expect(find.text('Tap to carry on'), findsNothing);
    final hand = tester.widget<HandGestureIndicator>(
      find.byType(HandGestureIndicator),
    );
    expect(hand.gesture, HandGesture.swipe);
    expect(
      hand.travel.dy,
      lessThan(0),
      reason: 'the hand should sweep up, out of the tray and onto the board',
    );

    // And the clock is still held on the step that waits longest.
    final before = _clock(tester);
    await _pumpFor(tester, const Duration(seconds: 4));
    expect(_clock(tester), before);

    await unmount(tester);
  });

  testWidgets('tapping the board does not get past the drag step', (
    tester,
  ) async {
    await pumpBattle(tester);
    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Send one in'), findsOneWidget);

    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));

    expect(
      find.text('Send one in'),
      findsOneWidget,
      reason: 'a tap stood in for the drag it is asking for',
    );

    await unmount(tester);
  });

  testWidgets('a drop the game refuses does not count as a deploy', (
    tester,
  ) async {
    await pumpBattle(tester);
    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Send one in'), findsOneWidget);

    // Far enough up to land in the top half, which is the opponent's colour
    // — the deploy rule refuses it and nothing is spent. The step is asking
    // for a card to be *placed*, so a drag that placed nothing must leave it
    // exactly where it was, still explaining the rule that just bit.
    await tester.timedDrag(
      find.byType(CardTile).at(1),
      const Offset(0, -520),
      const Duration(milliseconds: 400),
    );
    await _pumpFor(tester, const Duration(milliseconds: 600));

    expect(
      find.text('Send one in'),
      findsOneWidget,
      reason: 'a refused drop was treated as a deploy',
    );

    await unmount(tester);
  });

  testWidgets('dragging a card finishes it and lets the clock go', (
    tester,
  ) async {
    await pumpBattle(tester);
    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tapAt(const Offset(196, 400));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Send one in'), findsOneWidget);

    // Up from the first playable slot onto the bottom of the board, which is
    // the player's own half and therefore a legal drop. Index 1, because the
    // "Next" preview is the first CardTile in the row and is not a slot.
    await tester.timedDrag(
      find.byType(CardTile).at(1),
      const Offset(0, -170),
      const Duration(milliseconds: 300),
    );
    await _pumpFor(tester, const Duration(milliseconds: 600));

    expect(find.text('Send one in'), findsNothing);
    expect(find.byType(HandGestureIndicator), findsNothing);

    final before = _clock(tester);
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(
      _clock(tester),
      lessThan(before),
      reason: 'the match is still frozen after the marks finished',
    );

    await unmount(tester);
  });

  testWidgets('the marks run again every time level 1 is played', (
    tester,
  ) async {
    // The reversal of the once-per-device flag. Level 1 is three taps long
    // and exists to be replayed.
    await pumpBattle(tester);
    expect(find.text('Blue is you'), findsOneWidget);
    await unmount(tester);

    await pumpBattle(tester);
    expect(
      find.text('Blue is you'),
      findsOneWidget,
      reason: 'the second run of level 1 was left un-taught',
    );

    await unmount(tester);
  });

  testWidgets('an ordinary level gets no marks, and is never held', (
    tester,
  ) async {
    await pumpBattle(tester, level: 2);

    expect(find.text('Blue is you'), findsNothing);
    expect(find.byType(HandGestureIndicator), findsNothing);

    // Nothing is holding the clock. This is the half that would strand every
    // level in the game if the hold ever escaped the walkthrough.
    final before = _clock(tester);
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(_clock(tester), lessThan(before));

    await unmount(tester);
  });

  testWidgets('a sandbox gets no marks', (tester) async {
    await pumpBattle(tester, sandbox: SandboxMode.paint);

    expect(find.text('Blue is you'), findsNothing);

    await unmount(tester);
  });
}

/// The live game behind the arena. `GameWidget` is generic, so `find.byType`
/// does not match `GameWidget<SplatfrontGame>` and the predicate is needed.
SplatfrontGame _game(WidgetTester tester) {
  final widget = tester.widget(
    find.byWidgetPredicate(
      (w) => w.runtimeType.toString().startsWith('GameWidget'),
    ),
  );
  // ignore: avoid_dynamic_calls
  return (widget as dynamic).game as SplatfrontGame;
}

/// Pumps frame by frame for [total]. The battle screen has a live game loop,
/// so there is no settling to wait on.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const stepDuration = Duration(milliseconds: 100);
  for (var spent = Duration.zero; spent < total; spent += stepDuration) {
    await tester.pump(stepDuration);
  }
}

/// Seconds left, read off the HUD rather than out of the controller — the
/// digits on screen are what a player is losing time against.
///
/// Returned as a number, not as the `m:ss` string it is rendered as: string
/// order is not clock order, and comparing the two as text quietly answers a
/// different question.
int _clock(WidgetTester tester) {
  final digits = RegExp(r'^(\d+):(\d\d)$');
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final match = digits.firstMatch(text.data ?? '');
    if (match == null) continue;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }
  fail('no clock on the match screen');
}
