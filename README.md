# SPLATFRONT

A real-time territory-painting card battler for Android and iOS, built with
Flutter and Flame.

Two sides fight over a single arena screen: **you are Blue, the bot is Red.**
Every unit you deploy walks around and paints the ground in your colour. When
the timer runs out, whoever has painted more of the arena wins.

The hook is that the paint layer is three things at once:

- **the scoreboard** — coverage is the win condition
- **the economy** — elixir regenerates faster the more ground you hold
- **the battlefield** — you can only deploy a card onto ground your side
  already owns, so painting forward is what extends your reach

Losing paint costs you the means to take it back, which is what keeps a match
from settling early.

## Playing

- **90 seconds.** If the two sides are within 5% at the whistle, sudden death
  adds 30 more at double elixir income.
- **A deck is 6 cards**, four in hand with the next one previewed.
- **Playing any card locks the whole hand** for five seconds, not just the
  slot you spent. A turn is one card, so *which* card matters far more than
  how many the elixir bar can pay for.
- **21 cards**: troops, buildings that expire on a timer, and spells that
  ignore the deploy rule and can land anywhere.
- Three bot difficulties, four arenas, chests, and card levels 1–9.

Single player against bots, offline, with no ads and no in-app purchases.

## Building

```sh
flutter pub get
flutter run              # debug, on a connected device
flutter test             # the full suite
flutter build apk --profile
```

Portrait phones are the primary target; tablet portrait and large-tablet
layouts are handled by breakpoints in `lib/ui/widgets/responsive.dart`.

## How it is put together

```
lib/
  core/      constants, palette, audio, save
  game/
    arena/   the paint layer, its sampler, and the deploy map
    units/   one file per troop and building
    cards/   deck, hand rotation, elixir
    spells/  the four effects
    bot/     one brain, three sets of numbers
    match/   clock, sudden death, result
    fx/      particles, splatter, screen shake
  meta/      chests, quests, upgrades, profile
  ui/        screens and widgets (Flutter, not Flame)
```

Two rules hold throughout:

**All balance numbers live in JSON.** `assets/data/` holds the card stats,
bot decks, progression and costs. A balance pass is a JSON edit and a hot
restart, never a Dart change.

**The two chrome palettes never mix.** `Palette.ui*` is the menus, which are
light; `Palette.hud*` is the match, which is dark because it sits over a lit
board. Chrome hues are chosen to keep their distance from the two team
colours, so a button never reads as belonging to one side.

## Testing

`flutter test` runs the suite. `test/duel_harness.dart` is deliberately *not*
named `_test.dart` — it plays dozens of simulated ninety-second matches to
measure bot strength, which does not belong in every test run. Invoke it
directly when tuning difficulty:

```sh
flutter test test/duel_harness.dart
```
