import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/games/game_services.dart';

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

  test('start never throws and only runs once', () async {
    await GameServices.start();
    expect(GameServices.isStarted, isTrue);
    // Idempotent: a second call is a no-op rather than a second sign-in
    // attempt and a second account sheet.
    await GameServices.start();
    expect(GameServices.isStarted, isTrue);
  });

  test('achievements do nothing while signed out', () async {
    // Not an error, not a crash, and not a sheet. There are no achievements
    // defined in the Play Console yet either, so this is the honest state.
    await expectLater(GameServices.showAchievements(), completes);
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
