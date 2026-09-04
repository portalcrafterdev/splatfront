# Rive art contract

What a `.riv` file has to look like for SPLATFRONT to pick it up and drive it.

Nothing in `lib/` needs editing when art arrives. Drop the file into
`assets/rive/` and relaunch — `RiveUnitLibrary` finds it from the asset
manifest. A card with no file keeps the hand-drawn vector character in
`lib/game/units/unit_art.dart`, and the two sets can be mixed freely: a match
with a Rive Roller and a vector Brusher is fine and looks fine.

## The file

| | |
|---|---|
| Path | `assets/rive/<card id>.riv` — one file per unit |
| Card ids | Exactly as spelled in `assets/data/cards.json`: `dab`, `roller`, `brusher`, `kite`, `pin`, `sprayer`, `nozzle`, `sniper_nib`, `swarmlets`, `bucket_bot`, `warden`, `whirl`, `turret`, `sprinkler`, `barricade`, `beamer`, `scatter` |
| Artboard | Named after the card id. An artboard by any other name is used only if it is the file's default |
| State machine | The artboard's default. Named anything; if there is more than one, the default is the one that runs |

A file with no state machine still draws — it just sits at its rest pose. That
is enough for a card tile and not enough for the arena.

## Size and origin

The game draws in **art units, where 1.0 is the unit's collision radius**. The
artboard's frame is fitted so the character stands **2.8 art units tall with
its feet on the ground line**. Whatever the artboard's pixel size, it is
scaled to that, so the only thing that matters is the proportion: draw the
character filling the artboard frame top to bottom, feet on the bottom edge.

Get this wrong and the unit is the right shape at the wrong size — it is the
one thing worth checking against a vector character on the same screen.

## Facing

Characters **stand upright and do not rotate.** They face the way they walk:
eyes toward the camera coming down the screen, back of the head going away. A
top-down silhouette is unreadable at the 40 px these are drawn at.

## Inputs

All optional. A missing input costs that one signal, not the character.

| Role | Type | Name (first match wins) |
|---|---|---|
| Walking vs idle | bool | `walking`, `walk`, `moving`, `run` |
| Swing | trigger | `attack`, `swing`, `fire`, `shoot` |
| Death | trigger | `die`, `death`, `killed` |
| Death, as a latch | bool | `dying`, `dead` |
| Hit flash, 0 to 1 | number | `flash`, `hurt`, `damage` |
| Facing, -1 to 1 | number | `facingX` / `facingY`, `faceX` / `faceY`, `directionX` / `directionY` |
| Side: 0 red, 1 blue | number | `team`, `colour`, `color`, `side` |

The alternatives exist because art arrives from whoever drew it. Prefer the
first name in each row.

## Four things the art has to handle itself

The vector characters get these from the code that frames them. A Rive
artboard is drawn on its own, so its state machine owns all four.

1. **The lunge on a swing.** Nothing outside nudges a Rive unit forward when
   it attacks.
2. **The death collapse.** A unit is removed **0.6 s** after the die trigger
   (`Timings.deathFadeOut`), so a die state longer than that is cut off part
   way. The engine fades the whole artboard out over that 0.6 s as a backstop,
   so art with no die state does not leave a solid body on the floor — but a
   fade is not a death animation.
3. **The hit flash.** Read `flash` and white the character out with it.
4. **The team colour.** Read `team` and switch a colour group. Red is
   `#E96A63`, blue is `#2D69D7`; both are in `lib/core/palette.dart`.

## The cream rim

Every vector character is drawn twice — once as a fat pale stroke, then
normally on top — because a unit standing on its own fresh paint is otherwise
the same colour as the ground under it. **Rive art has to build that rim in**,
as an outline on the outermost shapes. It is not optional; without it the unit
disappears the moment it paints the tile it is standing on.

## Checking one

There is no substitute for the phone. Build a debug APK, open the unit
sandbox from Home, and spawn the unit: the sandbox is where the frame-rate
readout and the `+40 stress` chip live, and 40 artboards is the number the
performance budget is written against.
