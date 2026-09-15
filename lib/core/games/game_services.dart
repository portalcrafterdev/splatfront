import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import 'games_opt_out.dart';
import '../../meta/achievements.dart';
import '../../meta/leaderboards.dart';

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
/// **Achievements and scores go out through [report] and [submitScores], and
/// only ever as a record.** Both sets live in JSON — `achievements.json` and
/// `leaderboards.json` — and an entry with no platform id for the running
/// platform is skipped in silence. That is what let the whole set ship before
/// the Play Console work was done, and it is what keeps the iOS half quiet
/// until Game Center exists.
abstract final class GameServices {
  static bool _started = false;
  static bool _signedIn = false;
  static String? _playerName;
  static bool _busy = false;
  static bool _optedOut = false;

  /// True when the player has disconnected on this device.
  ///
  /// Exposed so the UI can say "Disconnected" rather than "Sign in", which
  /// are different facts: one is a choice this player made and can undo, the
  /// other is a state they have never left.
  static bool get isOptedOut => _optedOut;

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

    // **Before the platform is asked anything.** This one line is what makes
    // [disconnect] mean something: both platforms restore the session
    // silently at the next cold start, so without checking the opt-out first
    // a disconnected player would be signed back in by the very next launch
    // and would be right to call the button broken.
    //
    // It also has to come before the `isSignedIn` call rather than after —
    // that call is what re-establishes the session on Android, so asking it
    // and then discarding the answer would reconnect the account anyway.
    if (await GamesOptOut.isSet()) {
      _optedOut = true;
      _signedIn = false;
      revision.value++;
      return;
    }

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
      // Reconnecting clears the opt-out, and it has to happen *before* the
      // platform call rather than after a success. Otherwise a player who
      // disconnected and then pressed Sign in would be signed in for this
      // session and disconnected again by the next launch — the opt-out
      // outliving the decision that undid it, with a sign-in button that
      // appears to work once and then forgets.
      if (_optedOut) {
        _optedOut = false;
        await GamesOptOut.set(value: false);
      }

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

  /// Disconnects this device from the account.
  ///
  /// **Not a sign-out, and the button must not say so.** Play Games Services
  /// v2 has no sign-out for a game to call and Game Center never had one, so
  /// nothing here reaches the platform: the session on the device is
  /// untouched and the player is still signed in to Play Games. A button
  /// labelled "Sign out" would leave them hunting for a bug that is not
  /// there. "Disconnect" is what this actually does — it ends *this game's*
  /// relationship with the account.
  ///
  /// Everything derived from the account goes, not just the name. The one
  /// that is easy to miss is [_posted]: those are the last leaderboard values
  /// this launch sent, and leaving them behind would mean that reconnecting a
  /// *different* account silently skipped its first submissions, because the
  /// cache would claim the platform already had them.
  ///
  /// **The cloud snapshot is deliberately left alone** — this app does not
  /// keep one today, and if it ever does, disconnect is about this device's
  /// relationship to the account rather than the account's contents. Signing
  /// in again has to bring everything back; that is what makes the
  /// confirmation dialog honest.
  static Future<void> disconnect() async {
    _optedOut = true;
    _signedIn = false;
    _playerName = null;
    _busy = false;
    // Both caches are account-derived. See above for why _posted matters.
    _sent.clear();
    _posted.clear();
    revision.value++;
    // Last, and unawaited by nothing: the in-memory state above is already
    // correct for this session whatever the store does, and GamesOptOut
    // swallows its own failures.
    await GamesOptOut.set(value: true);
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

  // --- Leaderboards --------------------------------------------------------

  /// The last score posted for each board this launch.
  static final Map<String, int> _posted = <String, int>{};

  /// Submits the player's current standing to every configured board.
  ///
  /// Silent about everything, the same way [report] is: signed out, no ids,
  /// no network — all of it ends in nothing happening.
  ///
  /// Scores are absolute, not deltas, and the platform keeps the *best* one
  /// it has seen. That is what makes a single submission after any change
  /// sufficient, and it is why a player who cleared two hundred levels
  /// offline has all of it counted on their first submission after signing
  /// in. It also means a submission can never make a standing worse — a
  /// wiped save, or a profile that somehow reads low, cannot cost somebody
  /// their place.
  static Future<void> submitScores(
    LeaderboardSet boards,
    AchievementProgress progress,
  ) async {
    if (!_signedIn) return;
    for (final board in boards.all) {
      if (!board.isConfigured) continue;
      final value = progress.valueFor(board.source);
      // Zero is not submitted. Every board here starts at a lowest allowed
      // score of 1, so a fresh profile posting zero would be rejected by the
      // platform anyway — and posting it would put somebody who has never
      // finished a level on the board at all.
      if (value == null || value <= 0) continue;
      if (_posted[board.key] == value) continue;

      try {
        await gs.Leaderboards.submitScore(
          score: gs.Score(
            androidLeaderboardID: board.androidId,
            iOSLeaderboardID: board.iosId,
            value: value,
          ),
        );
        _posted[board.key] = value;
      } catch (error) {
        // Left unrecorded, so the next change tries again.
        debugPrint('Could not submit ${board.key}: $error');
      }
    }
  }

  /// Opens the platform's own leaderboards screen.
  ///
  /// With no [board] it shows the list of all of them, which is what the
  /// button in Settings wants: two boards behind one door rather than a row
  /// of buttons that has to grow every time one is added.
  static Future<void> showLeaderboards([Leaderboard? board]) async {
    if (!_signedIn) return;
    try {
      await gs.Leaderboards.showLeaderboards(
        androidLeaderboardID: board?.androidId ?? '',
        iOSLeaderboardID: board?.iosId ?? '',
      );
    } catch (error) {
      debugPrint('Could not open leaderboards: $error');
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
    _optedOut = false;
    _sent.clear();
    _posted.clear();
  }

  /// Installs a signed-in state directly, for tests of the UI around it.
  @visibleForTesting
  /// How many account-derived values are cached right now.
  ///
  /// Exposed only so a test can prove [disconnect] empties them. They are the
  /// half of a disconnect that is invisible from outside and easy to forget:
  /// left behind, they would make the *next* account's first submissions
  /// silently skip, because the cache would claim the platform already had
  /// those values.
  @visibleForTesting
  static int get debugCachedValues => _sent.length + _posted.length;

  /// Seeds the caches, so a test has something to watch be cleared.
  @visibleForTesting
  static void debugSeedCaches() {
    _sent['first_coat'] = 1;
    _posted['levels_cleared'] = 9;
  }

  static void debugSignedIn({required bool signedIn, String? name}) {
    _started = true;
    _signedIn = signedIn;
    _playerName = name;
    revision.value++;
  }
}
