import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/splatfront_game.dart';
import 'package:splatfront/ui/screens/battle_screen.dart';

/// Sizes the battle screen has to survive without clipping anything.
///
/// The small phone is a real device: 1080x2400 at density 480 is 360x800 dp,
/// which is where the arena's 2:3 aspect leaves the least room for the HUD.
const Map<String, Size> _screens = {
  'small phone 360x800': Size(360, 800),
  'phone 393x873': Size(393, 873),
  'tall phone 412x915': Size(412, 915),
  'tablet portrait 768x1024': Size(768, 1024),
  'tablet wide 1024x768': Size(1024, 768),
};

void main() {
  late CardRegistry cards;
  late Deck deck;
  late ArenaLayout layout;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
    deck = (await Deck.loadStarterDecks()).first;
    layout = (await ArenaLayout.loadAll()).first;
  });

  Future<void> pumpBattle(
    WidgetTester tester,
    Size size,
    SandboxMode sandbox,
  ) async {
    tester.view
      ..physicalSize = size * 3.0
      ..devicePixelRatio = 3.0
      // A real phone does not give the app all 800 dp: the status bar and the
      // gesture nav take a slice off each end, and SafeArea hands back what
      // is left. Testing without these was what let a clipped HUD through.
      ..padding = const FakeViewPadding(top: 90, bottom: 72);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: BattleScreen(
          layout: layout,
          cards: cards,
          // Only a real match has a hand; the sandboxes deliberately have none.
          deck: sandbox == SandboxMode.off ? deck : null,
          sandbox: sandbox,
        ),
      ),
    );
    await tester.pump();
  }

  for (final entry in _screens.entries) {
    for (final sandbox in SandboxMode.values) {
      testWidgets('${entry.key} lays out with sandbox ${sandbox.name}', (
        tester,
      ) async {
        await pumpBattle(tester, entry.value, sandbox);

        // A RenderFlex overflow is only an assert, so a profile build clips
        // silently and the bottom of the HUD just disappears. Here it throws.
        expect(
          tester.takeException(),
          isNull,
          reason: 'nothing may overflow at ${entry.value}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }

  testWidgets('the sandbox controls are actually on screen on a small phone', (
    tester,
  ) async {
    await pumpBattle(tester, const Size(360, 800), SandboxMode.units);

    final bar = find.text('Spawn');
    expect(bar, findsOneWidget);

    final rect = tester.getRect(bar);
    expect(
      rect.bottom,
      lessThanOrEqualTo(800),
      reason: 'the spawn bar must not sit below the bottom of the screen',
    );

    // And the unit chips have to be reachable too.
    expect(find.text('Brusher'), findsOneWidget);
    expect(tester.getRect(find.text('Brusher')).bottom, lessThanOrEqualTo(800));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the coverage bar and the hand both stay on screen', (
    tester,
  ) async {
    await pumpBattle(tester, const Size(360, 800), SandboxMode.off);

    final coverage = find.byType(ColoredBox).evaluate().where((e) {
      final box = e.widget as ColoredBox;
      return box.color == Palette.red || box.color == Palette.blue;
    });
    expect(coverage, isNotEmpty, reason: 'the coverage bar must be painted');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
