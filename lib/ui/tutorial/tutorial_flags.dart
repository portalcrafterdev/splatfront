import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which coach-mark sequences this device has already been through.
///
/// One bool per tutorial, so a new sequence added later starts unseen for
/// everybody rather than being swallowed by a single "tutorial done" flag
/// that existing players already carry.
///
/// Kept in `SharedPreferences` rather than in the Hive profile, for the same
/// reason GamesOptOut is: resetting progress is about the *save*, and a
/// player who has already been shown how to attack does not need showing
/// again because they wiped their campaign. Two decisions, two stores.
///
/// Nothing here throws. A read that fails reports "not seen yet", which
/// means the tutorial runs again — mildly irritating for a veteran, and the
/// right way round: the other failure mode leaves a first-time player staring
/// at a HUD nobody ever explained.
abstract final class TutorialFlags {
  /// Namespaced, because `SharedPreferences` is one flat store shared with
  /// every plugin in the app.
  @visibleForTesting
  static String keyFor(String tutorial) => 'splatfront_tutorial_$tutorial';

  /// Overrides the store in tests, so none of this needs a platform channel.
  /// Set it to an empty map for a fresh install; leave it null in production.
  @visibleForTesting
  static Map<String, bool>? debugStore;

  static Future<bool> isDone(String tutorial) async {
    final store = debugStore;
    if (store != null) return store[keyFor(tutorial)] ?? false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyFor(tutorial)) ?? false;
    } catch (error) {
      debugPrint('Could not read the tutorial flag for $tutorial: $error');
      return false;
    }
  }

  static Future<void> setDone(String tutorial, {required bool value}) async {
    final store = debugStore;
    if (store != null) {
      store[keyFor(tutorial)] = value;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyFor(tutorial), value);
    } catch (error) {
      // Swallowed deliberately. The sequence has already finished on screen;
      // only the memory of it is lost, and the cost of that is seeing it once
      // more. A failed preference write must not throw out of a button tap.
      debugPrint('Could not store the tutorial flag for $tutorial: $error');
    }
  }

  /// Forgets a sequence, so it runs again. This is what "Replay tutorial"
  /// does — it clears the flag rather than starting the overlay directly, so
  /// a player who backs out of the replay still gets offered it next launch.
  static Future<void> reset(String tutorial) =>
      setDone(tutorial, value: false);
}
