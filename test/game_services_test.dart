import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/games/game_services.dart';
import 'package:splatfront/meta/achievements.dart';
import 'package:splatfront/meta/leaderboards.dart';

/// Play Games / Game Center sign-in.
///
/// The properties worth pinning are all about what it must *not* do. This is
/// a single-player game: the sign-in is an account somebody may want
/// connected, never a step in front of playing, and never something the test
/// suite reaches a network for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GameServices.reset);

  test('signed out until something signs in', () {
    // `start` is called from main() and nowhere else, so in a test nothing
    // here has run — no platform channel, no account sheet, no network.
    expect(GameServices.isStarted, isFalse);
    expect(GameServices.isSignedIn, isFalse);
    expect(GameServices.playerName, isNull);
    expect(GameServices.isBusy, isFalse);
  });

  test('a failed sign-in leaves the game playable and signed out', () async {
    // There is no Play Services in a test binding, so the platform call
    // throws. The contract is that it comes back false rather than escaping:
    // section 16 requires the game to be fully playable with no network, and
    // a sign-in is the last thing allowed to break that.
    final ok = await GameServices.signIn();
    expect(ok, isFalse);
    expect(GameServices.isSignedIn, isFalse);
    // And it is not left stuck in its busy state, which would disable the
    // button for the rest of the session.
    expect(GameServices.isBusy, isFalse);
  });

  test('start gives up rather than hanging', () async {
    // The plugin's `isSignedIn` is a Completer waiting on a stream with no
    // timeout of its own, so with no Play Services behind it — a test
    // binding, or a device without them — it never completes at all. This
    // test *is* the guard: without the bound in `start` it does not fail, it
    // times out after thirty seconds, and on a phone it would leave the Home
    // prompt stuck on "Connecting…" forever.
    await GameServices.start().timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('start never returned'),
    );
    expect(GameServices.isStarted, isTrue);
    expect(GameServices.isSignedIn, isFalse);
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('start never throws and only runs once', () async {
    // It asks whether a session already exists and shows nothing. It must
    // never call signIn: Play Games v2 treats that as an explicit request and
    // puts its account sheet on screen, which on launch means a Google dialog
    // over the splash before anyone has seen the game. That happened once.
    await GameServices.start();
    expect(GameServices.isStarted, isTrue);
    expect(GameServices.isSignedIn, isFalse, reason: 'no session in a test');
    // Idempotent: a second call is a no-op rather than a second attempt.
    await GameServices.start();
    expect(GameServices.isStarted, isTrue);
  });

  test('achievements do nothing while signed out', () async {
    // Not an error, not a crash, and not a sheet. Signed out there is nowhere
    // to report to, and the game has to carry on exactly as it does offline.
    await expectLater(GameServices.showAchievements(), completes);
    await expectLater(
      GameServices.report(
        await AchievementSet.load(),
        const AchievementProgress(levelsCleared: 40),
      ),
      completes,
    );
  });

  test('scores do nothing while signed out', () async {
    // Same rule for the leaderboards, and it matters more here: a submit is
    // the one call that would otherwise reach the network on a device with no
    // account at all.
    await expectLater(GameServices.showLeaderboards(), completes);
    await expectLater(
      GameServices.submitScores(
        await LeaderboardSet.load(),
        const AchievementProgress(levelsCleared: 40, totalStars: 96),
      ),
      completes,
    );
  });

  test('the signed-in state is observable without polling', () {
    // A button in Settings rebuilds off this rather than checking on a timer.
    final seen = <int>[];
    void listener() => seen.add(GameServices.revision.value);
    GameServices.revision.addListener(listener);
    addTearDown(() => GameServices.revision.removeListener(listener));

    GameServices.debugSignedIn(signedIn: true, name: 'Tester');
    expect(GameServices.isSignedIn, isTrue);
    expect(GameServices.playerName, 'Tester');
    expect(seen, isNotEmpty, reason: 'nothing was notified of the change');
  });
}
