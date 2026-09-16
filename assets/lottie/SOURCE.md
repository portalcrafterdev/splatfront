# Where `hand_tap.json` came from

- **Animation:** "hand tap" (`hand_tap_01`)
- **Page:** https://lottiefiles.com/free-animation/hand-tap-5z6XERrjjo
- **File:** https://assets-v2.lottiefiles.com/a/a3f78f04-1152-11ee-aa36-b3416afe72fb/EiAr5FyZAa.lottie
- **Credited author in the dotLottie manifest:** LottieFiles
- **Licence:** LottieFiles free animation. Their free library ships under the
  Lottie Simple Licence, which permits use in a commercial product but not
  redistribution of the animation on its own. Chosen by the owner, who picked
  this specific animation.

Downloaded as a `.lottie` (a zip holding `manifest.json` and
`animations/12345.json`) and unpacked — the plain JSON is committed because
nothing else in the archive was needed and a single file keeps the asset
loadable without a decoder.

## The file is used unmodified

Not one byte of it is edited, so replacing it is a straight file swap. Two
things about it do not suit the app, and **both are corrected in Dart at load
time** rather than by rewriting the JSON — see `HandAnimations` in
`lib/ui/tutorial/hand_gesture_indicator.dart`:

- **Everything in it is `#000000`.** The hand is drawn over a dark scrim, so
  as shipped it is invisible. `LottieDelegates` recolours the fills to
  `Palette.hudOnScrim`, the hand's outline to `Palette.outlineShadow` and the
  ripple rings to `Palette.accent`.
- **The fingertip is not in the middle of the frame.** Measured by rendering
  the composition and finding the topmost ink at rest: **(241.5, 177)** of
  600 x 600, so `(0.403, 0.295)` as a fraction. The widget translates by that
  much, or the hand points about 23dp below whatever it is aimed at.

## Numbers a replacement file has to declare

`600 x 600`, `25` fps, `41` frames — 1.64s, which is what `cycle` is set to.
`tutorial_test.dart` pins the frame rate and the frame count, so a swapped
file that plays at a different speed fails loudly instead of quietly running
fast or slow.
