import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:splatfront/tutorial_demo_main.dart';
import 'package:splatfront/ui/tutorial/coach_mark.dart';
import 'package:splatfront/ui/tutorial/game_hud_screen.dart';
import 'package:splatfront/ui/tutorial/hand_gesture_indicator.dart';
import 'package:splatfront/ui/tutorial/tutorial_flags.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // `flutter test` does not read the `fonts:` section of pubspec.yaml, and
    // the caption panel is laid out in Baloo 2, which is materially wider
    // than the fallback. Without this the overflow check below measures type
    // the app never renders.
    for (final (family, path) in const [
      ('Baloo2', 'assets/fonts/Baloo2.ttf'),
      ('Lexend', 'assets/fonts/Lexend.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  setUp(() => TutorialFlags.debugStore = <String, bool>{});
  tearDown(() => TutorialFlags.debugStore = null);

  /// A fresh install: nothing seen, nothing done.
  Future<void> pumpDemo(WidgetTester tester) async {
    await tester.pumpWidget(const TutorialDemoApp());
    // The sequence starts on a post-frame callback and then awaits the flag
    // read, so it takes a couple of pumps to appear.
    await tester.pumpAndSettle();
  }

  /// A mounted overlay entry outliving a test would leak into the next one.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Finder caption(String text) => find.text(text);

  testWidgets('the tutorial runs itself on a fresh install', (tester) async {
    await pumpDemo(tester);

    expect(caption('Swing at it'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    // A hand is over the target, not just a dimmed screen.
    expect(find.byType(HandGestureIndicator), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a device that has finished it is left alone', (tester) async {
    await TutorialFlags.setDone(GameHudScreen.combatTutorial, value: true);

    await pumpDemo(tester);

    expect(caption('Swing at it'), findsNothing);
    expect(find.byType(HandGestureIndicator), findsNothing);
    // And the HUD is live from the first tap, with nothing in the way.
    await tester.tap(find.text('Potion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You drink a potion'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the scrim blocks everything except the target', (tester) async {
    await pumpDemo(tester);

    // Step 1 is Attack. Potion is behind the scrim, so tapping it must do
    // nothing at all — not advance the step, and not drink the potion. This
    // is the guard that matters: a scrim that only dims is decoration.
    await tester.tap(find.text('Potion'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('You drink a potion'), findsNothing);
    expect(caption('Swing at it'), findsOneWidget, reason: 'still on step 1');
    expect(find.text('1 of 2'), findsOneWidget);
    // Potions untouched: the badge still reads 3.
    expect(find.text('3'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a blocked tap replays the hand rather than doing nothing', (
    tester,
  ) async {
    await pumpDemo(tester);
    final before = tester
        .widget<HandGestureIndicator>(find.byType(HandGestureIndicator))
        .key;

    await tester.tap(find.text('Potion'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final after = tester
        .widget<HandGestureIndicator>(find.byType(HandGestureIndicator))
        .key;
    expect(after, isNot(before), reason: 'the indicator did not remount');

    await unmount(tester);
  });

  testWidgets('tapping the target runs the real action and advances', (
    tester,
  ) async {
    await pumpDemo(tester);

    await tester.tap(find.text('Attack'));
    await tester.pumpAndSettle();

    // The button's own handler ran — the tutorial did not swallow the tap and
    // re-emit a fake one.
    expect(find.textContaining('You swing for 22'), findsOneWidget);
    expect(caption('Patch yourself up'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    // And the block has moved with the step: Attack is now behind the scrim.
    expect(caption('Swing at it'), findsNothing);

    await unmount(tester);
  });

  testWidgets('finishing the last step ends it and remembers', (tester) async {
    await pumpDemo(tester);

    await tester.tap(find.text('Attack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Potion'));
    await tester.pumpAndSettle();

    expect(caption('Patch yourself up'), findsNothing);
    expect(find.byType(HandGestureIndicator), findsNothing);
    // The potion was really drunk — three down to two — and the screen's own
    // onFinished ran on top of it, which is why the log now reads as the
    // sequence ending rather than as the last action.
    expect(find.text('2'), findsOneWidget, reason: 'the flask was not spent');
    expect(find.textContaining('Tutorial complete'), findsOneWidget);
    expect(
      await TutorialFlags.isDone(GameHudScreen.combatTutorial),
      isTrue,
      reason: 'it will run again on the next launch',
    );
    // The screen is live again: the full HUD accepts taps.
    await tester.tap(find.text('Attack'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You swing for 22'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Replay tutorial clears the flag as well as restarting', (
    tester,
  ) async {
    await TutorialFlags.setDone(GameHudScreen.combatTutorial, value: true);
    await pumpDemo(tester);
    expect(caption('Swing at it'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay tutorial'));
    await tester.pumpAndSettle();

    expect(caption('Swing at it'), findsOneWidget);
    // Cleared, not just restarted. Someone who backs out of a replay should
    // still be offered it next launch.
    expect(await TutorialFlags.isDone(GameHudScreen.combatTutorial), isFalse);

    await unmount(tester);
  });

  testWidgets('the movement tip demonstrates the swipe hand', (tester) async {
    await TutorialFlags.setDone(GameHudScreen.combatTutorial, value: true);
    await pumpDemo(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay movement tip'));
    await tester.pumpAndSettle();

    expect(caption('Get around'), findsOneWidget);
    final hand = tester.widget<HandGestureIndicator>(
      find.byType(HandGestureIndicator),
    );
    expect(hand.gesture, HandGesture.swipe);
    // And the *drag* file loaded, which is a different asset from the tap
    // one and would otherwise only be covered by the indicator existing.
    final drawn = find.descendant(
      of: find.byType(HandGestureIndicator),
      matching: find.byType(RawLottie),
    );
    expect(drawn, findsOneWidget);
    expect(tester.widget<RawLottie>(drawn).composition, isNotNull);
    // A one-step sequence has no "1 of 1" counter to read.
    expect(find.text('1 of 1'), findsNothing);

    // Dragging the pad — the one thing the scrim leaves reachable — finishes
    // it, which is the swipe half of the contract: the step advances on a
    // real drag, not on a tap.
    await tester.drag(find.text('Drag to move'), const Offset(60, 40));
    await tester.pumpAndSettle();

    expect(caption('Get around'), findsNothing);
    expect(await TutorialFlags.isDone(GameHudScreen.movementTutorial), isTrue);

    await unmount(tester);
  });

  testWidgets('the swipe hand rests visible instead of finishing faded out', (
    tester,
  ) async {
    await TutorialFlags.setDone(GameHudScreen.combatTutorial, value: true);
    await pumpDemo(tester);
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay movement tip'));
    // Settle, so the four glides have finished and the hand is at rest.
    await tester.pumpAndSettle();

    // A glide fades out at the end of each pass, so an indicator that fell
    // back to phase 0 when it completed would finish by vanishing — a coach
    // mark that quietly stops pointing at anything after five seconds.
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(HandGestureIndicator),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, greaterThan(0.9));

    await unmount(tester);
  });

  testWidgets('a report from the wrong control does not skip a step', (
    tester,
  ) async {
    // Every action reports unconditionally, so the screen never has to ask
    // whether a tutorial is running. That only works because the controller
    // ignores anything that is not the step it is on.
    final first = GlobalKey();
    final second = GlobalKey();
    final controller = TutorialController(id: 'harness');
    late BuildContext host;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return Scaffold(
              body: Column(
                children: [
                  SizedBox(key: first, width: 120, height: 44),
                  SizedBox(key: second, width: 120, height: 44),
                ],
              ),
            );
          },
        ),
      ),
    );

    controller.start(
      host,
      steps: [
        CoachMarkStep(id: 'first', target: first, message: 'one'),
        CoachMarkStep(id: 'second', target: second, message: 'two'),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);

    controller.report('second');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget, reason: 'it skipped ahead');

    controller.report('first');
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);

    controller.cancel();
    controller.dispose();
    await unmount(tester);
  });

  testWidgets('it lays out on a phone, caption and all', (tester) async {
    // The primary target is phone portrait. A widget test throws on an
    // overflow, so the assertions here are mostly the pumps themselves — and
    // the fonts loaded in setUpAll are what make that measurement real, since
    // Baloo 2 is materially wider than the fallback.
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpDemo(tester);
    expect(caption('Swing at it'), findsOneWidget);
    expect(find.textContaining('Tap Attack'), findsOneWidget);

    await tester.tap(find.text('Attack'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap Potion'), findsOneWidget);

    await tester.tap(find.text('Potion'));
    await tester.pumpAndSettle();
    expect(find.byType(HandGestureIndicator), findsNothing);

    await unmount(tester);
  });

  testWidgets('the hand is a Lottie composition that actually loaded', (
    tester,
  ) async {
    // Without this the suite cannot tell a working hand from a missing one.
    // Every other test finds the indicator by type, and the indicator has an
    // errorBuilder — deliberately, so a bad asset degrades the lesson instead
    // of taking the screen down — which means a malformed or unregistered
    // file would leave an empty box and pass everything.
    await pumpDemo(tester);

    final drawn = find.descendant(
      of: find.byType(HandGestureIndicator),
      matching: find.byType(RawLottie),
    );
    expect(drawn, findsOneWidget, reason: 'the composition never rendered');

    final composition = tester.widget<RawLottie>(drawn).composition;
    expect(composition, isNotNull, reason: 'the file did not parse');
    // Authored at 60fps over 72 frames. If these drift, the 1200ms cycle is
    // no longer playing the file at the speed it was drawn for.
    expect(composition!.frameRate, 60);
    expect(composition.durationFrames, closeTo(72, 0.5));

    await unmount(tester);
  });

  testWidgets('the overlay settles — nothing loops', (tester) async {
    // The house rule from CLAUDE.md section 11. A pulsing hand that never
    // stopped would not fail this suite, it would hang it: pumpAndSettle
    // waits for frames to stop being scheduled. This asserts they do.
    await pumpDemo(tester);
    expect(find.byType(HandGestureIndicator), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'the coach mark is still animating',
    );

    await unmount(tester);
  });

  testWidgets('reduced motion gets a still hand, not a missing one', (
    tester,
  ) async {
    // Set on the dispatcher rather than as an ancestor MediaQuery: MaterialApp
    // builds its own from the view and discards anything above it.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await pumpDemo(tester);

    expect(caption('Swing at it'), findsOneWidget);
    expect(find.byType(HandGestureIndicator), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a controller disposed mid-sequence takes its overlay with it', (
    tester,
  ) async {
    // The worst bug this file could have is an orphaned entry: a black screen
    // with no way out and nothing listening.
    await pumpDemo(tester);
    expect(caption('Swing at it'), findsOneWidget);

    await unmount(tester);
    expect(caption('Swing at it'), findsNothing);
  });

  test('a failed preference read reports "not seen", so the tutorial runs', () async {
    // debugStore null and no platform channel bound: SharedPreferences throws
    // and isDone has to swallow it. Failing the other way would leave a
    // first-time player staring at a HUD nobody explained.
    TutorialFlags.debugStore = null;
    expect(await TutorialFlags.isDone('never_written'), isFalse);
  });
}
