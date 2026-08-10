import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/palette.dart';
import 'types/barricade.dart';
import 'types/beamer.dart';
import 'types/brusher.dart';
import 'types/bucket_bot.dart';
import 'types/dab.dart';
import 'types/kite.dart';
import 'types/nozzle.dart';
import 'types/pin.dart';
import 'types/roller.dart';
import 'types/scatter.dart';
import 'types/sniper_nib.dart';
import 'types/sprayer.dart';
import 'types/sprinkler.dart';
import 'types/swarmlets.dart';
import 'types/turret.dart';
import 'types/warden.dart';
import 'types/whirl.dart';
import 'unit.dart';
import 'unit_stats.dart';

/// Every troop defined in `assets/data/cards.json`, keyed by id.
///
/// Spell entries in the same file are skipped here; they get their own
/// registry when spells land in Phase 6.
class UnitsRegistry {
  const UnitsRegistry(this.tuning, this._byId);

  final UnitTuning tuning;
  final Map<String, UnitStats> _byId;

  Iterable<UnitStats> get all => _byId.values;

  /// Throws rather than returning null: a missing id is a typo in the JSON or
  /// in a deck, and should fail loudly at load time, not silently at runtime.
  UnitStats operator [](String id) {
    final stats = _byId[id];
    if (stats == null) {
      throw ArgumentError.value(id, 'id', 'No troop with this id in cards.json');
    }
    return stats;
  }

  bool contains(String id) => _byId.containsKey(id);

  /// [id] at [level], with the 1..9 HP and damage curve applied.
  UnitStats at(String id, int level) => this[id].atLevel(level, tuning);

  static UnitsRegistry fromJson(Map<String, dynamic> json) {
    final tuning = UnitTuning.fromJson(json);
    final byId = <String, UnitStats>{};
    for (final raw in json['cards'] as List<dynamic>) {
      final card = raw as Map<String, dynamic>;
      // Buildings are units too: same stats block, same components, they
      // just do not walk.
      final kind = card['kind'];
      if (kind != 'troop' && kind != 'building') continue;
      final stats = UnitStats.fromJson(card, tuning);
      byId[stats.id] = stats;
    }
    return UnitsRegistry(tuning, byId);
  }

  static Future<UnitsRegistry> load() async {
    final raw = await rootBundle.loadString('assets/data/cards.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// Builds the component for one troop id.
typedef UnitBuilder = Unit Function(UnitStats stats, Team team, Vector2 at);

/// Which troop ids have a component behind them.
///
/// All twelve troops from section 6. Most are pure data — the base [Unit]
/// loop already covers what makes them different, flying included — while
/// Nozzle and Warden carry real behaviour of their own. Asking for an id with
/// no builder throws, so a bad deck fails loudly rather than silently
/// fielding nothing.
const Map<String, UnitBuilder> _builders = <String, UnitBuilder>{
  Dab.id: Dab.spawn,
  Roller.id: Roller.spawn,
  Brusher.id: Brusher.spawn,
  Kite.id: Kite.spawn,
  Pin.id: Pin.spawn,
  Sprayer.id: Sprayer.spawn,
  SniperNib.id: SniperNib.spawn,
  Swarmlets.id: Swarmlets.spawn,
  BucketBot.id: BucketBot.spawn,
  Nozzle.id: Nozzle.spawn,
  Warden.id: Warden.spawn,
  Whirl.id: Whirl.spawn,

  // Buildings. Same map, because a building is a unit that does not walk.
  Turret.id: Turret.spawn,
  Sprinkler.id: Sprinkler.spawn,
  Barricade.id: Barricade.spawn,
  Beamer.id: Beamer.spawn,
  Scatter.id: Scatter.spawn,
};

extension UnitsRegistryFactory on UnitsRegistry {
  /// Troop ids that can actually be spawned today.
  List<String> get implemented =>
      _builders.keys.where(contains).toList(growable: false);

  bool isImplemented(String id) => _builders.containsKey(id);

  Unit create(
    String id, {
    required Team team,
    required Vector2 position,
    int level = 1,
  }) {
    final build = _builders[id];
    if (build == null) {
      throw UnimplementedError(
        'Troop "$id" has stats in cards.json but no component yet (Phase 6).',
      );
    }
    return build(at(id, level), team, position);
  }
}
