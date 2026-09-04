import 'dart:ui';

/// The two sides. [neutral] is nobody's colour: it scores for nobody and
/// blocks both sides from deploying.
///
/// The order matters: [Palette.classifyTargets] is indexed by [Team.index] in
/// the coverage sampler's hot loop.
enum Team { red, blue, neutral }

extension TeamX on Team {
  Team get opponent => switch (this) {
    Team.red => Team.blue,
    Team.blue => Team.red,
    Team.neutral => Team.neutral,
  };

  Color get colour => Palette.of(this);
}

class Palette {
  const Palette._();

  // --- The arena -----------------------------------------------------------
  //
  // Team colours are picked for separation first and prettiness second,
  // because at a glance mid-match the only question is whose ground that is.
  // Red and dark blue sit roughly opposite on the wheel *and* far apart in
  // lightness (57% against 43%), so they stay apart in a screenshot, at
  // thumbnail size, and for a red-green colourblind player.
  //
  // These are only ever the two sides. Menu chrome has its own colours below;
  // never reach for a team colour to accent a button, or the UI starts
  // claiming a side.

  /// The bot.
  ///
  /// Lifted 8 points in lightness from the original #E5443C, along with blue,
  /// because the pair was chosen against a near-white arena floor and the
  /// match screen is now a bright sky — the two of them read as heavy and
  /// unlit against it.
  ///
  /// **Both had to move together.** The rule below is a 12-point lightness
  /// gap between the sides, and lifting only the darker one closes it: that
  /// gap is what a colourblind player has instead of hue, so it is not
  /// negotiable and it is what fixes how far either can travel.
  ///
  /// **Saturation came down on the owner's call** — red 90% to 75%, blue 85%
  /// to 68% — because these two are not accents. Each covers up to half the
  /// screen for ninety seconds at a time, and chroma that looks right on a
  /// swatch the size of a button is genuinely tiring at that size. Hue and
  /// lightness are untouched, so both sides read exactly as before and every
  /// gap the sampler and a colourblind player depend on is unchanged.
  static const Color red = Color(0xFFE96A63);

  /// The player.
  ///
  /// The one that actually looked wrong. At 43% lightness it was the darkest
  /// thing on a screen that had just become a bright day.
  ///
  /// This is the owner's cornflower — hue 219, which is what gives it its
  /// character — held at 51% lightness rather than the 56% of the swatch it
  /// came from, and calmed from that swatch's 85% saturation to 68%. **The five points are not a preference and
  /// cannot be given back.** Two hard rules pin it from above:
  ///
  ///  * the sides must sit 12 points apart in lightness, so a blue at 56%
  ///    forces red up to 68%;
  ///  * white text on red must clear 3:1, and red fails that at 67%.
  ///
  /// There is no red that satisfies both, so the blue is as light as the pair
  /// allows. The only way to the exact swatch is to make red the *darker*
  /// side instead — the gap does not care which way round it runs — and that
  /// means a deep crimson against a bright blue, which is a different look
  /// rather than a lighter one.
  ///
  /// **Saturation came down on the owner's call** — red 90% to 75%, blue 85%
  /// to 68% — because these two are not accents. Each covers up to half the
  /// screen for ninety seconds at a time, and chroma that looks right on a
  /// swatch the size of a button is genuinely tiring at that size. Hue and
  /// lightness are untouched, so both sides read exactly as before and every
  /// gap the sampler and a colourblind player depend on is unchanged.
  static const Color blue = Color(0xFF2D69D7);

  /// Unpainted / solvent-wiped ground. Cool grey so it does not read as a
  /// washed-out red, which a warm grey next to red always does.
  static const Color neutral = Color(0xFFB9BAC2);

  /// Arena floor under the paint layer. Very nearly white and very slightly
  /// cool: a warm cream floor turns muddy where red paint meets it.
  static const Color arenaFloor = Color(0xFFEDEDF0);

  /// Static blockers.
  static const Color blocker = Color(0xFF5C6068);

  /// Drop feedback while dragging a card.
  static const Color deployValid = Color(0xFF3BD16F);

  /// Deliberately pink rather than red: this marker is drawn *over* the paint
  /// layer, and a red X on red ground is an invisible rejection.
  ///
  /// Pushed further toward magenta when the sides were lightened. At the
  /// original hue it cleared the readability floor in `palette_test.dart` by
  /// 200 of 3600, which is not a margin — the next nudge to the red would
  /// have taken the rejection marker down with it.
  static const Color deployInvalid = Color(0xFFFF2D8F);

  // --- Menu chrome ---------------------------------------------------------
  //
  // Kept warm on purpose. The menus are a different place from the arena, and
  // holding them apart stops orange furniture reading as "the red team's
  // screen".

