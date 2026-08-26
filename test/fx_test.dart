import 'dart:io';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/audio.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/arena_layout.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/fx/splatter.dart';
import 'package:splatfront/game/splatfront_game.dart';

/// Screen shake, paint droplets and the audio mixer.
///
/// All three are decoration, so the bar they have to clear is that they never
/// break the thing they decorate: the camera goes back where it started, the
/// particle budget holds, and audio stays silent rather than throwing when
/// there is no device to play it on.
void main() {
  late CardRegistry cards;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cards = await CardRegistry.load();
  });

  setUp(() {
    Splatter.live = 0;
    Audio.resetForTest();
  });

  void gameTest(
    String description,
    Future<void> Function(SplatfrontGame game, WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      final game = SplatfrontGame(
        layout: ArenaLayout.fallback,
        cards: cards,
        playerTeam: Team.red,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      try {
        await body(game, tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  void tick(SplatfrontGame game, {double seconds = 1.0}) {
    const step = 1 / 60;
    for (var t = 0.0; t < seconds; t += step) {
      game.updateTree(step);
    }
  }

  // --- Screen shake ------------------------------------------------------

  gameTest('a shake moves the camera and puts it back', (game, tester) async {
    final rest = game.camera.viewfinder.position.clone();

    game.shake(amplitude: 0.4, seconds: 0.2);
    tick(game, seconds: 0.05);
    expect(game.screenShake.isShaking, isTrue);
    expect(
      game.camera.viewfinder.position,
      isNot(rest),
      reason: 'the camera actually moved',
    );

    tick(game, seconds: 0.4);
    expect(game.screenShake.isShaking, isFalse);
    expect(
      game.camera.viewfinder.position,
      rest,
      reason: 'and landed exactly back on centre, not near it',
    );
  });

  gameTest('overlapping shakes take the strongest, never the sum', (
    game,
    tester,
  ) async {
    final shake = game.screenShake;
    for (var i = 0; i < 40; i++) {
      shake.shake(amplitude: 0.5, seconds: 0.3);
    }
    // Forty impacts in one frame must not add up to a camera off the board.
    for (var i = 0; i < 12; i++) {
      game.updateTree(1 / 60);
      final offset = game.camera.viewfinder.position;
      expect(offset.x.abs(), lessThanOrEqualTo(shake.maxOffset));
      expect(offset.y.abs(), lessThanOrEqualTo(shake.maxOffset));
    }
  });

  gameTest('a shake past the ceiling is clamped to it', (game, tester) async {
    game.shake(amplitude: 99, seconds: 0.2);
    tick(game, seconds: 0.03);
    expect(
      game.camera.viewfinder.position.x.abs(),
      lessThanOrEqualTo(game.screenShake.maxOffset),
    );
  });

  // --- Splatter ----------------------------------------------------------

  test('a burst claims droplets and gives them back when it ends', () {
    final splatter = Splatter.maybe(
      at: Vector2(8, 12),
      team: Team.red,
      random: math.Random(1),
      count: 10,
    );
    expect(splatter, isNotNull);
    expect(Splatter.live, 10);

    splatter!.onRemove();
    expect(Splatter.live, 0);
  });

  test('droplets are returned once, however many times removal fires', () {
    final splatter = Splatter.maybe(
      at: Vector2(8, 12),
      team: Team.blue,
      random: math.Random(2),
      count: 8,
    )!;
    splatter.onRemove();
    splatter.onRemove();
    expect(Splatter.live, 0, reason: 'never below zero');
  });

  test('the particle budget from section 13 actually holds', () {
    final bursts = <Splatter>[];
    for (var i = 0; i < 200; i++) {
      final splatter = Splatter.maybe(
        at: Vector2(8, 12),
        team: Team.red,
        random: math.Random(i),
        count: 12,
      );
      if (splatter != null) bursts.add(splatter);
    }

    expect(Splatter.live, lessThanOrEqualTo(PerfBudget.maxLiveParticles));
    expect(bursts, isNotEmpty, reason: 'some bursts did get through');
    expect(
      Splatter.maybe(
        at: Vector2(8, 12),
        team: Team.red,
        random: math.Random(0),
        count: 12,
      ),
      isNull,
      reason: 'and the budget refuses once it is spent',
    );
  });

  gameTest('a spell throws droplets and kicks the camera', (
    game,
    tester,
  ) async {
    final before = Splatter.live;
    game.castSpell(cards['paint_bomb'], Team.red, Vector2(8, 12));
    game.updateTree(1 / 60);

    expect(Splatter.live, greaterThan(before));
    expect(game.screenShake.isShaking, isTrue);
  });

  gameTest('droplets go back to the budget when the arena is torn down', (
    game,
    tester,
  ) async {
    game.burst(Vector2(8, 12), Team.red, count: 20, duration: 5);
    game.updateTree(1 / 60);
    expect(Splatter.live, 20);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      Splatter.live,
      0,
      reason: 'a burst cut short mid-flight still frees its droplets',
    );
  });

  // --- Audio -------------------------------------------------------------

  test('audio is silent and safe before it is initialised', () {
    expect(Audio.isReady, isFalse);
    // The whole point: none of this throws on a machine with no audio.
    expect(() => Audio.play(Sfx.hit), returnsNormally);
    expect(() => Audio.playMusic(Track.match), returnsNormally);
    expect(() => Audio.setVolumes(music: 0.5, sfx: 0.5), returnsNormally);
    expect(Audio.currentTrack, isNull);
  });

  test('every sound and track names a file that exists', () {
    // The clips are generated by `tool/generate_audio.dart`. A renamed enum
    // entry with no matching file is silence at runtime and nothing else, so
    // this is the only thing that would catch it.
    for (final sfx in Sfx.values) {
      expect(
        File('assets/audio/${sfx.file}').existsSync(),
        isTrue,
        reason: '${sfx.name} points at a missing file',
      );
    }
    for (final track in Track.values) {
      expect(
        File('assets/audio/${track.file}').existsSync(),
        isTrue,
        reason: '${track.name} points at a missing file',
      );
    }
    // The splat variants are picked by filename rather than by enum.
    for (final name in ['splat_1.wav', 'splat_2.wav', 'splat_3.wav']) {
      expect(File('assets/audio/$name').existsSync(), isTrue);
    }
  });

  test('the audio folder is bundled, so the clips actually ship', () {
    expect(
      File('pubspec.yaml').readAsStringSync().contains('assets/audio/'),
      isTrue,
    );
  });
}
