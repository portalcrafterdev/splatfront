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
    final collection = data.cards.playable.toList()
      ..sort((a, b) => a.cost.compareTo(b.cost));

    final swapping = _swapping;
    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MetaHeader(
              title: 'Collection',
              profile: profile,
              subtitle: swapping == null
                  ? 'Tap a card in your deck to swap it out. Tap any other '
                        'card to level it up.'
                  : 'Now pick the card that replaces '
                        '${data.cards[swapping].name}.',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
            SectionHeading(
              swapping == null ? 'Your deck' : 'Swapping out',
              trailing: swapping == null ? '${deck.length} cards' : null,
            ),
            _grid(
              cards: [for (final id in deck) data.cards[id]],
              profile: profile,
              layout: layout,
              readyToUpgrade: controller.canUpgrade,
              copiesNeeded: (level) => data.upgrades.stepFrom(level)?.copies,
              highlight: _swapping,
              onTap: (card) => setState(
                () => _swapping = _swapping == card.id ? null : card.id,
              ),
            ),

            const SizedBox(height: 22),
            SectionHeading(
              'Every card',
              trailing: '${collection.length} in the game',
            ),
            _grid(
              cards: collection,
              profile: profile,
              layout: layout,
              readyToUpgrade: controller.canUpgrade,
              copiesNeeded: (level) => data.upgrades.stepFrom(level)?.copies,
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
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
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
    Set<String> dimmed = const {},
    String? highlight,
  }) {
    return GridView.count(
      crossAxisCount: layout.collectionColumns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.62,
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
    required this.onTap,
  });

  final CardModel card;
  final int level;
  final int copies;

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
                  child: CardTile(
                    card: card,
                    width: constraints.maxWidth - 6 - Panel.stroke * 2,
                  ),
                ),
                const SizedBox(height: 8),
                // The bare copy count used to sit under "Lv 1" as a lone
                // number, which read as a second level. What a player wants
                // to know here is one thing: how close is this to going up.
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
                        // A building's clock is the stat that decides how you
                        // use it, so it belongs on the same line.
                        '${card.isBuilding ? '  ·  ${card.unit!.lifetime.round()}s' : ''}',
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
            _CostRow(
              label: 'Cards',
              have: copies,
              need: step.copies,
            ),
            const SizedBox(height: 6),
            _CostRow(
              label: 'Coins',
              have: profile.coins,
              need: step.coins,
            ),
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
  const _CostRow({
    required this.label,
    required this.have,
    required this.need,
  });

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
        // Only while there is still ground to cover. A bar that is always
        // full is furniture.
        if (!ready && !maxed) ...[
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
