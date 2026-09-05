import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/meta/achievements.dart';

/// The achievement set, and the budget it spends.
///
/// The point of these is not to check today's numbers. It is that Play Games
/// caps the total points across a game and **that cap does not grow when the
/// campaign does** — so the failure this guards against is not a wrong value
/// now, it is discovering in two years, with ten thousand levels shipped,
/// that there is no room left for the milestones they need.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AchievementSet set;

  setUpAll(() async {
    set = await AchievementSet.load();
  });

  /// Google documents 1000 points across all of a game's achievements.
  const platformCap = 1000;

  test('the file parses and holds the whole set', () {
    expect(set.all, hasLength(14));
    expect(set.totalPoints, 295);
  });

  test('every achievement is between 5 and 50 points', () {
    // The owner's range. Five is the floor Play Games allows at all; fifty is
    // the ceiling chosen here so that no single achievement can eat a
    // twentieth of the whole game's budget.
    for (final a in set.all) {
      expect(
        a.points,
        inInclusiveRange(5, 50),
        reason: '${a.key} is ${a.points}',
      );
      // Play Games only accepts multiples of five.
      expect(a.points % 5, 0, reason: '${a.key} is not a multiple of 5');
    }
  });

  test('there is room left for the campaign to grow', () {
    // The reason the range exists. Half the budget unspent is what lets a
    // ten-thousand-level campaign add its own milestones later without having
    // to delete one of these — and deleting a shipped achievement takes it
    // away from players who already earned it.
    expect(set.totalPoints, lessThan(platformCap));
    expect(
      platformCap - set.totalPoints,
      greaterThanOrEqualTo(500),
      reason: 'less than half the point budget is left for future levels',
    );
  });

  test('the cheap ones are cheap and the long haul is not', () {
    // A grading that inverts is worse than no grading: it teaches the player
    // that the number means nothing. Clearing every level in the game must
    // outrank winning the first one.
    final first = set.byKey('first_coat')!;
    final whole = set.byKey('the_whole_yard')!;
    expect(first.points, lessThan(whole.points));
    expect(whole.points, 50, reason: 'the longest haul is worth the maximum');
    expect(first.points, 5, reason: 'the first win is worth the minimum');
  });

  test('keys are unique and every one has a trigger the code knows', () {
    // A typo in `trigger` would leave an achievement permanently unearnable
    // and look exactly like one nobody has reached yet, which is the sort of
    // bug that survives a release.
    expect(set.all.map((a) => a.key).toSet(), hasLength(set.all.length));
    const progress = AchievementProgress();
    for (final a in set.all) {
      expect(
        progress.valueFor(a.trigger),
        isNotNull,
        reason: '${a.key} has an unknown trigger "${a.trigger}"',
      );
    }
  });

  test('nothing unlocks on a fresh profile', () {
    // Every target must be above zero, or an achievement fires the moment the
    // game is installed.
    const fresh = AchievementProgress();
    expect(fresh.earnedFrom(set), isEmpty);
  });

  test('progress unlocks exactly what it has reached', () {
    const progress = AchievementProgress(
      levelsCleared: 100,
      threeStarLevels: 4,
      chestsOpened: 3,
    );
    final earned = progress.earnedFrom(set).map((a) => a.key).toSet();

    expect(earned, contains('first_coat'));
    expect(earned, contains('primer'));
    expect(earned, contains('undercoat'));
    expect(earned, contains('topcoat'));
    expect(earned, contains('three_star_job'));
    expect(earned, contains('break_the_seal'));
    // Not yet.
    expect(earned, isNot(contains('gloss_finish')));
    expect(earned, isNot(contains('snagging_list')));
    expect(earned, isNot(contains('full_set')));
  });

  test('an achievement with no platform id is skipped, not broken', () {
    // The whole set ships before the Play Console work is done. Until an id
    // is pasted in, `unlockAll` must pass over it in silence rather than
    // calling the platform with an empty string.
    const unconfigured = Achievement(
      key: 'x',
      name: 'X',
      description: '',
      points: 5,
      incremental: false,
      androidId: '',
      iosId: '',
      trigger: 'levelsCleared',
      target: 1,
    );
    expect(unconfigured.isConfigured, isFalse);
    // And the shipped file is in exactly that state today, deliberately.
    expect(
      set.configured,
      isEmpty,
      reason: 'ids have been filled in — update this test with them',
    );
  });
}
