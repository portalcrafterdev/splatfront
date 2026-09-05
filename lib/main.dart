import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/ads/ads.dart';
import 'core/audio.dart';
import 'core/game_data.dart';
import 'core/games/game_services.dart';
import 'core/save/hive_boxes.dart';
import 'core/save/player_profile.dart';
import 'game/units/rive_units.dart';
import 'meta/profile_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only, on both phones and tablets.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Edge to edge, NOT full screen. `Flame.device.fullScreen()` puts the app
  // in immersive mode, which hides the status bar outright — no clock, no
  // battery, no signal, for as long as the game is open. That is a fair
  // trade for a game you look into for hours; it is a bad one for a phone
  // game played in ninety-second matches, and it is the kind of thing a
  // player notices and cannot fix.
  //
  // Edge to edge keeps the bars visible and lets the app draw behind them,
  // so nothing shrinks; SafeArea is what keeps content out from under them.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await HiveBoxes.init();
  final data = await GameData.load();

  // Whatever unit art has landed in `assets/rive/`. Awaited so the first
  // Roller of the first match is not the one that stutters while its artboard
  // decodes, and, like the audio below, it cannot throw: a card with no `.riv`
  // — or a device that cannot start the native runtime at all — keeps the
  // hand-drawn vector character it has always had.
  await RiveUnitLibrary.load();
  final saved = HiveBoxes.read();
  final profile = saved == null
      ? const PlayerProfile()
      : PlayerProfile.fromJson(saved);

  // Awaited so the first card played is not the one that stutters while its
  // clip decodes. It cannot throw: a device with no audio just stays silent.
  await Audio.init();
  Audio.setVolumes(
    music: profile.settings.musicVolume,
    sfx: profile.settings.sfxVolume,
  );

  // Ads are started here and *only* here, which is what keeps them out of the
  // widget suite: no test calls this, so `Ads.enabled` is false throughout and
  // no banner ever touches a platform channel. Like the audio and the Rive
  // art above, it cannot throw — a device with no network runs the whole game
  // with empty ad slots.
  await Ads.start();

  // Play Games / Game Center. Not awaited, and that is the point: it is a
  // network round trip that buys the player nothing they need, so it must
  // never sit between them and the home screen. It resolves in the
  // background and the Settings tile updates when it does.
  unawaited(GameServices.start());

  runApp(
    ProviderScope(
      overrides: [
        gameDataProvider.overrideWithValue(data),
        profileProvider.overrideWith(
          (ref) => ProfileController(data: data, initial: profile),
        ),
      ],
      child: const SplatfrontApp(),
    ),
  );
}
