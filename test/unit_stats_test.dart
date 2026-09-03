import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/game/units/units_registry.dart';

void main() {
  late UnitsRegistry registry;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registry = await UnitsRegistry.load();
  });

  test('cards.json holds every body in the set', () {
    // Twelve troops and five buildings. Both live in this registry: a
    // building is a unit whose speed happens to be zero.
    expect(registry.all, hasLength(17));
    for (final id in const [
      'dab',
      'roller',
      'brusher',
      'kite',
      'pin',
      'sprayer',
      'nozzle',
      'sniper_nib',
      'swarmlets',
      'bucket_bot',
      'warden',
    ]) {
      expect(registry.contains(id), isTrue, reason: '$id is missing');
    }
  });

  test('the section 6 stat table survives the round trip', () {
    final brusher = registry['brusher'];
    expect(brusher.cost, 3);
    expect(brusher.hp, 340);
    expect(brusher.damage, 70);
    expect(brusher.hitRate, 1.0);
    expect(brusher.paint, 1.0);
    expect(brusher.melee, isTrue);

    final sprayer = registry['sprayer'];
    expect(sprayer.cost, 4);
    expect(sprayer.hp, 220);
    expect(sprayer.range, 5.0);
    expect(sprayer.melee, isFalse);
    expect(sprayer.paint, 1.4);

    final roller = registry['roller'];
    expect(roller.hp, 620);
    expect(roller.paint, 2.2);
    expect(
      roller.speed,
      lessThan(registry['brusher'].speed),
      reason: 'Roller is slow, Brusher is medium',
    );
  });

  test('speed words resolve to numbers, and melee resolves to a reach', () {
    expect(registry['dab'].speed, greaterThan(registry['brusher'].speed));
    expect(registry['dab'].range, registry.tuning.meleeRange);
    expect(registry['sniper_nib'].range, 8.0);
  });

  test('aggro range defaults by reach and can be overridden', () {
    expect(registry['brusher'].aggroRange, registry.tuning.meleeAggro);
    expect(registry['sprayer'].aggroRange, registry.tuning.rangedAggro);
    // "Walks straight" is data: Roller never diverts to chase.
    expect(registry['roller'].aggroRange, 0.0);
  });

  test('multi-body cards report their body count', () {
    expect(registry['dab'].count, 3);
    expect(registry['swarmlets'].count, 6);
    expect(registry['brusher'].count, 1);
  });

  test('targeting masks read correctly', () {
    expect(registry['brusher'].targets.canHit(flying: false), isTrue);
    expect(registry['brusher'].targets.canHit(flying: true), isFalse);

    // Pin is the anti-air answer and must reach both.
    expect(registry['pin'].targets.canHit(flying: true), isTrue);
    expect(registry['pin'].targets.canHit(flying: false), isTrue);
    expect(registry['sniper_nib'].targets.canHit(flying: true), isTrue);
  });

  test('Kite is the only flyer', () {
    final flyers = registry.all.where((u) => u.flying).map((u) => u.id);
    expect(flyers, ['kite']);
  });

  test('levels 1 to 9 add 8% HP and damage, and never touch cost', () {
    final base = registry['brusher'];
    final maxed = registry.at('brusher', 9);

    expect(base.level, 1);
    expect(maxed.level, 9);
    expect(maxed.hp, closeTo(340 * (1 + 0.08 * 8), 0.001));
    expect(maxed.damage, closeTo(70 * (1 + 0.08 * 8), 0.001));
    expect(maxed.cost, base.cost);
    expect(maxed.speed, base.speed);
    expect(maxed.paint, base.paint);
    expect(maxed.hitRate, base.hitRate);
  });

  test('levels clamp to the 1..9 range', () {
    expect(registry.at('brusher', 0).level, 1);
    expect(registry.at('brusher', 99).level, 9);
  });

  test('attack interval is the inverse of hit rate', () {
    expect(registry['sprayer'].attackInterval, closeTo(1 / 1.4, 1e-9));
    expect(registry['sniper_nib'].attackInterval, closeTo(2.0, 1e-9));
  });

  test('an unknown id fails loudly rather than silently', () {
    expect(() => registry['not_a_card'], throwsArgumentError);
  });

  test('every body in the set has a component behind it', () {
    expect(registry.implemented, hasLength(17));
    for (final stats in registry.all) {
      expect(registry.isImplemented(stats.id), isTrue, reason: stats.id);
    }
  });

  test('the troops with real behaviour carry the data for it', () {
    // Nozzle splashes around whatever it hit.
    expect(registry['nozzle'].hasSplash, isTrue);
    expect(registry['nozzle'].splashRadius, 1.5);

    // Whirl uses the same field for a circle around *itself*, which is what
    // makes standing behind it no safer than standing in front.
    expect(registry['whirl'].hasSplash, isTrue);
    expect(registry['whirl'].splashRadius, 1.6);

    // Warden's aura is 25% off inside 3.0.
    expect(registry['warden'].hasAura, isTrue);
    expect(registry['warden'].auraRadius, 3.0);
    expect(registry['warden'].auraDamageReduction, 0.25);

    // And nobody else has either.
    const splashers = {'nozzle', 'whirl'};
    for (final stats in registry.all) {
      if (splashers.contains(stats.id)) continue;
      expect(stats.hasSplash, isFalse, reason: stats.id);
    }
    for (final stats in registry.all) {
      if (stats.id == 'warden') continue;
      expect(stats.hasAura, isFalse, reason: stats.id);
    }
  });

  test('every card in the file declares a cost the elixir bar can pay', () {
    for (final unit in registry.all) {
      expect(unit.cost, inInclusiveRange(1, 10), reason: unit.id);
      expect(unit.hp, greaterThan(0), reason: unit.id);
      expect(unit.radius, greaterThan(0), reason: unit.id);
    }
  });
}
