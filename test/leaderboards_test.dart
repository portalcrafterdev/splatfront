import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/meta/achievements.dart';
import 'package:splatfront/meta/leaderboards.dart';

/// The leaderboards, and the two things about them that fail silently.
///
/// A leaderboard is not like a screen: there is no way to look at it and see
/// that it is wrong. A bad id submits into nothing, and a `source` naming a
/// number that does not exist submits nothing at all. Both look exactly like
/// "no scores yet", which is also what a brand new board looks like.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LeaderboardSet boards;

  setUpAll(() async {
    boards = await LeaderboardSet.load();
  });

  test('the file parses and holds both boards', () {
    expect(boards.all, hasLength(2));
    expect(boards.byKey('levels_cleared'), isNotNull);
    expect(boards.byKey('total_stars'), isNotNull);
  });

  test('every score comes from a number the progress already knows', () {
    // The rule that keeps the leaderboards honest: they rank the same figures
    // the achievements are measured against rather than counting their own,
    // so the two can never tell a player different things about the same run.
    const progress = AchievementProgress();
    for (final board in boards.all) {
      expect(
        progress.valueFor(board.source),
        isNotNull,
        reason: '${board.key} submits "${board.source}", which is not a '
            'number AchievementProgress knows',
      );
    }
  });

  test('both boards submit on Android, and neither does on iOS yet', () {
    // A board with no id for the running platform must sit inert: submitting
    // to an empty id is a platform call that can only fail. Both Play Games
    // ids are in now; Game Center does not exist yet, and the iOS half has to
    // stay silent rather than half-work.
    for (final board in boards.all) {
      expect(
        board.androidId,
        startsWith('Cgk'),
        reason: '${board.key} has no Play Games id',
      );
      expect(board.iosId, isEmpty, reason: 'Game Center is not set up yet');
    }
    expect(boards.configured, hasLength(2));
  });

  test('a board with no id for this platform is skipped', () {
    // The property itself, held on a constructed board rather than on the
    // shipped file — so it survives every id being filled in, which is
    // exactly when it stops being covered by the set above.
    const unconfigured = Leaderboard(
      key: 'x',
      name: 'X',
      androidId: '',
      iosId: '',
      source: 'levelsCleared',
    );
    expect(unconfigured.isConfigured, isFalse);
  });

  test('the ids match the Play Console file they were copied from', () {
    // Same check as the achievements have, and for the same reason: Dart
    // cannot read an Android string resource, so `androidId` is a hand-copied
    // duplicate of games-ids.xml and a wrong one fails without a sound.
    final xml = File(
      'android/app/src/main/res/values/games-ids.xml',
    ).readAsStringSync();
    final fromConsole = <String, String>{
      for (final m in RegExp(
        r'<string name="leaderboard_([a-z_]+)"[^>]*>([^<]+)</string>',
      ).allMatches(xml))
        m.group(1)!: m.group(2)!,
    };

    for (final board in boards.all) {
      if (!board.isConfigured) continue;
      expect(
        board.androidId,
        fromConsole[board.key],
        reason: '${board.key} disagrees with games-ids.xml',
      );
    }
    // And nothing in the Console file is missing from here, which is the
    // direction that would otherwise go unnoticed: a board created and never
    // wired submits nothing and looks like a board nobody has played.
    for (final key in fromConsole.keys) {
      expect(
        boards.byKey(key),
        isNotNull,
        reason: 'games-ids.xml has $key but leaderboards.json does not',
      );
    }
  });

  test('ids are unique across the set', () {
    final ids = boards.configured.map((b) => b.androidId).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });
}
