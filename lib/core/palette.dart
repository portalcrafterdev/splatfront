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
  static const Color red = Color(0xFFE5443C);

  /// The player.
  static const Color blue = Color(0xFF2C4CB0);

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

  /// The heavy dark line around a menu tile.
  ///
  /// This is what makes the style, and it only works on a light ground: a
  /// thick near-black outline on every shape. (The dark build had to drop it
  /// for a lit top edge, because a dark line on a dark page is nothing.)
  static const Color outline = Color(0xFF15201C);

  /// The flat drop shadow under an outlined tile. Solid and offset rather
  /// than blurred — a soft shadow under a hard outline looks like a mistake.
  static const Color outlineShadow = Color(0xFF0B1512);

  // --- In-match chrome, which stays dark ---------------------------------
  //
  // The HUD sits over the arena and the cards read as physical objects, so
  // both keep the dark set they were designed against.

  static const Color hudBackground = Color(0xFF1C1A17);
  static const Color hudSurface = Color(0xFF2B2823);
  static const Color hudText = Color(0xFFF6F1E7);
  static const Color hudTextDim = Color(0xFF9C948A);

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
