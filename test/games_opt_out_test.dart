import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/games/game_services.dart';
import 'package:splatfront/core/games/games_opt_out.dart';
import 'package:splatfront/meta/achievements.dart';
import 'package:splatfront/meta/leaderboards.dart';

/// Disconnect: a local opt-out that has to outlive the app.
///
/// **There is no sign-out to test, because neither platform has one.** Play
/// Games Services v2 dropped it and Game Center never had it: the account
/// belongs to the device, and only the Play Games app or iOS Settings can
/// release it. Disconnect is therefore a decision this game remembers about
/// itself, and every test below is about whether that memory holds.
///
/// The one that matters most is "the opt-out survives a restart". Both
/// platforms silently restore the session at the next cold start, so a
/// disconnect that is not checked *before* the platform is asked anything is
/// a button that appears to work and is undone by the next launch.
void main() {
  setUp(() {
    // Stands in for SharedPreferences, so none of this needs a platform
    // channel. Starts false: a fresh install has never opted out.
    GamesOptOut.debugValue = false;
    GameServices.reset();
  });

  tearDown(() {
    GamesOptOut.debugValue = null;
    GameServices.reset();
  });

  test('disconnecting forgets the player and sets the flag', () async {
    GameServices.debugSignedIn(signedIn: true, name: 'Tester');
    expect(GameServices.isSignedIn, isTrue);
    expect(GameServices.playerName, 'Tester');

    await GameServices.disconnect();

    expect(GameServices.isSignedIn, isFalse);
    expect(GameServices.playerName, isNull, reason: 'the name is account data');
    expect(GameServices.isOptedOut, isTrue);
    expect(await GamesOptOut.isSet(), isTrue, reason: 'and it is persisted');
  });

  test('the opt-out survives a restart', () async {
    GameServices.debugSignedIn(signedIn: true, name: 'Tester');
    await GameServices.disconnect();

    // A cold start: everything in memory is gone, only the stored flag is
    // left. This is the exact sequence that makes the button real — without
    // the check inside start(), the platform hands the session straight back.
    GameServices.reset();
    expect(GameServices.isOptedOut, isFalse, reason: 'memory really is clear');

    await GameServices.start();

    expect(
      GameServices.isSignedIn,
      isFalse,
      reason: 'start() signed a disconnected player back in',
    );
    expect(GameServices.isOptedOut, isTrue);
  });

  test(
    'a disconnected app reports nothing, and forgets what it sent',
    () async {
      GameServices.debugSignedIn(signedIn: true, name: 'Tester');
      GameServices.debugSeedCaches();
      expect(GameServices.debugCachedValues, greaterThan(0));

      await GameServices.disconnect();

      // Reporting is gated on being signed in, and disconnect is what takes
      // that away. Without it every match would keep posting to an account the
      // player asked to be let go of.
      expect(GameServices.isSignedIn, isFalse);

      // And the caches go with it. This is the half that is invisible from
      // outside: they hold the last values sent this launch, so leaving them
      // behind would make the *next* account's first submissions skip — the
      // cache would claim the platform already had them.
      expect(
        GameServices.debugCachedValues,
        0,
        reason: 'account-derived caches outlived the account',
      );

      // Still safe to call afterwards, and still silent.
      await expectLater(
        GameServices.report(AchievementSet.empty, const AchievementProgress()),
        completes,
      );
      await expectLater(
        GameServices.submitScores(
          LeaderboardSet.empty,
          const AchievementProgress(levelsCleared: 9, totalStars: 21),
        ),
        completes,
      );
    },
  );

  test('signing in again clears the opt-out', () async {
    GameServices.debugSignedIn(signedIn: true, name: 'Tester');
    await GameServices.disconnect();
    expect(await GamesOptOut.isSet(), isTrue);

    // The sign-in itself cannot succeed in a test — there is no platform on
    // the other end — and that is deliberately the harder case: the flag has
    // to be cleared by the *attempt*, not by a success. Otherwise a player
    // whose sign-in fails once stays permanently opted out with a dead
    // button, which is the failure this guards.
    await GameServices.signIn();

    expect(GameServices.isOptedOut, isFalse);
    expect(
      await GamesOptOut.isSet(),
      isFalse,
      reason: 'a restart would decline while this is still set',
    );
  });

  test('a failed preference write still disconnects this session', () async {
    // GamesOptOut swallows storage failures on purpose: the disconnect has
    // already happened in memory and holds until the app closes, and a
    // preference write must never throw out of a button tap. Simulated by
    // taking the store away entirely, which is what an unavailable platform
    // channel looks like.
    GameServices.debugSignedIn(signedIn: true, name: 'Tester');
    GamesOptOut.debugValue = null;

    await expectLater(GameServices.disconnect(), completes);
    expect(GameServices.isOptedOut, isTrue);
    expect(GameServices.isSignedIn, isFalse);
  });
}
