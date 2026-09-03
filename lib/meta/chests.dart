import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// One chest type, from `assets/data/chests.json`.
class ChestType {
  const ChestType({
    required this.id,
    required this.name,
    required this.duration,
    required this.dropWeight,
    required this.coinsMin,
    required this.coinsMax,
    required this.cardsMin,
    required this.cardsMax,
  });

  final String id;
  final String name;
  final Duration duration;
  final int dropWeight;
  final int coinsMin;
  final int coinsMax;
  final int cardsMin;
  final int cardsMax;

  factory ChestType.fromJson(Map<String, dynamic> json) {
    final coins = json['coins'] as Map<String, dynamic>;
    final cards = json['cards'] as Map<String, dynamic>;
    return ChestType(
      id: json['id'] as String,
      name: json['name'] as String,
      duration: Duration(seconds: (json['seconds'] as num).toInt()),
      dropWeight: (json['dropWeight'] as num).toInt(),
      coinsMin: (coins['min'] as num).toInt(),
      coinsMax: (coins['max'] as num).toInt(),
      cardsMin: (cards['min'] as num).toInt(),
      cardsMax: (cards['max'] as num).toInt(),
    );
  }
}

/// What opening a chest gave.
class ChestReward {
  const ChestReward({required this.coins, required this.cards});

  final int coins;

  /// Duplicates awarded, by card id.
  final Map<String, int> cards;

  int get totalCards => cards.values.fold(0, (sum, n) => sum + n);
}

/// Chest rules: which type a win awards, how long each takes, and what is
/// inside.
class ChestConfig {
  const ChestConfig({
    required this.types,
    required this.initialSlots,
    required this.unlockedSlots,
    required this.unlockAtTrophies,
  });

  final List<ChestType> types;
  final int initialSlots;
  final int unlockedSlots;
  final int unlockAtTrophies;

  ChestType byId(String id) =>
      types.firstWhere((t) => t.id == id, orElse: () => types.first);

  /// Two slots to start, four from Arena 2.
  int slotsFor(int trophies) =>
      trophies >= unlockAtTrophies ? unlockedSlots : initialSlots;

  /// Rolls the chest a win awards, by drop weight.
  ChestType roll(math.Random random) {
    final total = types.fold<int>(0, (sum, t) => sum + t.dropWeight);
    var pick = random.nextInt(math.max(1, total));
    for (final type in types) {
      pick -= type.dropWeight;
      if (pick < 0) return type;
    }
    return types.first;
  }

  /// Rolls the contents of [type], spreading the card copies over [cardPool].
  ChestReward open(ChestType type, List<String> cardPool, math.Random random) {
    final coins =
        type.coinsMin + random.nextInt(type.coinsMax - type.coinsMin + 1);
    final total =
        type.cardsMin + random.nextInt(type.cardsMax - type.cardsMin + 1);

    final cards = <String, int>{};
    if (cardPool.isEmpty) return ChestReward(coins: coins, cards: cards);

    for (var i = 0; i < total; i++) {
      final id = cardPool[random.nextInt(cardPool.length)];
      cards[id] = (cards[id] ?? 0) + 1;
    }
    return ChestReward(coins: coins, cards: cards);
  }

  static ChestConfig fromJson(Map<String, dynamic> json) {
    final slots = json['slots'] as Map<String, dynamic>;
    return ChestConfig(
      types: [
        for (final t in json['types'] as List<dynamic>)
          ChestType.fromJson(t as Map<String, dynamic>),
      ],
      initialSlots: (slots['initial'] as num).toInt(),
      unlockedSlots: (slots['unlocked'] as num).toInt(),
      unlockAtTrophies: (slots['unlockAtTrophies'] as num).toInt(),
    );
  }

  static Future<ChestConfig> load() async {
    final raw = await rootBundle.loadString('assets/data/chests.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
