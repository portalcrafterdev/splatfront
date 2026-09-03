/// What a unit may shoot at.
enum TargetMask {
  ground,
  air,
  airGround;

  static TargetMask parse(String? raw) => switch (raw) {
    'air' => TargetMask.air,
    'airGround' || 'air+ground' => TargetMask.airGround,
    _ => TargetMask.ground,
  };

  bool canHit({required bool flying}) => switch (this) {
    TargetMask.ground => !flying,
    TargetMask.air => flying,
    TargetMask.airGround => true,
  };
}

/// The shared tuning block at the top of `cards.json`. Speed words and the
/// word "melee" resolve against this, so a balance pass can retune every
/// medium-speed unit at once.
class UnitTuning {
  const UnitTuning({
    required this.speeds,
    required this.meleeRange,
    required this.deathSplashMultiplier,
    required this.deathSplashMin,
    required this.meleeAggro,
    required this.rangedAggro,
    required this.levelScaling,
    required this.maxLevel,
    this.advanceRange = 6.0,
  });

  final Map<String, double> speeds;
  final double meleeRange;

  /// A dying unit leaves a splash, which scores, so its size is balance data.
  final double deathSplashMultiplier;
  final double deathSplashMin;
  final double meleeAggro;
  final double rangedAggro;
  final double levelScaling;
  final int maxLevel;

  /// How far a unit will walk from where it was dropped, with nothing to
  /// fight.
  ///
  /// There is no base at the far edge and nothing to break on arrival: the
  /// ground is the objective, so a unit that marched to the end walked off
  /// the only thing worth holding. It advances this far, then holds its
  /// post — still fighting anything that comes into aggro range, still
  /// painting where it stands. Pushing further up the board is what the next
  /// card is for, which is what makes the deploy line move.
  final double advanceRange;

