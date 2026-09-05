import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/screen_wake.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/ui/screens/battle_screen.dart';

/// The screen staying awake through a match.
///
/// The thing worth pinning is not that it turns on — it is that it turns
/// **off**, by every route out of an arena. A wakelock that leaks is a phone
/// that quietly cooks in somebody's pocket, and nothing on screen would say
/// so; it arrives as a one-star review about battery.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CardRegistry cards;
  late ArenaLayout layout;
  late Deck deck;

  setUpAll(() async {
    cards = await CardRegistry.load();
    layout = (await ArenaLayout.loadAll()).first;
    deck = (await Deck.loadStarterDecks()).first;
  });

  setUp(ScreenWake.resetForTest);

  test('nothing is held until something asks', () {
    // `request` is called from the battle screen and nowhere else, so a suite
    // that never opens an arena never touches the platform channel.
    expect(ScreenWake.isHeld, isFalse);
  });

  test('asking twice for the same state is one call, not two', () {
    // The whistle releases the lock and `dispose` releases it again moments
    // later. Both are correct and neither should reach the platform twice.
    ScreenWake.request(true);
    expect(ScreenWake.isHeld, isTrue);
    ScreenWake.request(true);
    expect(ScreenWake.isHeld, isTrue);
    ScreenWake.request(false);
    expect(ScreenWake.isHeld, isFalse);
  });

  testWidgets('an arena holds the screen and lets go on the way out', (
    tester,
  ) async {
    // No trophy rules, so this screen has no clock and no whistle — the exact
    // case a whistle-only release would miss, and the one the audio mute got
    // wrong first time round. Leaving by the back button has to be enough.
    await tester.pumpWidget(
      MaterialApp(home: BattleScreen(layout: layout, cards: cards, deck: deck)),
    );
    await tester.pump();
    expect(
      ScreenWake.isHeld,
      isTrue,
      reason: 'a match is ninety seconds of not touching the glass',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      ScreenWake.isHeld,
      isFalse,
      reason: 'left the arena with no whistle, and it let go anyway',
    );
  });

  testWidgets('a menu never holds the screen', (tester) async {
    // The rule that keeps this a comfort rather than a complaint: the lock is
    // for the arena only. A player who leaves the Collection open on a table
    // gets their phone's normal screen timeout.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('a menu'))),
    );
    await tester.pump();
    expect(ScreenWake.isHeld, isFalse);
  });
}
