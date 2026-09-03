import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/app.dart';
import 'package:splatfront/core/game_data.dart';
import 'package:splatfront/core/save/player_profile.dart';
import 'package:splatfront/meta/profile_controller.dart';
import 'package:splatfront/ui/screens/chest_screen.dart';
import 'package:splatfront/ui/widgets/unit_art_view.dart';

/// The chest screen, end to end.
///
/// The controller's timer rules are covered in `meta_test.dart`. This is
/// about the half a player actually touches: does the button appear, does
/// pressing it do the thing, and does the screen notice when a timer runs
/// out. A chest that is ready in the model but has no OPEN button on screen
/// is a chest that will not open.
///
/// Chest readiness is measured against the wall clock, which a widget test
/// cannot fast-forward, so the fixtures start their timers in the past
/// instead.
void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await GameData.load();
  });

  Future<ProfileController> pump(
    WidgetTester tester,
    PlayerProfile profile,
  ) async {
    final controller = _InMemoryProfile(data: data, initial: profile);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDataProvider.overrideWithValue(data),
          profileProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: ChestScreen()),
      ),
    );
    await tester.pump();
    return controller;
  }

  /// The screen ticks once a second to refresh the countdown; a live ticker
  /// leaking out of one test wedges the next.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('tapping the chest on Home reaches the chest screen', (
    tester,
  ) async {
    // The reported symptom was "I win, a chest arrives, and it will not
    // open". The first thing that has to work is getting to the screen where
    // opening happens at all.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDataProvider.overrideWithValue(data),
          profileProvider.overrideWith(
            (ref) => _InMemoryProfile(
              data: data,
              initial: const PlayerProfile(chests: [ChestSlot(typeId: 'wood')]),
            ),
          ),
        ],
        child: const SplatfrontApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(ChestScreen), findsNothing);
    // Tapped by its icon rather than by an exported widget type: this should
    // work the way a thumb works, not through a seam opened for the test.
    await tester.tap(find.byIcon(Icons.inventory_2).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ChestScreen), findsOneWidget);
    expect(find.text('Wood chest'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Home says what each chest is waiting for', (tester) async {
    // The symptom was a chest that "will not open". It was sealed, and Home
    // showed the same anonymous icon whether it was sealed, running or
    // finished — so there was nothing on screen saying a timer had to be
    // started at all.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDataProvider.overrideWithValue(data),
          profileProvider.overrideWith(
            (ref) => _InMemoryProfile(
              data: data,
              initial: PlayerProfile(
                chests: [
                  const ChestSlot(typeId: 'wood'),
                  ChestSlot(
                    typeId: 'silver',
                    unlockStartedAt: DateTime.now().subtract(
                      const Duration(minutes: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        child: const SplatfrontApp(),
      ),
    );
    await tester.pump();

    expect(find.text('TAP TO START'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('Wood'), findsOneWidget);
    expect(find.text('Silver'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a sealed chest offers START and nothing else', (tester) async {
    final controller = await pump(
      tester,
      const PlayerProfile(chests: [ChestSlot(typeId: 'wood')]),
    );

    expect(find.text('Wood chest'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('OPEN'), findsNothing);

    await tester.tap(find.text('START'));
    await tester.pump();

    expect(controller.state.chests.single.isUnlocking, isTrue);
    expect(find.text('START'), findsNothing, reason: 'it is running now');
    await unmount(tester);
  });

  testWidgets('the reward screen reads properly', (tester) async {
    await pump(
      tester,
      PlayerProfile(
        chests: [
          ChestSlot(
            typeId: 'wood',
            unlockStartedAt: DateTime.now().subtract(
              const Duration(minutes: 5),
            ),
          ),
        ],
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));

    // The route is built by a PageRouteBuilder, which puts no Material over
    // its page. Without one every Text falls back to Flutter's "you forgot
    // the Material" style and draws itself with a yellow underline, which is
    // what every label on this screen was wearing.
    expect(
      find.ancestor(
        of: find.text('Tap to close'),
        matching: find.byType(Material),
      ),
      findsWidgets,
      reason: 'no Material above the text means underlined labels',
    );

    // A reward tile draws a character above its name. CustomPaint does not
    // clip, so the art was free to paint past the bottom of its own box and
    // land on the name underneath it.
    for (final view in tester.widgetList<UnitArtView>(
      find.byType(UnitArtView),
    )) {
      expect(view.size, greaterThan(0));
    }
    if (find.byType(UnitArtView).evaluate().isNotEmpty) {
      expect(
        find.descendant(
          of: find.byType(UnitArtView).first,
          matching: find.byType(ClipRect),
        ),
        findsOneWidget,
        reason: 'unclipped art paints over whatever the tile puts below it',
      );
    }

    expect(tester.takeException(), isNull, reason: 'nothing overflowed');

    await tester.tap(find.text('Tap to close'));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('a chest whose timer has run out shows OPEN and opens', (
    tester,
  ) async {
    // Started five minutes ago; Wood takes three.
    final controller = await pump(
      tester,
      PlayerProfile(
        chests: [
          ChestSlot(
            typeId: 'wood',
            unlockStartedAt: DateTime.now().subtract(
              const Duration(minutes: 5),
            ),
          ),
        ],
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);

    await tester.tap(find.text('OPEN'));
    await tester.pump();

    expect(controller.state.chests, isEmpty, reason: 'the slot is free again');
    expect(controller.state.coins, greaterThan(0), reason: 'it paid out');
    expect(
      controller.state.cardCopies.values.fold<int>(0, (a, b) => a + b),
      greaterThan(0),
      reason: 'and gave card copies',
    );

    // The opening plays as a full-screen animation rather than a dialog: the
    // chest shakes, bursts, and deals the rewards out. Pump past the end of
    // it and the contents should be on screen.
    await tester.pump(const Duration(milliseconds: 2500));

    expect(find.text('Wood chest'), findsOneWidget);
    expect(find.text('Tap to close'), findsOneWidget);
    // Matched on the big counter specifically: the app bar's coin chip shows
    // the same number the moment the reward lands, so a plain text match
    // finds two and proves nothing about the animation.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.fontSize == 30 &&
            w.data == '${controller.state.coins}',
      ),
      findsOneWidget,
      reason: 'the coin counter finishes on the real number',
    );

    // Tapping once it has finished closes it and leaves the slot empty.
    await tester.tap(find.text('Tap to close'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to close'), findsNothing);
    expect(find.text('EMPTY'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('the rewards end up centred, not pushed down the screen', (
    tester,
  ) async {
    // The chest sat in a fixed 190-tall box at the top of a centred column.
    // Once it burst and faded, the box stayed — so the column was still
    // perfectly centred while everything you were actually looking at sat
    // 190 pixels below the middle of the screen.
    await pump(
      tester,
      PlayerProfile(
        chests: [
          ChestSlot(
            typeId: 'wood',
            unlockStartedAt: DateTime.now().subtract(
              const Duration(minutes: 5),
            ),
          ),
        ],
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));

    final screen = tester.getRect(find.byType(MaterialApp));
    // Top of the reward block to the bottom of the hint under it.
    final top = tester.getRect(find.text('Wood chest')).top;
    final bottom = tester.getRect(find.text('Tap to close')).bottom;
    final blockCentre = (top + bottom) / 2;

    expect(
      (blockCentre - screen.center.dy).abs(),
      lessThan(40),
      reason:
          'the rewards sit ${(blockCentre - screen.center.dy).round()}px '
          'off centre',
    );
  });

  testWidgets('the opening can be skipped with a tap', (tester) async {
    await pump(
      tester,
      PlayerProfile(
        chests: [
          ChestSlot(
            typeId: 'wood',
            unlockStartedAt: DateTime.now().subtract(
              const Duration(minutes: 5),
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pump();
    // Part-way through the wind-up, before the burst.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tap to close'), findsNothing);

    // A tap during the animation jumps to the end rather than closing it, so
    // an impatient thumb never skips the rewards themselves.
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Tap to close'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the second chest is blocked while the first is running', (
    tester,
  ) async {
    await pump(
      tester,
      PlayerProfile(
        chests: [
          ChestSlot(typeId: 'wood', unlockStartedAt: DateTime.now()),
          const ChestSlot(typeId: 'silver'),
        ],
      ),
    );

    // Exactly one START, and it is disabled: only one unlocks at a time.
    final start = find.widgetWithText(FilledButton, 'START');
    expect(start, findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    await unmount(tester);
  });

  testWidgets('a long chest is genuinely long, not stuck', (tester) async {
    // Gold takes three hours. Two minutes in it is still counting, and that
    // is the design rather than a jam — worth pinning, because "the chest
    // will not open" is what a three-hour timer looks like from outside.
    await pump(
      tester,
      PlayerProfile(
        chests: [
          ChestSlot(
            typeId: 'gold',
            unlockStartedAt: DateTime.now().subtract(
              const Duration(minutes: 2),
            ),
          ),
        ],
      ),
    );

    expect(find.text('OPEN'), findsNothing);
    expect(find.text('Ready'), findsNothing);
    expect(find.textContaining('h'), findsWidgets, reason: 'hours remain');
    await unmount(tester);
  });

  testWidgets('a chest that finishes while you watch grows an OPEN button', (
    tester,
  ) async {
    // The one that would really look like "the chest will not open": the
    // timer runs out while the screen is already in front of you. Nothing
    // else on this screen changes on its own, so if the ticker were missing
    // the tile would sit at 0:00 forever and never offer OPEN.
    //
    // Readiness is measured against the wall clock, which `tester.pump` does
    // not move, so this waits on real time via runAsync. Wood takes three
    // minutes; starting it two minutes and fifty-nine seconds ago leaves
    // about a second to go.
    await pump(
      tester,
      PlayerProfile(
        chests: [
          ChestSlot(
            typeId: 'wood',
            unlockStartedAt: DateTime.now().subtract(
              const Duration(seconds: 179),
            ),
          ),
        ],
      ),
    );

    expect(find.text('OPEN'), findsNothing, reason: 'not yet');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1400)),
    );
    // One pump past the ticker's next beat.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    await unmount(tester);
  });
}

/// Keeps the whole meta layer off Hive.
class _InMemoryProfile extends ProfileController {
  _InMemoryProfile({required super.data, required super.initial});

  @override
  void saveToDisk(PlayerProfile profile) {}
}
