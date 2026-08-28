import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// What a quest counts.
enum QuestType {
  winMatches,
  playMatches,
  playCards,
  playSpells,

  /// Best single-match coverage, as a whole percentage.
  paintShare,

  unknown;

  static QuestType parse(String? raw) => switch (raw) {
    'winMatches' => QuestType.winMatches,
    'playMatches' => QuestType.playMatches,
    'playCards' => QuestType.playCards,
    'playSpells' => QuestType.playSpells,
    'paintShare' => QuestType.paintShare,
    _ => QuestType.unknown,
  };

  /// Most quests accumulate; paint share is a personal best instead, because
  /// painting 40% twice is not painting 80%.
  bool get isBest => this == QuestType.paintShare;
}

class Quest {
  const Quest({
    required this.id,
    required this.type,
    required this.target,
    required this.coins,
    required this.text,
  });

  final String id;
  final QuestType type;
  final int target;
  final int coins;
  final String text;

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    id: json['id'] as String,
    type: QuestType.parse(json['type'] as String?),
    target: (json['target'] as num).toInt(),
    coins: (json['coins'] as num).toInt(),
    text: json['text'] as String,
  );
}

/// What one finished match contributes to quest progress.
class MatchTally {
  const MatchTally({
    required this.won,
    required this.cardsPlayed,
    required this.spellsPlayed,
    required this.paintSharePercent,
  });

  final bool won;
  final int cardsPlayed;
  final int spellsPlayed;

  /// The player's final coverage, 0..100.
  final int paintSharePercent;

  /// How much this match adds to a quest of [type].
  int contributionTo(QuestType type) => switch (type) {
    QuestType.winMatches => won ? 1 : 0,
    QuestType.playMatches => 1,
    QuestType.playCards => cardsPlayed,
    QuestType.playSpells => spellsPlayed,
    QuestType.paintShare => paintSharePercent,
    QuestType.unknown => 0,
  };
}

/// The daily quest pool, from `assets/data/quests.json`.
class QuestConfig {
  const QuestConfig({required this.pool, required this.dailyCount});

  final List<Quest> pool;
  final int dailyCount;

  Quest? byId(String id) {
    for (final quest in pool) {
      if (quest.id == id) return quest;
    }
    return null;
  }

  /// The day key quests are drawn against. Rolling over at local midnight is
  /// what "daily" means to a player.
  static String dayKey(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  /// Three quests for [day], drawn deterministically from the day itself.
  ///
  /// Seeding off the date rather than storing a random pick means the same
  /// day always yields the same set, even if the save is lost.
  List<Quest> forDay(String day) {
    if (pool.isEmpty) return const [];
    final random = math.Random(day.hashCode);
    final remaining = List<Quest>.of(pool);
    final picked = <Quest>[];

    while (picked.length < dailyCount && remaining.isNotEmpty) {
      picked.add(remaining.removeAt(random.nextInt(remaining.length)));
    }
    return picked;
  }

  static QuestConfig fromJson(Map<String, dynamic> json) => QuestConfig(
    dailyCount: (json['dailyCount'] as num?)?.toInt() ?? 3,
    pool: [
      for (final q in json['pool'] as List<dynamic>)
        Quest.fromJson(q as Map<String, dynamic>),
    ],
  );

  static Future<QuestConfig> load() async {
    final raw = await rootBundle.loadString('assets/data/quests.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
