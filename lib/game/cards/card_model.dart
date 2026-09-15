import '../units/unit_stats.dart';

/// What a card puts on the board.
///
/// A building is a unit that does not walk: same stats, same targeting, same
/// deploy rule, but it stands where you drop it and expires on a clock. That
/// makes it data rather than a second code path — [CardKind.isUnit] is what
/// most of the game actually cares about.
enum CardKind {
  troop,
  building,
  spell;

  /// True for anything that puts a body on the field.
  bool get isUnit => this != CardKind.spell;

  static CardKind parse(String? raw) => switch (raw) {
    'troop' => CardKind.troop,
    'building' => CardKind.building,
    _ => CardKind.spell,
  };
}

/// What a spell does when it lands. Behaviour arrives in Phase 6; the
/// definition exists now so spells can sit in a deck and be costed.
enum SpellEffect {
  /// Damage plus a full recolour of the blast radius.
  damageAndPaint,

  /// Stun, no damage, no paint.
  stun,

  /// Wipes paint to neutral, denying both sides the ground.
  wipeToNeutral,

  /// Friendly speed and paint-rate buff.
  buff,

  /// Present in the JSON but not understood by this build.
  unknown;

  static SpellEffect parse(String? raw) => switch (raw) {
    'damageAndPaint' => SpellEffect.damageAndPaint,
    'stun' => SpellEffect.stun,
    'wipeToNeutral' => SpellEffect.wipeToNeutral,
    'buff' => SpellEffect.buff,
    _ => SpellEffect.unknown,
  };
}

/// A spell's numbers, straight out of `cards.json`.
class SpellStats {
  const SpellStats({
    required this.effect,
    required this.radius,
    this.damage = 0,
    this.duration = 0,
    this.speedMultiplier = 1,
    this.paintRateMultiplier = 1,
    this.friendlyOnly = false,
  });

  final SpellEffect effect;
  final double radius;
  final double damage;
  final double duration;
  final double speedMultiplier;
  final double paintRateMultiplier;
  final bool friendlyOnly;

  /// Does this spell repaint the ground it lands on?
  bool get paints =>
      effect == SpellEffect.damageAndPaint ||
      effect == SpellEffect.wipeToNeutral;

  factory SpellStats.fromJson(Map<String, dynamic> json) => SpellStats(
    effect: SpellEffect.parse(json['effect'] as String?),
    radius: (json['radius'] as num?)?.toDouble() ?? 0,
    damage: (json['damage'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    speedMultiplier: (json['speedMultiplier'] as num?)?.toDouble() ?? 1,
    paintRateMultiplier: (json['paintRateMultiplier'] as num?)?.toDouble() ?? 1,
    friendlyOnly: json['friendlyOnly'] as bool? ?? false,
  );
}

/// One card in a deck: what it costs, and what it puts on the field.
class CardModel {
  const CardModel({
    required this.id,
    required this.name,
    required this.cost,
    required this.kind,
    required this.level,
    this.unit,
    this.spell,
    this.note = '',
    this.blurb = '',
  });

  final String id;
  final String name;

  /// Elixir. Card level never changes this.
  final int cost;

  final CardKind kind;
  final int level;

  /// Set for troops.
  final UnitStats? unit;

  /// Set for spells.
  final SpellStats? spell;

  /// The designer's note: precise, and written for whoever is balancing
  /// the card. Not for the player — several of these name fields in
  /// cards.json by their code names.
  final String note;

  /// One line for the player, at roughly a seven-year-old's reading level.
  ///
  /// Separate from [note] rather than replacing it, because the two have
  /// different jobs and different readers. "aggroRange 0 is what 'walks
  /// straight' means" is exactly right in a balance note and useless on a
  /// card a child is looking at.
  final String blurb;

  bool get isTroop => kind == CardKind.troop;
  bool get isBuilding => kind == CardKind.building;
  bool get isSpell => kind == CardKind.spell;

  /// Anything that puts a body down: a troop or a building.
  bool get isUnit => kind.isUnit;

  /// Bodies may only land on your own colour; spells may target anywhere.
  bool get obeysDeployZone => isUnit;

  /// How many bodies this card puts down.
  int get bodyCount => unit?.count ?? 0;

  /// Radius used for the drop ghost: a troop's body, or a spell's blast.
  double get previewRadius => isSpell ? (spell?.radius ?? 1.5) : 0.9;

  @override
  String toString() => 'CardModel($id, cost $cost, level $level)';
}