  // The chrome hues are chosen around the two sides, not independently of
  // them. Red sits at hue 3 and blue at 224, which leaves two clear gaps —
  // roughly 40 to 200, and 250 to 350 with magenta already taken by elixir.
  // Everything below lives in one of those gaps, and the distance to each
  // team colour is written next to it. This mattered less when the menus
  // were a plain cream page; it matters now that the board shows through
  // behind them, because chrome that shares a hue with the ground it sits on
  // stops reading as chrome.

  /// The single highlight colour: buttons, selection, focus.
  ///
  /// Teal, hue 175 — 49 from blue and 172 from red. It was orange at hue 24,
  /// which put every button in the same family as the opponent's half of the
  /// background, and the Battle button was the worst of it: a warm block on
  /// warm ground. Cool chrome over a warm board also does the other useful
  /// thing, which is to look like interface rather than like paint.
  ///
  /// Dark enough for the white labels already on it. The first teal tried
  /// here was a bright #14C8B8, which measured **2.10:1** against white —
  /// worse than the orange it replaced (2.60) and under the 3:1 floor for
  /// large text. This one is 3.74:1 against white, which is what lets the
  /// Battle button keep its white label. `palette_test.dart` pins it, because
  /// contrast is not something anyone can see by reading a hex value.
  static const Color accent = Color(0xFF0D9488);

  /// The flat shadow under a filled accent control.
  ///
  /// Same hue, darker: the near-black [outlineShadow] belongs under an
  /// outlined tile on the page, and putting it under a small teal pill just
  /// makes the pill look dirty. A tonal shade reads as the same object
  /// catching less light.
  static const Color accentShade = Color(0xFF0A6F66);

  /// Secondary highlight for stat chips and labels.
  ///
  /// Violet, hue 271 — 46 from blue. Deep rather than bright, because this
  /// one has to be read as small text and a thin border on a pale page; the
  /// lighter #A855F7 that suited a dark ground washes out on this one.
  static const Color info = Color(0xFF9333EA);

  /// Chests and rewards. Amber, hue 41 — the one chrome colour that stays
  /// near the red end, and it earns the exception: gold has to look like
  /// gold. Confined to chests and the coin count, never a state, so it does
  /// not have to hold up next to the board.
  ///
  /// Deep rather than bright. The light `#F5B62E` that suited a dark page
  /// measured 1.77:1 against a near-white chip, which makes the coin icon
  /// effectively invisible; this is 3.96:1.
  static const Color gold = Color(0xFFA97400);

  /// Done, affordable, healthy.
  static const Color success = Color(0xFF3BD16F);

  /// Cannot afford, negative trophy change, unhealthy.
  static const Color danger = Color(0xFFE2444B);

  // The menus are light and the arena is dark, and that is on purpose: the
  // app is a bright place you tap around in, and the match is a lit board you
  // look into. Two sets rather than one, so changing how a menu looks cannot
  // quietly repaint the HUD sitting over the arena.
  //
  // Cool rather than warm. The first light scheme was a cream page with an
  // orange accent, which the owner rejected twice; a brief dark version was
  // rejected too. This is light again but nowhere near that palette — a pale
  // cold page, a heavy ink outline, and teal doing the work orange used to.
  //
  // The known cost of a light page is the card art: a CardTile is drawn
  // against the dark hud* set, so on a pale page each one is a dark rectangle
  // and the Collection can read as holes punched in the paper. The answer is
  // to frame them — see _CollectionCard — not to darken the page around them.

  /// Menu page. Pale and slightly cold, with a whisper of green in it so it
  /// does not go blue by contrast next to the teal.
  static const Color uiBackground = Color(0xFFEDF2EF);

  /// A menu tile sitting on that page, and the bottom of a panel gradient.
  static const Color uiSurface = Color(0xFFFAFDFB);

  /// The top of a panel gradient, and any tile that should read as raised.
  static const Color uiSurfaceHigh = Color(0xFFFFFFFF);

  /// Menu ink. A very dark green-black rather than pure black: black on a
  /// tinted page reads as a spreadsheet, and this is a game.
  static const Color uiText = Color(0xFF15201C);
  static const Color uiTextDim = Color(0xFF5F6E68);

  /// The heavy dark line that used to go around every menu tile.
  ///
  /// **Retired on the owner's call.** It was the house style — a thick
  /// near-black outline on every shape, with [outlineShadow] hard-offset under
  /// it — and the menus now use `Panel.softEdge` and `Panel.softShadow`
  /// instead: a hairline for the edge, a blurred drop for the lift. Nothing
  /// reaches for these two any more except `Panel(outlined: true)`, which
  /// nothing passes.
  ///
  /// Both are kept, and so is that flag, because the argument for the outline
  /// was real and is worth knowing before anyone puts a light tile on a light
  /// page again: without *some* edge a panel dissolves into the ground and
  /// every boundary has to be found rather than seen. The soft pair is a
  /// quieter answer to that problem, not an abandonment of it. (The brief dark
  /// build had to drop the line too, for the opposite reason — a dark line on
  /// a dark page is nothing at all.)
  static const Color outline = Color(0xFF15201C);

