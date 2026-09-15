import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device has opted out of Play Games / Game Center.
///
/// **This flag is the entire Disconnect button.** Neither platform lets an app
/// sign a player out: Play Games Services v2 dropped programmatic sign-out and
/// Game Center never had one, because the account belongs to the device rather
/// than to the game. Only the Play Games app or iOS Settings can release it.
///
/// So Disconnect is a *local opt-out*, and this is where it is remembered.
/// Without persistence the button would be theatre: both platforms silently
/// restore the session at the next cold start, so the player would disconnect,
/// reopen the app, find themselves signed in again, and reasonably conclude
/// the button does nothing. [GameServices.start] reads this **before** it asks
/// the platform anything, which is the line that makes the button mean
/// something.
///
/// Kept in `SharedPreferences` rather than in the Hive profile on purpose.
/// Resetting all progress must not silently reconnect an account the player
/// chose to disconnect, and disconnecting must not touch the save — two
/// decisions, two stores.
///
/// Nothing here throws. A preferences read that fails is treated as "not
/// opted out", which is the same state a fresh install is in; a write that
/// fails loses only the *memory* of the decision, and the disconnect still
/// holds for the rest of the session.
abstract final class GamesOptOut {
  /// Namespaced, because `SharedPreferences` is one flat store shared with
  /// every plugin in the app.
  @visibleForTesting
  static const String key = 'splatfront_games_opt_out';

  /// Overrides the store in tests, so none of this needs a platform channel.
  @visibleForTesting
  static bool? debugValue;

  static Future<bool> isSet() async {
    if (debugValue case final override?) return override;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (error) {
      // A device whose preferences cannot be read is a device that has never
      // opted out as far as we can tell. Failing open is right here: the cost
      // is an account reconnecting, which the player can undo; failing closed
      // would strand somebody signed out with no way back.
      debugPrint('Could not read the games opt-out: $error');
      return false;
    }
  }

  static Future<void> set({required bool value}) async {
    if (debugValue != null) {
      debugValue = value;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      // Swallowed deliberately. The disconnect has already happened in
      // memory and holds until the app is closed — only its persistence is
      // lost. A failed preference write must not throw out of a button tap.
      debugPrint('Could not store the games opt-out: $error');
    }
  }
}
