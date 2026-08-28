import '../../game/cards/card_registry.dart';

/// A chest sitting in one of the player's slots.
class ChestSlot {
  const ChestSlot({required this.typeId, this.unlockStartedAt});

  final String typeId;

  /// When the timer was started, or null while it is still sealed.
  final DateTime? unlockStartedAt;

  bool get isUnlocking => unlockStartedAt != null;

  ChestSlot startUnlocking(DateTime now) =>
      ChestSlot(typeId: typeId, unlockStartedAt: now);

  Map<String, dynamic> toJson() => {
    'typeId': typeId,
    if (unlockStartedAt != null)
      'startedAt': unlockStartedAt!.millisecondsSinceEpoch,
  };

  factory ChestSlot.fromJson(Map<String, dynamic> json) => ChestSlot(
    typeId: json['typeId'] as String,
    unlockStartedAt: json['startedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((json['startedAt'] as num).toInt()),
  );
}

/// Progress on one daily quest.
class QuestProgress {
  const QuestProgress({
    required this.questId,
    this.progress = 0,
    this.claimed = false,
  });

  final String questId;
  final int progress;
  final bool claimed;

  QuestProgress copyWith({int? progress, bool? claimed}) => QuestProgress(
    questId: questId,
    progress: progress ?? this.progress,
    claimed: claimed ?? this.claimed,
  );

  Map<String, dynamic> toJson() => {
    'questId': questId,
    'progress': progress,
    'claimed': claimed,
  };

  factory QuestProgress.fromJson(Map<String, dynamic> json) => QuestProgress(
    questId: json['questId'] as String,
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    claimed: json['claimed'] as bool? ?? false,
  );
}

/// Volume, haptics and language.
class Settings {
  const Settings({
    this.musicVolume = 0.7,
    this.sfxVolume = 0.9,
    this.haptics = true,
    this.language = 'en',
  });

  /// 0..1. The sliders show these as 0..100.
  final double musicVolume;
  final double sfxVolume;
  final bool haptics;

  /// Only English ships in v1; the setting persists so switching later does
  /// not lose the choice.
  final String language;

  Settings copyWith({
    double? musicVolume,
    double? sfxVolume,
    bool? haptics,
    String? language,
  }) => Settings(
    musicVolume: musicVolume ?? this.musicVolume,
    sfxVolume: sfxVolume ?? this.sfxVolume,
    haptics: haptics ?? this.haptics,
    language: language ?? this.language,
  );

  Map<String, dynamic> toJson() => {
    'musicVolume': musicVolume,
    'sfxVolume': sfxVolume,
    'haptics': haptics,
    'language': language,
  };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    musicVolume: (json['musicVolume'] as num?)?.toDouble() ?? 0.7,
    sfxVolume: (json['sfxVolume'] as num?)?.toDouble() ?? 0.9,
    haptics: json['haptics'] as bool? ?? true,
    language: json['language'] as String? ?? 'en',
  );
}

/// Everything about one player that survives a restart.
class PlayerProfile {
  const PlayerProfile({
    this.trophies = 0,
    this.coins = 0,
    this.cardLevels = const {},
    this.cardCopies = const {},
    this.deck = const [],
    this.chests = const [],
    this.quests = const [],
    this.questDay,
    this.settings = const Settings(),
  });

  final int trophies;
  final int coins;

  /// Level per card id. Absent means level 1.
  final Map<String, int> cardLevels;

  /// Spare duplicates per card id, spent on upgrades.
  final Map<String, int> cardCopies;

  /// The chosen eight. Empty falls back to the starter deck.
  final List<String> deck;

  final List<ChestSlot> chests;

  /// Today's three quests, and which day they were drawn for.
  final List<QuestProgress> quests;
  final String? questDay;

  final Settings settings;

  /// Highest trophies ever reached is not tracked separately in v1; arenas
  /// unlock off the current count.
  int levelOf(String cardId) => cardLevels[cardId] ?? 1;
  int copiesOf(String cardId) => cardCopies[cardId] ?? 0;

  /// The card levels in the shape the game layer wants.
  CardLevels get levels => CardLevels(cardLevels);

  PlayerProfile copyWith({
    int? trophies,
    int? coins,
    Map<String, int>? cardLevels,
    Map<String, int>? cardCopies,
    List<String>? deck,
    List<ChestSlot>? chests,
    List<QuestProgress>? quests,
    String? questDay,
    Settings? settings,
  }) => PlayerProfile(
    trophies: trophies ?? this.trophies,
    coins: coins ?? this.coins,
    cardLevels: cardLevels ?? this.cardLevels,
    cardCopies: cardCopies ?? this.cardCopies,
    deck: deck ?? this.deck,
    chests: chests ?? this.chests,
    quests: quests ?? this.quests,
    questDay: questDay ?? this.questDay,
    settings: settings ?? this.settings,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'trophies': trophies,
    'coins': coins,
    'cardLevels': cardLevels,
    'cardCopies': cardCopies,
    'deck': deck,
    'chests': [for (final c in chests) c.toJson()],
    'quests': [for (final q in quests) q.toJson()],
    'questDay': questDay,
    'settings': settings.toJson(),
  };

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
    trophies: (json['trophies'] as num?)?.toInt() ?? 0,
    coins: (json['coins'] as num?)?.toInt() ?? 0,
    cardLevels: _intMap(json['cardLevels']),
    cardCopies: _intMap(json['cardCopies']),
    deck: List<String>.from(json['deck'] as List? ?? const []),
    chests: [
      for (final c in json['chests'] as List? ?? const [])
        ChestSlot.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    quests: [
      for (final q in json['quests'] as List? ?? const [])
        QuestProgress.fromJson(Map<String, dynamic>.from(q as Map)),
    ],
    questDay: json['questDay'] as String?,
    settings: Settings.fromJson(
      Map<String, dynamic>.from(json['settings'] as Map? ?? const {}),
    ),
  );

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key as String: (entry.value as num).toInt(),
    };
  }
}
