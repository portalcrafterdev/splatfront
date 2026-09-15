import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The way out to the player's own Play Games account.
///
/// **There is no sign-out in this game, and there cannot be one.** Play Games
/// Services v2 removed it: sign-in is automatic and belongs to the Play Games
/// app, not to the title, so a game can no longer disconnect an account or
/// switch one. `games_services` exposes `signIn` and `isSignedIn` and no
/// counterpart — that is the platform, not a gap in the package. Game Center
/// is the same on iOS, where only Settings can sign anybody out.
///
/// A "Log out" button here would have nothing real to call. Clearing our own
/// cached state would make the UI *say* signed out while Play Games still
/// considered the player signed in, and the next launch would silently put it
/// back — a button that lies about what it did is worse than no button.
///
/// So this opens the place where it can actually be done. The label says
/// "Manage account" rather than "Log out" for the same reason.
abstract final class PlayerAccount {
  static const MethodChannel _channel = MethodChannel('splatfront/accounts');

  /// Whether there is anywhere to send the player at all.
  ///
  /// Android only. iOS would need the Game Center equivalent, and this app
  /// has no Game Center capability enabled yet — offering the row there would
  /// be offering a button that cannot work.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the Play Games app.
  ///
  /// False when it is not installed or the launch is refused, which is a real
  /// state on a device without Google services. Callers should hide the
  /// affordance rather than show one that goes nowhere — and the check is
  /// done by *trying*, because `getLaunchIntentForPackage` is the only honest
  /// test of whether it will open.
  static Future<bool> openPlayGames() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openPlayGames') ?? false;
    } on PlatformException catch (e) {
      debugPrint('Could not open Play Games: $e');
      return false;
    } on MissingPluginException {
      // The channel is only registered by MainActivity, so every widget test
      // and every unit test lands here. Not an error: there is simply no
      // Android activity on the other end.
      return false;
    }
  }
}
