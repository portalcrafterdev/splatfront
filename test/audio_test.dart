import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/audio.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/ui/screens/battle_screen.dart';

/// The music has to stop when the player leaves the game.
///
/// It did not, for a long time: `flame_audio`'s Bgm can pause itself on a
/// lifecycle change, but only after its own `initialize()` has registered an
/// observer, and nothing ever called that — so no one was listening and the
/// menu loop played on over whatever the player switched to.
///
/// These drive the real [WidgetsBinding], not [Audio.handleLifecycleState]
/// directly, because "the observer is actually registered" is the half that
/// was broken.
void main() {
  late TestWidgetsFlutterBinding binding;

  setUp(() {
    binding = TestWidgetsFlutterBinding.ensureInitialized();
    Audio.resetForTest();
    Audio.watchLifecycle();
  });

  tearDown(() {
    // Puts the binding back in the foreground for whatever runs next, then
    // drops the observer.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Audio.resetForTest();
  });

  test('the game starts in the foreground', () {
    expect(Audio.isSuspended, isFalse);
  });

  test('booting the game is what starts it listening', () {
    // The bug in full: every other test here registers the observer by hand,
    // so they would all have passed while the shipped app registered nothing.
    // This is the one that fails if init stops wiring it up.
    Audio.resetForTest(); // No observer.
    Audio.init(); // Deliberately not awaited: registration is synchronous,
    // and the asset load behind it needs a plugin no test has.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(Audio.isSuspended, isTrue);
  });

  test('leaving the app suspends the sound', () {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(Audio.isSuspended, isTrue);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(Audio.isSuspended, isTrue, reason: 'still gone, still silent');
  });

  test('coming back lifts the suspension', () {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(Audio.isSuspended, isTrue);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(Audio.isSuspended, isFalse);
  });

  test('only resumed counts as being in the foreground', () {
    // Every other state means the player is looking at something else: the
    // shade is down, a call is up, or the app is off screen entirely.
    for (final state in AppLifecycleState.values) {
      Audio.resetForTest();
      Audio.watchLifecycle();
      Audio.handleLifecycleState(state);
      expect(
        Audio.isSuspended,
        state != AppLifecycleState.resumed,
        reason: '$state',
      );
    }
  });

  test('repeating a state is not a second pause', () {
    Audio.handleLifecycleState(AppLifecycleState.paused);
    expect(Audio.isSuspended, isTrue);
    Audio.handleLifecycleState(AppLifecycleState.paused);
    expect(Audio.isSuspended, isTrue);
    Audio.handleLifecycleState(AppLifecycleState.resumed);
    expect(Audio.isSuspended, isFalse);
    Audio.handleLifecycleState(AppLifecycleState.resumed);
    expect(Audio.isSuspended, isFalse);
  });

  test('choosing a track while away does not make a sound', () async {
    Audio.handleLifecycleState(AppLifecycleState.paused);
    await Audio.playMusic(Track.match);
    // Audio is not initialised in tests, so nothing could play regardless;
    // what this pins is that the call is still safe and silent.
    expect(Audio.isReady, isFalse);
    expect(Audio.isSuspended, isTrue);
  });

  group('the whistle silences the match, not the interface', () {
    test('every sound is on one side of the split', () {
      // A new Sfx that is neither would keep playing over the result screen
      // or, worse, silence the victory sting. The switch in Sfx.isGameplay is
      // exhaustive, so this is really a guard on the classification being
      // thought about rather than defaulted.
      final gameplay = Sfx.values.where((s) => s.isGameplay).toList();
      final ui = Sfx.values.where((s) => !s.isGameplay).toList();
      expect(gameplay, isNotEmpty);
      expect(ui, isNotEmpty);
      expect(gameplay.length + ui.length, Sfx.values.length);
    });

    test('the fight is match sound and the outcome is not', () {
      // The arena keeps running after the clock stops: units already swinging
      // carry on, so these are what used to leak under the result screen.
      for (final sound in [Sfx.hit, Sfx.death, Sfx.splat, Sfx.deploy,
          Sfx.leadChange, Sfx.elixirFull]) {
        expect(sound.isGameplay, isTrue, reason: sound.name);
      }
      // And these have to survive the mute, or the whistle makes no sound.
      for (final sound in [Sfx.victory, Sfx.defeat, Sfx.chestOpen, Sfx.uiTap]) {
        expect(sound.isGameplay, isFalse, reason: sound.name);
      }
    });

    test('the mute is on by default', () {
      // The app opens on the home screen. Defaulting to off and switching on
      // at the whistle closed exactly one path and left every other one open:
      // a match left by the back button never reaches a whistle at all.
      expect(
        Audio.gameplayMuted,
        isTrue,
        reason: 'anywhere that is not an arena is silent',
      );
      // Playing anything while muted must stay safe, not just silent.
      expect(() => Audio.play(Sfx.hit), returnsNormally);
      expect(() => Audio.play(Sfx.victory), returnsNormally);

      Audio.gameplayMuted = false;
      Audio.resetForTest();
      expect(Audio.gameplayMuted, isTrue, reason: 'and it resets to silent');
    });

    testWidgets('the arena unmutes on the way in and mutes on the way out', (
      tester,
    ) async {
      // No trophy rules, so this screen has no clock and no whistle. That is
      // the case the whistle-only mute missed entirely: the units are still
      // down there swinging when the screen goes.
      final cards = await CardRegistry.load();
      final layout = (await ArenaLayout.loadAll()).first;
      final deck = (await Deck.loadStarterDecks()).first;

      await tester.pumpWidget(
        MaterialApp(
          home: BattleScreen(layout: layout, cards: cards, deck: deck),
        ),
      );
      await tester.pump();
      expect(
        Audio.gameplayMuted,
        isFalse,
        reason: 'inside the arena the fight is audible',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        Audio.gameplayMuted,
        isTrue,
        reason: 'left the arena without a whistle, and it went quiet anyway',
      );
    });
  });

  group('repeated sounds are pooled', () {
    test('every sound a fight repeats has a pool', () {
      // Not tuning. Building a fresh AudioPlayer per shot posts several
      // platform-channel messages each time, and a busy fight fires dozens a
      // second: the Android main thread fell behind, the queue passed 150,000
      // pending DartMessenger callbacks, input stopped being serviced and the
      // app was killed for not responding. Any combat sound that is not
      // pooled puts that back.
      const repeated = [Sfx.hit, Sfx.death, Sfx.deploy, Sfx.splat];
      for (final sound in repeated) {
        expect(
          Audio.isPooled(sound),
          isTrue,
          reason: '${sound.name} repeats in a fight and needs a pool',
        );
      }
    });

    test('every pooled file is a real clip the cache loads', () {
      // A pool for a file that is not in the asset list would throw at boot,
      // inside the try that turns audio off entirely.
      for (final file in Audio.pooledFiles) {
        expect(
          Sfx.values.any((s) => s.file == file) ||
              Audio.splatVariants.contains(file),
          isTrue,
          reason: '$file is pooled but is not a sound in the set',
        );
      }
    });
  });

  test('dropping the observer stops the callbacks', () {
    Audio.resetForTest(); // Removes the observer.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(
      Audio.isSuspended,
      isFalse,
      reason: 'no observer, so nothing should have been told',
    );
  });
}
