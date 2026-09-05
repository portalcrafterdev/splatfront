import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the display awake while a match is on screen.
///
/// A match is ninety seconds during which a player may not touch the glass at
/// all — they deploy a card and then watch it fight. Android and iOS both
/// count that as idle, so the screen dims and then sleeps mid-push, and the
/// player has to wake the phone to find out they lost the board. Nothing else
/// in the app has that shape: every menu is something you are touching.
///
/// Same three rules as `Audio`, `Ads` and `GameServices`, and the same static
/// shape:
///
/// **Inert until started.** Nothing touches a platform channel until [start]
/// runs from `main`, so the widget suite never holds a real wakelock — it
/// opens arenas by the dozen and would otherwise spend every one of them
/// talking to a plugin that is not registered.
///
/// **Nothing here throws.** A platform with no wakelock, a channel that is
/// not registered, a plugin that fails — every one of those has to end in a
/// screen that dims like any other app's, never in a crash. This is a comfort,
/// not a feature.
///
/// **Held for the arena only.** Never app-wide. A wakelock over the whole app
/// means a player who left the Collection open on a table has a phone burning
/// itself down, and that is the sort of thing that gets one-starred as
/// "drains battery" without anybody working out why.
abstract final class ScreenWake {
  /// Whether the lock is currently meant to be held.
  ///
  /// Tracked here rather than read back from the plugin: `enabled` is an
  /// async platform round trip, and this is toggled from `initState` and
  /// `dispose`, which cannot await. It also makes the state observable in a
  /// test without a fake platform channel.
  static bool _held = false;
  static bool _started = false;

  /// Whether a match currently has the screen held awake.
  ///
  /// This is the *intent*, and it is tracked whether or not [start] has run.
  /// That is what lets a test assert an arena asked for the lock without a
  /// platform behind it.
  static bool get isHeld => _held;

  /// Allows the platform call. Called once from `main`.
  static void start() => _started = true;

  /// Set true while an arena is on screen.
  ///
  /// Idempotent, so the whistle releasing it and the screen being disposed a
  /// moment later cost one platform call rather than two.
  static void request(bool held) {
    if (_held == held) return;
    _held = held;
    if (_started) _apply(held);
  }

  static Future<void> _apply(bool held) async {
    try {
      await WakelockPlus.toggle(enable: held);
    } catch (error) {
      // Left as it is. A screen that sleeps is the normal behaviour of every
      // other app on the device, so there is nothing to tell the player and
      // nothing for them to do about it.
      debugPrint('Could not ${held ? 'hold' : 'release'} the screen: $error');
    }
  }

  /// Drops the lock without a platform call, for tests.
  @visibleForTesting
  static void resetForTest() {
    _held = false;
    _started = false;
  }
}