  /// The flat drop shadow that went under an outlined tile. Solid and offset
  /// rather than blurred, because a soft shadow under a hard outline looks
  /// like a mistake — and, the other way round, this one under a *borderless*
  /// tile reads as a black bar. The two only ever worked as a pair.
  static const Color outlineShadow = Color(0xFF0B1512);

  // --- In-match chrome ----------------------------------------------------
  //
  // **This set used to be dark and is now a bright day.** Section 14 said the
  // menus were light and the match stayed dark, and that the two must never
  // be mixed. The owner reversed the dark half on a reference image: sky
  // behind the board, pale cards, and the board itself set into a dark frame.
  //
  // The half of the rule that still stands, and is the reason it existed, is
  // that these are a **separate set** from `ui*`. A match screen and a menu
  // are not the same room. Reaching for `uiSurface` in the HUD or `hudSurface`
  // in a menu is still how the two drift into one flat theme.
  //
  // The board keeps a dark bezel, and that is now load-bearing rather than
  // decorative: it is the only thing separating a blue sky from a blue side.

  /// The sky, top to bottom. Lighter toward the horizon, as a sky is.
  ///
  /// Hue 201 — which is, honestly, 23 from the blue side at 224, closer than
  /// anything else in the app gets to a team colour. **Lightness is what
  /// keeps them apart**: the sky sits at 69–80% against blue's 51%, the same
  /// separation section 14 relies on for red against blue. The dark bezel
  /// does the rest, and neither can be softened without the board starting to
  /// bleed into the background behind it.
  ///
  /// The top of the sky was #59B7EA and had to be lifted when blue was: that
  /// gap had fallen to 12 points, and `palette_test.dart` caught it. The two
  /// are coupled, and anything that darkens this or lightens blue has to move
  /// the other with it.
  static const Color hudSkyHigh = Color(0xFF6FC4F0);
  static const Color hudSkyLow = Color(0xFF9FD9F2);

  /// The frame the arena is set into, and the ground for anything that has to
  /// stay legible over sky — the clock, most of all.
  static const Color hudBezelHigh = Color(0xFF3A4147);
  static const Color hudBezelLow = Color(0xFF20262B);

  /// A card, and the deck the hand sits on. A pale mint rather than a plain
  /// white: the units are drawn in team colour, and flat white behind a blue
  /// body makes the body look like a cut-out.
  static const Color hudSurface = Color(0xFFFFFFFF);
  static const Color hudSurfaceLow = Color(0xFFDCEFE3);
  static const Color hudTrayHigh = Color(0xFFEAF6F0);
  static const Color hudTrayLow = Color(0xFFC7DED4);

  /// Kept as the tone anything translucent darkens toward — a card's cooldown
  /// shutter, the strip behind a body count. Those still want to be dark on a
  /// light card, because they are covering it up.
  static const Color hudBackground = Color(0xFF16211D);

  /// Match ink, now that the match is printed on paper rather than on night.
  static const Color hudText = Color(0xFF16211D);
  static const Color hudTextDim = Color(0xFF5C6B65);

  /// The heavy line around a card, so it reads as a chunky object on a busy
  /// sky the way a menu tile does on a plain page.
  static const Color hudOutline = Color(0xFF1B2A26);

  /// Ink for text printed on the dark scrim — the countdown and the end
  /// screen.
  ///
  /// Those two dim the arena rather than sitting beside it, because both have
  /// to be read *over* a lit board, and that stayed true when the rest of the
  /// match went light. [hudText] went dark with the theme, so anything on the
  /// scrim needs the opposite pair or it disappears the moment the theme
  /// flips — which is exactly what happened.
  static const Color hudOnScrim = Color(0xFFF2F7F5);
  static const Color hudOnScrimDim = Color(0xFFA8B5B0);

  /// Elixir, and the cost badge on every card.
  ///
  /// Magenta on purpose, and it should stay in this part of the wheel. Red
  /// sits at hue 3 and blue at 224, which leaves one wide gap between them —
  /// this is the middle of it, about 85 from blue and 66 from red. A resource
  /// bar that drifted toward either would start reading as a side's meter,
  /// and gold or amber, the obvious "currency" choice, lands 41 from red.
  static const Color elixir = Color(0xFFD65CC8);

  static Color of(Team team) => switch (team) {
    Team.red => red,
    Team.blue => blue,
    Team.neutral => neutral,
  };

  /// The three classification targets used by the coverage sampler, in
  /// [Team.index] order.
  static const List<Color> classifyTargets = [red, blue, neutral];
}
