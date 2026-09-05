import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ads/ads.dart';
import '../../core/game_data.dart';
import '../../core/palette.dart';
import '../../core/save/player_profile.dart';
import '../../meta/chests.dart';
import '../../meta/profile_controller.dart';
import '../widgets/chest_opening.dart';
import '../widgets/meta_widgets.dart';
import '../widgets/motion.dart';

/// Chest slots: start one unlocking, wait it out, open it.
///
/// Only one chest unlocks at a time, and a win with every slot full earns
/// nothing — which is what gives the timers any weight.
class ChestScreen extends ConsumerStatefulWidget {
  const ChestScreen({super.key});

  @override
  ConsumerState<ChestScreen> createState() => _ChestScreenState();
}

class _ChestScreenState extends ConsumerState<ChestScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The countdown is the only thing on this screen that changes on its own.
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);
    final slots = controller.chestSlots;

    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Said as a sentence rather than as fragments joined with a
              // middle dot, which is filing-system voice, not a person's.
              MetaHeader(
                title: 'Chests',
                profile: profile,
                subtitle: slots > data.chests.initialSlots
                    ? 'You have $slots slots. One unlocks at a time.'
                    : 'You have $slots slots, and '
                          '${data.chests.unlockedSlots} once you reach '
                          '${data.chests.unlockAtTrophies} trophies.',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (var i = 0; i < slots; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _slotAt(i, profile, data, controller),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Win a match to earn a chest. With every slot full, a win '
                      'earns nothing — so keep one free.',
                      style: TextStyle(
                        color: Palette.uiTextDim,
                        fontSize: 12,
                        height: 1.4,
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

  /// One slot, filled or empty.
  ///
  /// The chest's type is read once, here, and captured. Opening removes the
  /// chest from the profile, so a callback that looked the type up again by
  /// index would be reading a list that had already changed under it.
  Widget _slotAt(
    int index,
    PlayerProfile profile,
    GameData data,
    ProfileController controller,
  ) {
    if (index >= profile.chests.length) return const _EmptySlot();

    final slot = profile.chests[index];
    final type = data.chests.byId(slot.typeId);

    return _FilledSlot(
      slot: slot,
      type: type,
      controller: controller,
      index: index,
      onOpened: (reward) => _showReward(reward, type.name),
      watching: _watching,
      onWatchAd: () => _watchToSkip(index),
    );
  }

  /// True while a rewarded ad is being fetched or is on screen.
  ///
  /// Held here rather than in the slot because the offer is disabled on
  /// *every* chest while one is running — two videos started from two rows
  /// would be two rewards for one watch.
  bool _watching = false;

  Future<void> _watchToSkip(int index) async {
    if (_watching) return;
    setState(() => _watching = true);
    try {
      final earned = await Ads.showRewarded();
      if (!mounted) return;
      // Only on `onUserEarnedReward`. Somebody who backed out of the video
      // early gets nothing, which is the whole contract of the format —
      // paying out on dismissal would be paying for nothing.
      if (earned) {
        ref.read(profileProvider.notifier).speedUpChest(index, Ads.chestSkip);
      } else {
        // Said plainly rather than silently doing nothing, because from the
        // player's side a button that does nothing is a broken button.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No ad available right now. Try again in a moment.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  /// Hands the reward to the opening animation.
  ///
  /// This used to be an alert dialog listing the contents, which told you
  /// what you got and made opening a chest feel like reading a receipt.
  void _showReward(ChestReward reward, String chestName) {
    showChestOpening(
      context,
      reward: reward,
      chestName: chestName,
      cards: ref.read(gameDataProvider).cards,
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) => Container(
    height: 88,
    decoration: BoxDecoration(
      color: Palette.uiSurface.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Palette.uiTextDim.withValues(alpha: 0.2)),
    ),
    alignment: Alignment.center,
    child: const Text(
      'EMPTY',
      style: TextStyle(
        color: Palette.uiTextDim,
        fontSize: 11,
        letterSpacing: 2,
      ),
    ),
  );
}

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.slot,
    required this.type,
    required this.controller,
    required this.index,
    required this.onOpened,
    required this.watching,
    required this.onWatchAd,
  });

  final ChestSlot slot;
  final ChestType type;
  final ProfileController controller;
  final int index;
  final void Function(ChestReward reward) onOpened;

  /// A rewarded ad is already running, from this row or another one.
  final bool watching;
  final VoidCallback onWatchAd;

  @override
  Widget build(BuildContext context) {
    final remaining = controller.remainingOn(slot);
    final ready = controller.isReady(slot);
    final somethingElseUnlocking =
        controller.isAnyChestUnlocking && !slot.isUnlocking;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.uiSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready
              ? Palette.accent
              : Palette.uiTextDim.withValues(alpha: 0.25),
          width: ready ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2,
                size: 34,
                color: ready ? Palette.accent : Palette.uiTextDim,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${type.name} chest',
                      style: const TextStyle(
                        color: Palette.uiText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ready
                          ? 'Ready'
                          : remaining == null
                          ? 'Takes ${formatDuration(type.duration)}'
                          : formatDuration(remaining),
                      style: TextStyle(
                        color: ready ? Palette.accent : Palette.uiTextDim,
                        fontSize: 12,
                        fontWeight: ready ? FontWeight.w800 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              _action(context, ready, somethingElseUnlocking),
            ],
          ),
          // Only while it is actually counting down. A sealed chest has not
          // started, so there is nothing to take off; a finished one is
          // already there to press.
          if (!ready && remaining != null && Ads.rewardedAvailable)
            _watchToSkip(remaining),
        ],
      ),
    );
  }

  /// The rewarded offer, on a chest that is counting down.
  ///
  /// Only on a *running* chest: a sealed one has not started yet, so there is
  /// nothing to take time off, and a finished one is already open to press.
  /// The chest timer is the only real time gate in this game, which is why it
  /// is the placement worth having.
  Widget _watchToSkip(Duration remaining) {
    final skip = Ads.chestSkip;
    // Says what the press will actually do. "Take 4 hours off" on a chest
    // with two minutes left would be nonsense, and "open now" on one with
    // eight hours left would be a lie — this is the only honest way to label
    // a flat reduction against timers that run from three minutes to eight
    // hours.
    final finishes = remaining <= skip;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: watching ? null : onWatchAd,
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: Text(
            finishes
                ? 'Watch an ad to open now'
                : 'Watch an ad  ·  −${formatDuration(skip)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Palette.info,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext context, bool ready, bool blocked) {
    if (ready) {
      return FilledButton(
        onPressed: () {
          final reward = controller.openChest(index);
          // The sound belongs to the animation, which fires it on the burst
          // rather than on the press.
          if (reward != null) onOpened(reward);
        },
        style: FilledButton.styleFrom(backgroundColor: Palette.accent),
        child: const Text('OPEN'),
      );
    }
    if (slot.isUnlocking) {
      return const SizedBox.shrink();
    }
    return FilledButton(
      // Only one chest unlocks at a time.
      onPressed: blocked ? null : () => controller.startUnlocking(index),
      style: FilledButton.styleFrom(
        backgroundColor: Palette.uiBackground,
        disabledBackgroundColor: Palette.uiBackground,
        foregroundColor: Palette.uiText,
      ),
      child: const Text('START'),
    );
  }
}
