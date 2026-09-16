import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game_data.dart';
import '../../core/palette.dart';
import '../../core/save/player_profile.dart';
import '../../game/cards/card_model.dart';
import '../../game/cards/card_registry.dart';
import '../../meta/profile_controller.dart';
import '../widgets/card_tile.dart';
import '../widgets/meta_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/responsive.dart';
import '../type.dart';

/// Collection and deck builder.
///
/// Tap any card to open its upgrade sheet. Hold a deck card to arm a swap,
/// then tap the card that takes its place. A tap is never destructive.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  /// The deck slot waiting to be replaced, if any.
  String? _swapping;

  /// The card whose own page is open, if any. Held here rather than pushed as
  /// a route so the bottom bar stays visible behind it.
  String? _detail;

  @override
  Widget build(BuildContext context) {
    final open = _detail;
    if (open != null) {
      return PopScope(
        // The system back gesture closes the card rather than leaving the
        // tab. Without this, backing out of a card detail drops the player
        // off Cards entirely, which is not what the arrow in the corner
        // implies and not what the gesture means anywhere else.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _detail = null);
        },
        child: _CardPage(
          cardId: open,
          onBack: () => setState(() => _detail = null),
        ),
      );
    }
    return _gridPage(context);
  }

  Widget _gridPage(BuildContext context) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);
    final layout = Breakpoints.of(context);

    final deck = controller.deck.cardIds;

    // Owned cards first, sorted by cost; the locked ones follow in the order
    // they will arrive, which turns the tail of the page into a road map
    // rather than a wall of padlocks in an arbitrary order.
    final owned = controller.unlockedCards.toList()
      ..sort((a, b) => a.cost.compareTo(b.cost));
    final locked =
        data.cards.playable
            .where((c) => !controller.isCardUnlocked(c.id))
            .toList()
          ..sort(
            (a, b) => (controller.campaign.unlockLevelFor(a.id) ?? 0).compareTo(
              controller.campaign.unlockLevelFor(b.id) ?? 0,
            ),
          );

    // A swap needs somewhere to swap *from*. Until the campaign hands over a
    // seventh card, everything owned is already in the deck and there is no
    // card outside it to bring in.
    final canSwap = owned.length > deck.length;

    // Cards you have both the copies and the coins for, right now. Cheapest
    // first, so the one a child can most nearly afford twice is on the left.
    final readyToGrow = owned
        .where((c) => controller.canUpgrade(c.id))
        .toList();

    final swapping = _swapping;
    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MetaHeader(
                // "Cards", which is what the tab in the bottom bar has always
                // called it. Two names for one screen is one too many, and of
                // the two "collection" is the word a child is less likely to
                // have.
                title: 'Cards',
                profile: profile,
                // Says what tapping actually does *now*, which changes with
                // how many cards you own.
                //
                // It used to promise "tap any other card to level it up" on a
                // screen where there was no other card — every card owned was
                // in the deck, so the only grid on the page was the deck, and
                // tapping there armed a swap. There was no route to the
                // upgrade sheet at all from a starting collection.
                subtitle: swapping != null
                    ? 'Now pick the card that takes '
                          '${data.cards[swapping].name}\'s place.'
                    : canSwap
                    // Tap and hold do different things, and the tap is the
                    // one named first because it is the one that is always
                    // safe. Holding a deck card to swap it out was a plain
                    // tap, which is a child's default gesture — so the most
                    // destructive thing on the screen was also the easiest
                    // one to do by accident.
                    ? 'Tap a card to make it stronger. '
                          'Hold a deck card to swap it out.'
                    : 'Tap a card to make it stronger.',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    SectionHeading(
                      swapping == null ? 'Your deck' : 'Swapping out',
                      trailing: swapping == null
                          ? '${deck.length} cards'
                          : null,
                    ),
                    _grid(
                      cards: [for (final id in deck) data.cards[id]],
                      profile: profile,
                      layout: layout,
                      readyToUpgrade: controller.canUpgrade,
                      copiesNeeded: (level) =>
                          data.upgrades.stepFrom(level)?.copies,
                      lockedUntil: (_) => null,
                      highlight: _swapping,
                      // A tap always means "make this stronger", in the deck
                      // and out of it. It used to mean "arm a swap" here and
                      // "level up" everywhere else, so the same gesture on
                      // two grids on one page did two different things — and
                      // the destructive one was on the default gesture.
                      //
                      // Mid-swap a tap picks the card to take out instead,
                      // because the page is asking a question and a tap is
                      // how you answer it.
                      onTap: (card) {
                        if (_swapping != null) {
                          setState(
                            () => _swapping = _swapping == card.id
                                ? null
                                : card.id,
                          );
                          return;
                        }
                        _showUpgradeSheet(card);
                      },
                      // Holding arms the swap. Nothing to swap with means
                      // nothing happens: arming it would be a dead end
                      // dressed up as a selection, with the header asking for
                      // a replacement and no card on the page to pick.
                      onHold: canSwap
                          ? (card) => setState(
                              () => _swapping = _swapping == card.id
                                  ? null
                                  : card.id,
                            )
                          : null,
                    ),

                    // The one section that answers "what can I actually do
                    // right now". Everything else on this page is a picture
                    // of what you own; these are the cards with enough copies
                    // and enough coins behind them to change today.
                    //
                    // Deliberately allowed to repeat a card already shown in
                    // the deck above. It is a callout, not a category — a
                    // child should not have to audit six tiles for a small
                    // green label to find the one that is ready.
                    if (readyToGrow.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      SectionHeading(
                        'Ready to grow',
                        trailing: '${readyToGrow.length}',
                      ),
                      _grid(
                        cards: readyToGrow,
                        profile: profile,
                        layout: layout,
                        readyToUpgrade: controller.canUpgrade,
                        copiesNeeded: (level) =>
                            data.upgrades.stepFrom(level)?.copies,
                        lockedUntil: (_) => null,
                        onTap: _showUpgradeSheet,
                      ),
                    ],

                    // Until the campaign hands over a seventh card, everything
                    // owned is already in the deck and this grid would be a
                    // second copy of the one above it.
                    //
                    // It used to collapse to a heading plus a sentence saying
                    // so, which is the worst of both: a section heading with
                    // no section under it, wearing 22dp of air at each end, so
                    // the middle of the page was a hundred and fifty pixels of
                    // nothing between two grids. The whole block goes now, and
                    // the count it was carrying moves onto the heading below,
                    // which is about the same subject anyway.
                    if (owned.length > deck.length) ...[
                      const SizedBox(height: 18),
                      SectionHeading(
                        'Your cards',
                        trailing:
                            '${owned.length} of ${data.cards.playable.length}',
                      ),
                      _grid(
                        cards: owned,
                        profile: profile,
                        layout: layout,
                        readyToUpgrade: controller.canUpgrade,
                        copiesNeeded: (level) =>
                            data.upgrades.stepFrom(level)?.copies,
                        lockedUntil: (_) => null,
                        dimmed: deck.toSet(),
                        onTap: (card) {
                          final swapping = _swapping;
                          if (swapping == null) {
                            _showUpgradeSheet(card);
                            return;
                          }
                          if (deck.contains(card.id)) return;
                          controller.swapCard(outId: swapping, inId: card.id);
                          setState(() => _swapping = null);
                        },
                      ),
                    ],

                    if (locked.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      // Says what opens them, not just that they are shut.
                      // "Still to come" plus the level on each tile is a plan;
                      // a row of padlocks is a nag.
                      //
                      // The trailing count says how far along the collection
                      // is rather than where the cards come from, which the
                      // level printed on every tile below already answers.
                      SectionHeading(
                        'Still to come',
                        trailing:
                            '${owned.length} of '
                            '${data.cards.playable.length} collected',
                      ),
                      _grid(
                        cards: locked,
                        profile: profile,
                        layout: layout,
                        readyToUpgrade: (_) => false,
                        copiesNeeded: (_) => null,
                        lockedUntil: (id) =>
                            controller.campaign.unlockLevelFor(id),
                        // Tapping one does nothing on purpose: there is no action to
                        // offer. An upgrade sheet for a card you do not own would be
                        // a dead end dressed up as a screen.
                        onTap: (_) {},
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid({
    required List<CardModel> cards,
    required PlayerProfile profile,
    required bool Function(String cardId) readyToUpgrade,
    required int? Function(int level) copiesNeeded,
    required LayoutClass layout,
    required void Function(CardModel card) onTap,
    required int? Function(String cardId) lockedUntil,
    void Function(CardModel card)? onHold,
    Set<String> dimmed = const {},
    String? highlight,
  }) {
    return GridView.count(
      crossAxisCount: layout.collectionColumns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      // Sized to what a cell actually holds, which is a card mount of
      // width x 1.25 plus about 41dp of frame, gap and footer. At 0.62 every
      // row carried roughly 23dp of slack under its labels — two rows of deck
      // and a row of locked cards put nearly 70dp of nothing down the middle
      // of the page, which is what made the gap under the deck read as a
      // missing section rather than as spacing.
      childAspectRatio: 0.66,
      children: [
        for (final card in cards)
          _CollectionCard(
            card: card,
            level: profile.levelOf(card.id),
            copies: profile.copiesOf(card.id),
            needed: copiesNeeded(profile.levelOf(card.id)),
            ready: readyToUpgrade(card.id),
            selected: card.id == highlight,
            dimmed: dimmed.contains(card.id),
            lockedUntil: lockedUntil(card.id),
            onTap: () => onTap(card),
            onHold: onHold == null ? null : () => onHold(card),
          ),
      ],
    );
  }

  /// Opens the card's own page, in place of the grid.
  ///
  /// It was a modal bottom sheet, and a sheet is the wrong container for
  /// this. It covers the page it came from, it is dismissed by a gesture a
  /// child does not necessarily know, and it is short — which is what kept
  /// the card's stats down to one line of "620 HP · 40 dmg" when what that
  /// line needed was four bars and a sentence.
  ///
  /// Rendered inside the tab rather than pushed as a route, so the bottom bar
  /// stays put and the page has one obvious way back: the arrow, top left.
  void _showUpgradeSheet(CardModel card) => setState(() => _detail = card.id);
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.card,
    required this.level,
    required this.copies,
    required this.needed,
    required this.ready,
    required this.selected,
    required this.dimmed,
    required this.lockedUntil,
    required this.onTap,
    this.onHold,
  });

  final CardModel card;
  final int level;
  final int copies;

  /// The campaign level that hands this card over, or null once it is owned.
  ///
  /// Locked cards are still drawn rather than hidden. Knowing that Kite is
  /// waiting at level 21 is a reason to play level 20; a collection that
  /// silently grows has nothing to look forward to.
  final int? lockedUntil;

  /// Copies required for the next level, or null at the cap.
  final int? needed;

  /// Copies *and* coins are both there: this card can be levelled right now.
  final bool ready;

  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  /// Arms a deck swap. Null where there is nothing to swap with, which is
  /// also every grid that is not the deck.
  final VoidCallback? onHold;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onHold,
      child: Opacity(
        opacity: dimmed ? 0.4 : 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Framed, not floated. A CardTile is drawn against the dark
                // hud* set, so on a pale page twenty-one of them read as
                // rectangles punched out of the paper — which is what the
                // Collection looked like before. A light mount with the same
                // outline as every other tile turns each one into a card
                // sitting on the page instead of a hole in it.
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Palette.uiSurfaceHigh,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Panel.softEdge, width: 1),
                    boxShadow: Panel.softShadow,
                  ),
                  // The width has to come off the *actual* border, not a
                  // constant that used to match it: the mount is 3dp of
                  // padding plus its edge on each side, and leaving the old
                  // 2.5dp stroke in this sum after softening the edge to 1
                  // would size every card in the grid three pixels wide.
                  child: _maybeLocked(
                    CardTile(card: card, width: constraints.maxWidth - 6 - 2),
                    locked: lockedUntil != null,
                  ),
                ),
                const SizedBox(height: 8),
                // The bare copy count used to sit under "Lv 1" as a lone
                // number, which read as a second level. What a player wants
                // to know here is one thing: how close is this to going up.
                if (lockedUntil case final at?)
                  _LockedLabel(level: at)
                else
                  _Progress(
                    level: level,
                    copies: copies,
                    needed: needed,
                    ready: ready,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drains the colour out of a locked card and lays a padlock over it.
///
/// Greyscale rather than a low opacity: the art has to stay readable so the
/// player can see what they are working toward, and fading it out on a pale
/// page just makes it disappear.
Widget _maybeLocked(Widget tile, {required bool locked}) {
  if (!locked) return tile;
  return Stack(
    alignment: Alignment.center,
    children: [
      ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: Opacity(opacity: 0.75, child: tile),
      ),
      const Icon(Icons.lock_rounded, size: 26, color: Colors.white),
    ],
  );
}