  factory UnitTuning.fromJson(Map<String, dynamic> json) {
    final aggro = json['aggroRange'] as Map<String, dynamic>? ?? const {};
    final splash = json['deathSplash'] as Map<String, dynamic>? ?? const {};
    return UnitTuning(
      advanceRange: (json['advanceRange'] as num?)?.toDouble() ?? 6.0,
      speeds: {
        for (final e
            in (json['speeds'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: (e.value as num).toDouble(),
      },
      meleeRange: (json['meleeRange'] as num?)?.toDouble() ?? 0.85,
      deathSplashMultiplier:
          (splash['paintMultiplier'] as num?)?.toDouble() ?? 1.5,
      deathSplashMin: (splash['minRadius'] as num?)?.toDouble() ?? 0.5,
      meleeAggro: (aggro['melee'] as num?)?.toDouble() ?? 3.0,
      rangedAggro: (aggro['ranged'] as num?)?.toDouble() ?? 6.0,
      levelScaling: (json['levelScaling'] as num?)?.toDouble() ?? 0.08,
      maxLevel: (json['maxLevel'] as num?)?.toInt() ?? 9,
    );
  }
}

/// One troop's stats, with every JSON word already resolved to a number.
class UnitStats {
  const UnitStats({
    required this.id,
    required this.name,
    required this.cost,
    required this.hp,
    required this.damage,
    required this.hitRate,
    required this.speed,
    required this.range,
    required this.paint,
    required this.targets,
    required this.count,
    required this.flying,
    required this.radius,
    required this.aggroRange,
    required this.melee,
    required this.level,
    this.splashRadius = 0,
    this.lifetime = 0,
    this.volley = 0,
    this.shellPaint = 0,
    this.auraRadius = 0,
    this.auraDamageReduction = 0,
    this.note = '',
  });

  final String id;
  final String name;
  final int cost;

  final double hp;
  final double damage;

  /// Attacks per second.
  final double hitRate;

  /// World units per second.
  final double speed;

  /// Attack reach in world units.
  final double range;

  /// Stamp radius. Zero means the unit does not paint the ground.
  final double paint;

  final TargetMask targets;

  /// Bodies spawned per card play.
  final int count;

  final bool flying;
  final double radius;

  /// How far the unit looks for something to fight.
  final double aggroRange;

  final bool melee;
  final int level;

  final double splashRadius;

  /// Seconds a building stands before it expires. Zero means forever, which
  /// is every troop: only buildings have a clock on them.
  final double lifetime;

  /// How many shells go out at once. Zero means it fires one, at a target.
  /// A volley fires this many evenly around the compass instead.
  final int volley;

  /// Stamp radius of the shot this unit lobs, as opposed to [paint], which is
  /// what it leaves under its own feet. A cannon has one and not the other.
  final double shellPaint;

  final double auraRadius;
  final double auraDamageReduction;
  final String note;

  bool get paints => paint > 0;

  /// True for anything that expires on its own.
  bool get isTemporary => lifetime > 0;

  /// True for a gun that fires all round itself rather than at one target.
  bool get firesVolley => volley > 0;
  bool get hasSplash => splashRadius > 0;
  bool get hasAura => auraRadius > 0 && auraDamageReduction > 0;

  /// Seconds between attacks.
  double get attackInterval => hitRate > 0 ? 1 / hitRate : double.infinity;

  factory UnitStats.fromJson(Map<String, dynamic> json, UnitTuning tuning) {
    final rawRange = json['range'];
    final melee = rawRange is! num;
    final range = rawRange is num ? rawRange.toDouble() : tuning.meleeRange;

    return UnitStats(
      id: json['id'] as String,
      name: json['name'] as String,
      cost: (json['cost'] as num).toInt(),
      hp: (json['hp'] as num).toDouble(),
      damage: (json['damage'] as num).toDouble(),
      hitRate: (json['hitRate'] as num).toDouble(),
      speed: tuning.speeds[json['speed'] as String? ?? 'medium'] ?? 1.6,
      range: range,
      paint: (json['paint'] as num?)?.toDouble() ?? 0,
      targets: TargetMask.parse(json['targets'] as String?),
      count: (json['count'] as num?)?.toInt() ?? 1,
      flying: json['flying'] as bool? ?? false,
      radius: (json['radius'] as num?)?.toDouble() ?? 0.4,
      aggroRange:
          (json['aggroRange'] as num?)?.toDouble() ??
          (melee ? tuning.meleeAggro : tuning.rangedAggro),
      melee: melee,
      level: 1,
      splashRadius: (json['splashRadius'] as num?)?.toDouble() ?? 0,
      lifetime: (json['lifetime'] as num?)?.toDouble() ?? 0,
      volley: (json['volley'] as num?)?.toInt() ?? 0,
      shellPaint: (json['shellPaint'] as num?)?.toDouble() ?? 0,
      auraRadius: (json['auraRadius'] as num?)?.toDouble() ?? 0,
      auraDamageReduction:
          (json['auraDamageReduction'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String? ?? '',
    );
  }

  /// Levels 1 to 9 add [UnitTuning.levelScaling] to HP and damage per level.
  /// Cost never changes, and neither does anything else.
  UnitStats atLevel(int level, UnitTuning tuning) {
    final clamped = level.clamp(1, tuning.maxLevel);
    final multiplier = 1 + tuning.levelScaling * (clamped - 1);
    return copyWith(
      hp: hp * multiplier,
      damage: damage * multiplier,
      level: clamped,
    );
  }

  UnitStats copyWith({double? hp, double? damage, int? level}) => UnitStats(
    id: id,
    name: name,
    cost: cost,
    hp: hp ?? this.hp,
    damage: damage ?? this.damage,
    hitRate: hitRate,
    speed: speed,
    range: range,
    paint: paint,
    targets: targets,
    count: count,
    flying: flying,
    radius: radius,
    aggroRange: aggroRange,
    melee: melee,
    level: level ?? this.level,
    splashRadius: splashRadius,
    lifetime: lifetime,
    volley: volley,
    shellPaint: shellPaint,
    auraRadius: auraRadius,
    auraDamageReduction: auraDamageReduction,
    note: note,
  );
}
