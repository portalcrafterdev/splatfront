import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import '../../meta/achievements.dart';

/// Play Games on Android, Game Center on iOS.
///
/// Deliberately static and deliberately forgiving, the same shape as `Audio`
/// and `Ads`. Three rules, and they are the same three:
///
/// **Inert until started.** Nothing touches a platform channel until [start]
/// runs from `main`, so the widget suite never signs anything in and never
/// waits on a network.
///
/// **Nothing here throws.** No Play Services on the device, a build whose
/// certificate is not registered, an emulator with no account, a player who
/// cancels the sheet — every one of those has to end in "not signed in" and
/// nothing else. Section 16 requires the game to be fully playable offline,
/// and this is a sign-in for a single-player game: it is decoration on the
/// progression, never a gate in front of it.
///
/// **Achievements go through [unlockAll], and only ever as a record.** The
/// set and its unlock conditions live in ; an
/// entry with no platform id yet is skipped in silence, which is what lets
/// the whole set ship before the Play Console work is done.
abstract final class GameServices {
  static bool _started = false;
  static bool _signedIn = false;
  static String? _playerName;
  static bool _busy = false;

  /// True once [start] has run, whatever the sign-in result was.
  static bool get isStarted => _started;

  /// Whether there is a signed-in player right now.
  static bool get isSignedIn => _signedIn;

  /// The signed-in player's display name, if the platform gave one.
  static String? get playerName => _playerName;

  /// True while a sign-in is in flight, so the button can't be double-tapped
  /// into two concurrent platform calls.
  static bool get isBusy => _busy;

  /// Notifies when the signed-in state changes, so a button can rebuild
  /// without every screen having to poll.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Asks whether there is already a signed-in player. Shows nothing.
  ///
  /// **This must never be `signIn()`.** It was, and it was wrong: Play Games
  /// Services v2 treats `signIn` as an explicit request and puts its full
  /// account sheet on screen — so launching the app threw a Google sign-in
  /// dialog over the splash before anybody had seen the game. That is exactly
  /// the thing this was supposed to avoid, and on a single-player game it is
  /// the sort of prompt that gets an app closed rather than played.
  ///
  /// `isSignedIn` is the silent question. If the player has connected before,
  /// the platform restores the session on its own and this reports it; if
  /// they have not, nothing appears and the button on Home is there for when
  /// they want it.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      // Bounded, and it has to be. The plugin implements `isSignedIn` as a
      // Completer waiting on its player stream with no timeout of its own, so
      // on a device with no Play Services — or in a test binding — it never
      // completes at all rather than failing. An unbounded await here would
      // leave this permanently half-started and the Home prompt frozen on
      // "Connecting…".
      _signedIn = await gs.GamesServices.isSignedIn.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
      if (_signedIn) await _readPlayer();
    } catch (error) {
      // The overwhelmingly common cause in development is a signing
      // certificate whose SHA-1 is not registered against the Play Games
      // project, which surfaces here as an opaque platform error. It is not
      // something the player can act on, so it stays in the log.
      debugPrint('Play Games not available: $error');
      _signedIn = false;
    }
    revision.value++;
  }

  /// Signs in from a button the player pressed.
  ///
  /// Returns whether there is a signed-in player afterwards. Never throws.
  static Future<bool> signIn() async {
    if (_busy) return _signedIn;
    _busy = true;
    revision.value++;
    try {
      final result = await gs.GamesServices.signIn();
      _signedIn = result != null && !result.toLowerCase().contains('error');
      if (_signedIn) await _readPlayer();
      return _signedIn;
    } catch (error) {
      debugPrint('Play Games sign-in failed: $error');
      _signedIn = false;
      return false;
    } finally {
      _busy = false;
      revision.value++;
    }
  }

  static Future<void> _readPlayer() async {
    try {
      _playerName = await gs.Player.getPlayerName();
    } catch (_) {
      // A session without a readable name is still a session.
      _playerName = null;
    }
  }

  // --- Achievements --------------------------------------------------------

  /// The last value posted for each key this launch.
  ///
  /// In-memory only, and that is fine: the platform is the real record, and
  /// re-posting a value it already has is a no-op on both stores. This only
  /// keeps the chatter down, so that a profile change does not fire fourteen
  /// platform calls when nothing about them moved.
  static final Map<String, int> _sent = <String, int>{};

  /// Reports where the player is against the whole set.
  ///
  /// Takes the progress rather than a list of earned achievements, because
  /// the incremental ones want reporting *before* they are finished — "47 of
  /// 100" is the entire reason to make something a progress bar.
  ///
  /// Silent about everything: signed out, no ids configured, no network — all
  /// of it ends in nothing happening. Achievements are a record of play, not
  /// part of it, and they must never interrupt or block.
  static Future<void> report(
    AchievementSet set,
    AchievementProgress progress,
  ) async {
    if (!_signedIn) return;
    for (final achievement in set.all) {
      if (!achievement.isConfigured) continue;
      final value = progress.valueFor(achievement.trigger);
      if (value == null || value <= 0) continue;

      // Never overshoot: the platform rejects steps above the configured
      // total, and there is nothing past "done" to report anyway.
      final capped = value > achievement.target ? achievement.target : value;
      if (_sent[achievement.key] == capped) continue;
      if (!achievement.incremental && capped < achievement.target) continue;

      final id = gs.Achievement(
        androidID: achievement.androidId,
        iOSID: achievement.iosId,
        steps: capped,
      );
      try {
        // The two kinds take different calls and the platform ignores the
        // wrong one, which is a silent failure rather than an error — so this
        // branch has to agree with what was typed into the Console.
        if (achievement.incremental) {
          await gs.Achievements.setSteps(achievement: id);
        } else {
          await gs.GamesServices.unlock(achievement: id);
        }
        _sent[achievement.key] = capped;
      } catch (error) {
        // Left unrecorded, so the next check tries again.
        debugPrint('Could not report ${achievement.key}: $error');
      }
    }
  }

  /// Opens the platform's own achievements screen.
  ///
  /// Does nothing while signed out, and nothing if no achievements have been
  /// defined in the Play Console — which is the case today. Kept because it
  /// is the natural next step and the seam belongs here rather than in a
  /// screen.
  static Future<void> showAchievements() async {
    if (!_signedIn) return;
    try {
      await gs.GamesServices.showAchievements();
    } catch (error) {
      debugPrint('Could not open achievements: $error');
    }
  }

  @visibleForTesting
  static void reset() {
    _started = false;
    _signedIn = false;
    _playerName = null;
    _busy = false;
    _sent.clear();
  }

  /// Installs a signed-in state directly, for tests of the UI around it.
  @visibleForTesting
  static void debugSignedIn({required bool signedIn, String? name}) {
    _started = true;
    _signedIn = signedIn;
    _playerName = name;
    revision.value++;
  }
}
