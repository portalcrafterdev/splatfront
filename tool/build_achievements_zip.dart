// Builds the achievements bulk-import zip for the Play Console.
//
//   dart run tool/build_achievements_zip.dart
//
// Writes build/achievements/ and prints the command to zip it.
//
// **The zip is an upload, not a download.** Play Console has a bulk importer
// that takes a zip of CSVs and creates every achievement in one go, which
// beats typing fourteen of them into a web form and getting one point value
// wrong. Google generates the ids *afterwards*; nothing here can invent them.
//
// Format from developer.android.com/games/pgs/integrate-achievements#zip-file:
//
//   AchievementsMetadata.csv   required, NO header row
//     Name,Description,Incremental value,Steps Needed,Initial State,Points,List Order
//
//   AchievementsIconsMappings.csv   optional
//     Name,icon filename
//
//   AchievementsLocalizations.csv   optional
//     Name,Localized name,Localized description,Locale
//
// Rules the importer enforces, and the ones worth knowing because they fail
// the whole file rather than one row:
//
//   * No commas anywhere in a name or description. There is no quoting — a
//     comma is a column break, full stop. "1,000 levels" would have shifted
//     every column after it and imported garbage.
//   * Points must be a multiple of 5, between 5 and 200.
//   * Steps Needed only for incremental rows, and blank for the rest.
//   * Initial State cannot be changed after publishing, so Revealed vs
//     Hidden is a one-way decision.
//   * No subdirectories in the zip.
import 'dart:convert';
import 'dart:io';

void main() {
  final source = File('assets/data/achievements.json');
  if (!source.existsSync()) {
    stderr.writeln('assets/data/achievements.json not found. Run from the '
        'project root.');
    exitCode = 1;
    return;
  }

  final json = jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  final entries = (json['achievements'] as List).cast<Map<String, dynamic>>();

  final problems = <String>[];
  final rows = <String>[];
  final iconRows = <String>[];
  final missingIcons = <String>[];
  var order = 1;
  var total = 0;

  for (final a in entries) {
    final key = a['key'] as String;
    final name = a['name'] as String;
    final description = a['description'] as String;
    final points = (a['points'] as num).toInt();
    final incremental = a['incremental'] as bool;
    final target = (a['target'] as num).toInt();

    // Checked here rather than discovered as a rejected upload, because the
    // Console reports a failed import by row number and not by reason.
    if (name.contains(',')) problems.add('$name: comma in name');
    if (description.contains(',')) problems.add('$name: comma in description');
    if (points % 5 != 0 || points < 5 || points > 200) {
      problems.add('$name: $points is not a multiple of 5 in 5..200');
    }
    if (name.length > 100) problems.add('$name: name over 100 chars');
    if (description.length > 500) problems.add('$name: description too long');
    if (incremental && (target < 2 || target > 10000)) {
      problems.add('$name: $target steps is outside 2..10000');
    }
    total += points;

    // The icons are drawn by `generate_achievement_icons.dart` into the same
    // directory. Either they are all there and the mapping file goes in, or
    // none of them do — a partial mapping is the one state the importer has
    // no sensible reading of.
    if (File('build/achievements/$key.png').existsSync()) {
      iconRows.add('$name,$key.png');
    } else {
      missingIcons.add(key);
    }

    rows.add(
      [
        name,
        description,
        incremental ? 'True' : 'False',
        // Blank for a standard achievement. A number here on a non-
        // incremental row is rejected.
        incremental ? '$target' : '',
        // Revealed throughout: every one of these is a plain goal, and a
        // hidden achievement the player cannot see is no reason to keep
        // playing. This cannot be changed once published.
        'Revealed',
        '$points',
        '${order++}',
      ].join(','),
    );
  }

  if (problems.isNotEmpty) {
    stderr.writeln('The importer would reject this file:');
    for (final p in problems) {
      stderr.writeln('  - $p');
    }
    exitCode = 1;
    return;
  }

  final out = Directory('build/achievements')..createSync(recursive: true);
  // No header row, and a trailing newline. The importer counts rows.
  File('${out.path}/AchievementsMetadata.csv')
      .writeAsStringSync('${rows.join('\n')}\n');

  final mapping = File('${out.path}/AchievementsIconsMappings.csv');
  if (missingIcons.isEmpty && iconRows.isNotEmpty) {
    mapping.writeAsStringSync('${iconRows.join('\n')}\n');
  } else {
    // Deleted rather than left behind: a stale mapping naming a PNG that is
    // no longer in the zip fails the whole import.
    if (mapping.existsSync()) mapping.deleteSync();
  }

  stdout
    ..writeln('Wrote ${rows.length} achievements to ${out.path}')
    ..writeln('Total points: $total of the 1000 Play Games allows '
        '(${1000 - total} left for future levels)')
    ..writeln()
    ..writeln('Zip it — no subdirectories, the CSV must be at the root:')
    ..writeln('  powershell Compress-Archive -Path '
        'build/achievements/* -DestinationPath '
        'build/achievements.zip -Force')
    ..writeln()
    ..writeln('Then: Play Console -> Play Games Services -> Achievements')
    ..writeln('      -> import, and upload build/achievements.zip.');

  if (missingIcons.isEmpty && iconRows.isNotEmpty) {
    stdout.writeln('\nIcons: ${iconRows.length} included, with the mapping '
        'file. Re-draw them with\n  flutter test '
        'tool/generate_achievement_icons.dart');
  } else {
    stdout.writeln('\nNo icons in this zip — the Console will fall back to a '
        'placeholder for\neach one. Draw them first with\n  flutter test '
        'tool/generate_achievement_icons.dart');
    if (missingIcons.isNotEmpty && iconRows.isNotEmpty) {
      stdout.writeln('Missing: ${missingIcons.join(', ')}');
    }
  }
}