/// What a locked card is waiting for, in place of its upgrade progress.
class _LockedLabel extends StatelessWidget {
  const _LockedLabel({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) => Text(
    'Level $level',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Palette.uiTextDim,
      fontSize: 11,
      fontWeight: FontWeight.w800,
    ),
  );
}

/// One card's own page: what it is, what it does, and what growing it costs.
///
/// Replaces a modal bottom sheet whose entire stat line was
/// `620 HP · 40 dmg · until destroyed`. Three units of measurement and a rate,
/// which tells an eight-year-old nothing and tells most adults nothing either
/// without a second card to hold it against. The bars below are that second
/// card, built in — every track is the best value in the roster.
class _CardPage extends ConsumerWidget {
  const _CardPage({required this.cardId, required this.onBack});

  final String cardId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);

    final level = profile.levelOf(cardId);
    final copies = profile.copiesOf(cardId);
    final step = data.upgrades.stepFrom(level);
    final card = data.cards.at(cardId, level);
    final peaks = RosterPeaks.of(data.cards);
    final unit = card.unit;

    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    PressScale(
                      onTap: onBack,
                      child: Semantics(
                        button: true,
                        label: 'Back to cards',
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Palette.uiSurfaceHigh,
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: Panel.softShadow,
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            size: 21,
                            color: Palette.uiText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: Fonts.display,
                          color: Palette.uiText,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    CurrencyChip(
                      icon: Icons.monetization_on,
                      value: profile.coins,
                      colour: Palette.accent,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    Panel(
                      outlined: false,
                      radius: 18,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: Column(
                        children: [
                          CardTile(card: card, width: 86),
                          const SizedBox(height: 10),
                          Text(
                            'Level $level',
                            style: const TextStyle(
                              fontFamily: Fonts.display,
                              color: Palette.uiText,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (card.blurb.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              card.blurb,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Palette.uiTextDim,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Spells have no body, so there is nothing here to
                    // measure — no hp, no damage per second, no walking
                    // speed. Four empty tracks would be a worse answer than
                    // no tracks.
                    if (unit != null) ...[
                      const SizedBox(height: 12),
                      Panel(
                        outlined: false,
                        radius: 18,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          children: [
                            StatBar(
                              label: 'Tough',
                              value: RosterPeaks.toughOf(unit) / peaks.tough,
                              colour: Palette.accent,
                              // The two that levelling actually moves.
                              // Section 6: +8% HP and damage per level, and
                              // nothing else. Paint and speed never change,
                              // so they carry no growth mark rather than a
                              // misleading "+0%".
                              growth: step == null ? null : '+8%',
                            ),
                            StatBar(
                              label: 'Hits',
                              value: RosterPeaks.hitsOf(unit) / peaks.hits,
                              colour: Palette.elixir,
                              growth: step == null ? null : '+8%',
                            ),
                            StatBar(
                              label: 'Paint',
                              value: unit.paint / peaks.paint,
                              colour: Palette.lime,
                            ),
                            StatBar(
                              label: 'Speed',
                              value: unit.speed / peaks.speed,
                              colour: Palette.info,
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                    if (step == null)
                      Panel(
                        outlined: false,
                        radius: 18,
                        child: Row(
                          children: const [
                            Icon(
                              Icons.workspace_premium_rounded,
                              color: Palette.gold,
                              size: 22,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'As big as it gets!',
                                style: TextStyle(
                                  color: Palette.uiText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Panel(
                        outlined: false,
                        radius: 18,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cards you need',
                                    style: TextStyle(
                                      color: Palette.uiText,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  // Countable while the target is small,
                                  // which it is for every early level. A big
                                  // target falls back to the fraction the
                                  // rest of the app uses.
                                  if (Pips.suits(step.copies))
                                    Pips(
                                      done: copies.clamp(0, step.copies),
                                      target: step.copies,
                                    )
                                  else
                                    Text(
                                      '$copies / ${step.copies}',
                                      style: const TextStyle(
                                        color: Palette.uiTextDim,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'Coins',
                                  style: TextStyle(
                                    color: Palette.uiTextDim,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${step.coins}',
                                  style: TextStyle(
                                    fontFamily: Fonts.display,
                                    color: profile.coins >= step.coins
                                        ? Palette.uiText
                                        : Palette.danger,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _GrowButton(
                        label: 'GROW TO ${step.level}',
                        enabled: controller.canUpgrade(cardId),
                        onPressed: () => controller.upgradeCard(cardId),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _shortfall(
                          copies: copies,
                          needCopies: step.copies,
                          coins: profile.coins,
                          needCoins: step.coins,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Palette.uiTextDim,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The one line under the button: what is still missing, or that nothing is.
  ///
  /// Says the gap rather than the totals. "3 more cards to go" is what decides
  /// whether you go and play or go and open a chest; "7 / 10" makes the reader
  /// do that subtraction for themselves, and this reader cannot yet.
  static String _shortfall({
    required int copies,
    required int needCopies,
    required int coins,
    required int needCoins,
  }) {
    final cards = needCopies - copies;
    final gold = needCoins - coins;
    if (cards <= 0 && gold <= 0) return 'Ready to grow!';
    final parts = <String>[
      if (cards > 0) '$cards more ${cards == 1 ? 'card' : 'cards'}',
      if (gold > 0) '$gold more coins',
    ];
    return '${parts.join(' and ')} to go';
  }
}

/// The big lime button.
///
/// Grey and inert when you cannot afford it rather than hidden — the price is
/// the point of the page, and a button you have not earned yet is still
/// information about what earning it looks like.
class _GrowButton extends StatelessWidget {
  const _GrowButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: enabled ? onPressed : null,
    scale: 0.96,
    child: Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Palette.lime : Palette.uiBackground,
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled ? Panel.softShadow : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: Fonts.display,
            color: enabled ? Colors.white : Palette.uiTextDim,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    ),
  );
}

/// How close a card is to its next level.
///
/// Two different questions, and only one of them is live at a time. While
/// you are short, the useful thing is the count and how far along it is.
/// Once you can afford it, the count stops mattering — "21/2" is a fact
/// about the past — and the only thing worth saying is that you can act.
///
/// So a ready card loses its bar rather than filling it. Early on nearly
/// everything is affordable, and a full green bar under all twenty-one read
/// as a pattern in the page instead of as twenty-one invitations. The
/// orange label is the app's action colour and the only orange in the grid.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.level,
    required this.copies,
    required this.needed,
    required this.ready,
  });

  final int level;
  final int copies;
  final int? needed;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final target = needed;
    final maxed = target == null;
    final fraction = maxed ? 1.0 : (copies / target).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Lv $level',
              style: const TextStyle(
                color: Palette.uiText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (ready)
              // Lime, and the only lime on the page — it is the colour of
              // "getting there", and this is the one tile you can act on.
              // "Grow!" rather than "Level up": levelling is a game-systems
              // word, growing is something a seven-year-old has watched
              // happen.
              const Text(
                'Grow!',
                style: TextStyle(
                  fontFamily: Fonts.display,
                  color: Palette.lime,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              Text(
                maxed ? 'max' : '$copies/$target',
                style: const TextStyle(
                  color: Palette.uiTextDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        // Only while there is ground covered *and* ground still to cover.
        //
        // A bar that is always full is furniture, and so is one that is always
        // empty: on a fresh save every card sits at level 1 with no copies, so
        // twenty-one identical empty tracks were the last thing on every tile
        // and they said exactly what the "0/2" beside them already said. The
        // count carries it until there is something to draw.
        if (!ready && !maxed && copies > 0) ...[
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: Palette.uiTextDim.withValues(alpha: 0.22),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    heightFactor: 1,
                    child: const ColoredBox(color: Palette.uiTextDim),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
