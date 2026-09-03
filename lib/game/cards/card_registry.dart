import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../units/units_registry.dart';
import 'card_model.dart';

/// Every card in the game, troops and spells alike, from `cards.json`.
///
/// [UnitsRegistry] owns troop stats and the components behind them; this sits
/// on top and presents all sixteen as deck-able cards with a cost.
class CardRegistry {
  const CardRegistry(this.units, this._byId);

  final UnitsRegistry units;
  final Map<String, CardModel> _byId;

  Iterable<CardModel> get all => _byId.values;

  Iterable<CardModel> get troops => all.where((c) => c.isTroop);
  Iterable<CardModel> get buildings => all.where((c) => c.isBuilding);
  Iterable<CardModel> get spells => all.where((c) => c.isSpell);

  /// Cards that can actually be played: a troop with a component behind it,
  /// or a spell whose effect this build understands. A deck may only be built
  /// from these.
  ///
  /// The spell side checks the parsed effect rather than the implementation
  /// map, to avoid importing the game from here; `spell_test.dart` asserts
  /// that every known effect really does have an implementation, so the two
  /// cannot drift apart.
  Iterable<CardModel> get playable => all.where(
    (c) => c.isUnit
        ? units.isImplemented(c.id)
        : c.spell?.effect != null && c.spell!.effect != SpellEffect.unknown,
  );

  bool contains(String id) => _byId.containsKey(id);

  CardModel operator [](String id) {
    final card = _byId[id];
    if (card == null) {
      throw ArgumentError.value(id, 'id', 'No card with this id in cards.json');
    }
    return card;
  }

  /// [id] at [level], with the 1..9 HP and damage curve applied to troops.
  CardModel at(String id, int level) {
    final card = this[id];
    if (!card.isUnit) return card;
    return CardModel(
      id: card.id,
      name: card.name,
      cost: card.cost,
      kind: card.kind,
      level: level.clamp(1, units.tuning.maxLevel),
      unit: units.at(id, level),
      note: card.note,
    );
  }

  static CardRegistry fromJson(Map<String, dynamic> json) {
    final unitsRegistry = UnitsRegistry.fromJson(json);
    final byId = <String, CardModel>{};

    for (final raw in json['cards'] as List<dynamic>) {
      final entry = raw as Map<String, dynamic>;
      final id = entry['id'] as String;
      final kind = CardKind.parse(entry['kind'] as String?);
      final hasBody = kind.isUnit;

      byId[id] = CardModel(
        id: id,
        name: entry['name'] as String,
        cost: (entry['cost'] as num).toInt(),
        kind: kind,
        level: 1,
        unit: hasBody ? unitsRegistry[id] : null,
        spell: hasBody ? null : SpellStats.fromJson(entry),
        note: entry['note'] as String? ?? '',
      );
    }
    return CardRegistry(unitsRegistry, byId);
  }

  static Future<CardRegistry> load() async {
    final raw = await rootBundle.loadString('assets/data/cards.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// A deck: eight distinct cards, in the order they will first come up.
class Deck {
  Deck(this.cardIds) {
    if (cardIds.length != size) {
      throw ArgumentError('A deck must hold exactly $size cards');
    }
    if (cardIds.toSet().length != cardIds.length) {
      throw ArgumentError('A deck may not repeat a card');
    }
  }

  static const int size = 6;

  final List<String> cardIds;

  /// Fails loudly if the deck names a card that cannot be played yet, rather
  /// than discovering it mid-match.
  void validateAgainst(CardRegistry registry) {
    final playable = registry.playable.map((c) => c.id).toSet();
    for (final id in cardIds) {
      if (!registry.contains(id)) {
        throw ArgumentError('Deck names "$id", which is not in cards.json');
      }
      if (!playable.contains(id)) {
        throw ArgumentError('Deck names "$id", which has no component yet');
      }
    }
  }

  static Future<List<Deck>> loadStarterDecks() async {
    final raw = await rootBundle.loadString('assets/data/decks.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final deck in json['decks'] as List<dynamic>)
        Deck(
          List<String>.from((deck as Map<String, dynamic>)['cards'] as List),
        ),
    ];
  }
}

/// Level of each owned card. Real progression lands in Phase 7; until then
/// everything is level 1.
class CardLevels {
  const CardLevels([this._levels = const {}]) : _floor = 1;

  /// Every card at the same level.
  ///
  /// The campaign scales its opponent this way: one number, rather than a map
  /// that would have to be rebuilt every time the bot's deck changed and
  /// would silently leave a card at level 1 if it ever fell out of step.
  const CardLevels.uniform(int level) : _levels = const {}, _floor = level;

  final Map<String, int> _levels;

  /// What a card not named in [_levels] is played at.
  final int _floor;

  int of(String cardId) => _levels[cardId] ?? _floor;
}
