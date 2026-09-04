import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/game/cards/card_registry.dart';
import 'package:splatfront/game/units/rive_units.dart';
import 'package:splatfront/game/units/unit_art.dart';

/// The Rive seam, tested from the side a headless suite can reach.
///
/// rive_native is FFI and there is no native library under `flutter test`, so
/// nothing here decodes a file. What is worth pinning is the half that
/// decides *whether* a unit gets Rive art at all — the naming rule, and the
/// fact that every card still has a vector character to fall back to — plus
/// the fitting constants the art contract quotes at artists.
void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('asset discovery', () {
    test('picks up a .riv named after a card, and nothing else', () {
      expect(
        riveCardIds(const [
          'assets/rive/roller.riv',
          'assets/rive/bucket_bot.riv',
          'assets/rive/brusher.png',
          'assets/audio/hit.wav',
          'assets/data/cards.json',
        ]),
        ['bucket_bot', 'roller'],
      );
    });

    test('ignores a working file in a subfolder', () {
      // An artist's source tree under assets/rive/ is not a roster of units.
      expect(
        riveCardIds(const [
          'assets/rive/src/roller_wip.riv',
          'assets/rive/roller.riv',
        ]),
        ['roller'],
      );
    });

    test('finds nothing in an empty folder, which is where the game ships', () {
      expect(riveCardIds(const []), isEmpty);
      expect(riveCardIds(const ['assets/rive/']), isEmpty);
    });
  });

  group('fallback', () {
    late CardRegistry cards;
    setUpAll(() async => cards = await CardRegistry.load());

    test('no art loaded means no card claims a Rive artboard', () {
      expect(RiveUnitLibrary.cardIds, isEmpty);
      for (final card in cards.all) {
        expect(RiveUnitLibrary.has(card.id), isFalse);
        expect(RiveUnitLibrary.create(card.id), isNull);
      }
    });

    test('every unit card keeps a vector character behind the seam', () {
      // This is what makes a partly-converted roster safe: art can land one
      // card at a time and the rest of the field still draws.
      for (final card in cards.all) {
        if (!card.kind.isUnit) continue;
        expect(
          unitArt.containsKey(card.id),
          isTrue,
          reason: '${card.id} has neither Rive art nor a vector character',
        );
      }
    });
  });

  group('the size contract', () {
    test('a Rive character stands the same height as a vector one', () {
      // The vector convention: feet on y = 1.0, crown near y = -1.6, so 2.6
      // of character. The contract doc quotes these two numbers at artists,
      // and art fitted to them drops in beside vector art without resizing.
      expect(RiveUnitAnimation.feetY, 1.0);
      expect(RiveUnitAnimation.artboardHeight, greaterThan(2.6));
      expect(RiveUnitAnimation.artboardHeight, lessThan(3.1));
    });
  });
}
