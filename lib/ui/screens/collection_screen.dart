import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game_data.dart';
import '../../core/palette.dart';
import '../../core/save/player_profile.dart';
import '../../game/cards/card_model.dart';
import '../../meta/profile_controller.dart';
import '../widgets/card_tile.dart';
import '../widgets/meta_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/responsive.dart';

/// Collection and deck builder.
///
/// Tap a card in the deck to pick it, then tap one in the collection to swap
/// it in. Tapping a card on its own opens its upgrade sheet.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  /// The deck slot waiting to be replaced, if any.
  String? _swapping;

  @override
  Widget build(BuildContext context) {
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

    final swapping = _swapping;
    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MetaHeader(
                title: 'Collection',
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
                    ? 'Now pick the card that replaces '
                          '${data.cards[swapping].name}.'
                    : canSwap
                    ? 'Tap a card in your deck to swap it out. Tap any other '
                          'card to level it up.'
                    : 'Tap a card to level it up. Swapping opens once you own '
                          'a card outside your deck.',
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
                      onTap: (card) {
                        // With nothing outside the deck to bring in, arming a
                        // swap is a dead end dressed up as a selection: the
                        // header would ask you to pick a replacement and there
                        // would be nothing on the page to pick. Levelling up
                        // is the one thing you can actually do to a card you
                        // already own, so that is what a tap does.
                        if (!canSwap) {
                          _showUpgradeSheet(card);
                          return;
                        }
                        setState(
                          () => _swapping = _swapping == card.id
                              ? null
                              : card.id,
                        );
                      },
                    ),

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
          ),
      ],
    );
  }

  void _showUpgradeSheet(CardModel card) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.uiSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _UpgradeSheet(cardId: card.id),
    );
  }
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                    border: Border.all(
                      color: Palette.outline,
                      width: Panel.stroke,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Palette.outlineShadow,
                        offset: Offset(0, Panel.lift),
                      ),
                    ],
                  ),
                  child: _maybeLocked(
                    CardTile(
                      card: card,
                      width: constraints.maxWidth - 6 - Panel.stroke * 2,
                    ),
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

/// Upgrade one card: what it costs, and whether it can be paid for.
class _UpgradeSheet extends ConsumerWidget {
  const _UpgradeSheet({required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);

    final level = profile.levelOf(cardId);
    final copies = profile.copiesOf(cardId);
    final step = data.upgrades.stepFrom(level);
    final card = data.cards.at(cardId, level);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CardTile(card: card, width: 70),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      style: const TextStyle(
                        color: Palette.uiText,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Level $level',
                      style: const TextStyle(
                        color: Palette.info,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (card.isUnit)
                      Text(
                        '${card.unit!.hp.round()} HP  ·  '
                        '${card.unit!.damage.round()} dmg'
                        // A building on a clock says how long it has; one
                        // without says so, because "stands until destroyed"
                        // is the stat that decides how you use it. Reading
                        // the lifetime blindly printed "0s" on a building
                        // that in fact never expires.
                        '${card.isBuilding ? '  ·  ${card.unit!.isTemporary ? '${card.unit!.lifetime.round()}s' : 'until destroyed'}' : ''}',
                        style: const TextStyle(
                          color: Palette.uiTextDim,
                          fontSize: 12,
                        ),
                      ),
                    if (card.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          card.note,
                          style: const TextStyle(
                            color: Palette.uiTextDim,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (step == null)
            const Text(
              'Maximum level.',
              style: TextStyle(color: Palette.uiTextDim, fontSize: 13),
            )
          else ...[
            _CostRow(label: 'Cards', have: copies, need: step.copies),
            const SizedBox(height: 6),
            _CostRow(label: 'Coins', have: profile.coins, need: step.coins),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: controller.canUpgrade(cardId)
                    ? () {
                        controller.upgradeCard(cardId);
                        Navigator.of(context).pop();
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.accent,
                  disabledBackgroundColor: Palette.uiBackground,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('UPGRADE TO ${step.level}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({required this.label, required this.have, required this.need});

  final String label;
  final int have;
  final int need;

  @override
  Widget build(BuildContext context) {
    final enough = have >= need;
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Palette.uiTextDim, fontSize: 12),
        ),
        const Spacer(),
        Text(
          '$have / $need',
          style: TextStyle(
            color: enough ? Palette.success : Palette.danger,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
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
              const Text(
                'Level up',
                style: TextStyle(
                  color: Palette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
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
