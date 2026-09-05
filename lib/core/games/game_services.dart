import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

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
/// **Signing in buys nothing yet, and that is deliberate.** There are no
/// achievements and no leaderboards defined in the Play Console, so the only
/// thing this currently does is establish the session and hand back a player
/// name. Submitting scores is a small addition on top once boards exist; it
/// is not something the code can invent on its own.
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

  /// Attempts the silent sign-in the platforms both offer at launch.
  ///
  /// Silent on purpose: Play Games shows its own welcome banner if the player
  /// has signed in before, and throwing an account chooser at somebody who
  /// just opened a single-player game is the sort of thing that gets an app
  /// closed. The explicit [signIn] is behind a button they choose to press.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      // On Android this resolves against the already-authenticated Play
      // Games session and does nothing visible if there is not one.
      final result = await gs.GamesServices.signIn();
      _signedIn = result != null && !result.toLowerCase().contains('error');
      if (_signedIn) await _readPlayer();
    } catch (error) {
      // The overwhelmingly common cause in development is a signing
      // certificate whose SHA-1 is not registered against the Play Games
      // project, which surfaces here as an opaque platform error. It is not
      // something the player can act on, so it stays in the log.
      debugPrint('Play Games silent sign-in unavailable: $error');
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
