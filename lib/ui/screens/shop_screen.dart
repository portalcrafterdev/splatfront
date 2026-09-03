import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game_data.dart';
import '../../core/palette.dart';
import '../../game/cards/card_model.dart';
import '../../meta/profile_controller.dart';
import '../../meta/quests.dart';
import '../widgets/card_tile.dart';
import '../widgets/meta_widgets.dart';
import '../widgets/motion.dart';

/// Coins only. No paid currency, no ads, no IAP.
///
/// The daily offers are drawn from the date, the same way quests are, so the
/// shop is stable through the day without needing to be saved.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);

    final offers = _offersFor(QuestConfig.dayKey(DateTime.now()), controller);

    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // The standing explanation belongs here, next to the title, and
              // not as a paragraph after the last row where it read as a
              // disclaimer nobody reaches.
              MetaHeader(
                title: 'Shop',
                profile: profile,
                subtitle:
                    'Four card deals, new every day. Coins come from '
                    'chests and quests — nothing here costs real money.',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final offer in offers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OfferRow(
                          card: data.cards[offer.cardId],
                          copies: offer.copies,
                          cost: offer.copies * data.shopCoinsPerCopy,
                          short:
                              (offer.copies * data.shopCoinsPerCopy) -
                              profile.coins,
                          onBuy: () =>
                              controller.buyCopies(offer.cardId, offer.copies),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Deterministic from the day, so the shop does not reshuffle on rebuild.
  List<_Offer> _offersFor(String day, ProfileController controller) {
    // Salted so the shop does not mirror the quest draw for the same day.
    final random = math.Random(Object.hash(day, 'shop'));
    // Unlocked cards only. Selling copies of a card the player cannot put in
    // a deck is selling them nothing, and it spends the shop slot that could
    // have carried something they can use today.
    final data = controller.data;
    final pool = controller.unlockedCards.toList();
    if (pool.isEmpty) return const [];

    final picked = <_Offer>[];
    final used = <String>{};
    var guard = 0;

    while (picked.length < data.shop.dailyOfferCount && guard++ < 100) {
      final card = pool[random.nextInt(pool.length)];
      if (!used.add(card.id)) continue;
      final span = data.shop.copiesMax - data.shop.copiesMin;
      picked.add(
        _Offer(
          cardId: card.id,
          copies: data.shop.copiesMin + random.nextInt(span + 1),
        ),
      );
    }
    return picked;
  }
}

class _Offer {
  const _Offer({required this.cardId, required this.copies});
  final String cardId;
  final int copies;
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.card,
    required this.copies,
    required this.cost,
    required this.short,
    required this.onBuy,
  });

  final CardModel card;
  final int copies;
  final int cost;

  /// Coins missing, zero or less when it can be bought.
  ///
  /// A greyed price told you that you could not buy it but not how far off
  /// you were, which is the one thing that decides whether you wait or go
  /// and play a match.
  final int short;
  final VoidCallback onBuy;

  bool get affordable => short <= 0;

  @override
  // A Panel, not a flat fill. Near-white on cream has no edge of its own, so
  // these rows read as slightly lighter page rather than as things sitting on
  // it — the same failure the menus already fixed once.
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(10),
    child: Row(
      children: [
        CardTile(card: card, width: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.name,
                style: const TextStyle(
                  color: Palette.uiText,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'x$copies cards',
                style: const TextStyle(color: Palette.uiTextDim, fontSize: 12),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: affordable ? onBuy : null,
          style: FilledButton.styleFrom(
            backgroundColor: Palette.accent,
            disabledBackgroundColor: Palette.uiBackground,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on, size: 14),
              const SizedBox(width: 5),
              Text(affordable ? '$cost' : '$short short'),
            ],
          ),
        ),
      ],
    ),
  );
}
