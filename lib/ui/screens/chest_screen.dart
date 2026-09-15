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
import '../type.dart';
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
    final maxSlots = data.chests.unlockedSlots;

    // The first chest that can be opened right now, for the button at the
    // bottom. There is rarely more than one, because only one unlocks at a
    // time — but "rarely" is not "never", and a button has to mean something
    // exact.
    final readyIndex = profile.chests.indexWhere(controller.isReady);

    // A chest counting down, for the ad offer. Sealed chests have no time to
    // take off and finished ones are already open.
    final runningIndex = profile.chests.indexWhere(
      (c) => c.isUnlocking && !controller.isReady(c),
    );

    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MetaHeader(
                title: 'Chests',
                profile: profile,
                // Plain, and about what the player does rather than about how
                // many slots the save has. "You have 2 slots, and 4 once you
                // reach 400 trophies" is a database row read aloud.
                subtitle: slots >= maxSlots
                    ? 'Win a match to earn one. One opens at a time.'
                    : 'Win a match to earn one. '
                          '$slots boxes now, $maxSlots later.',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.92,
                      children: [
                        // Every slot the save will ever have, not just the
                        // ones it has now. The locked pair is the only thing
                        // on this screen that says more chests are coming,
                        // and a grid that grows from two tiles to four with
                        // no warning reads as a bug rather than a reward.
                        for (var i = 0; i < maxSlots; i++)
                          _slotAt(i, slots, profile, data, controller),
                      ],
                    ),
                    if (runningIndex >= 0 && Ads.rewardedAvailable) ...[
                      const SizedBox(height: 14),
                      _WatchToSkip(
                        remaining:
                            controller.remainingOn(
                              profile.chests[runningIndex],
                            ) ??
                            Duration.zero,
                        watching: _watching,
                        onPressed: () => _watchToSkip(runningIndex),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      readyIndex >= 0
                          ? 'Tap the box to see what is inside.'
                          : 'With every box full, winning earns nothing — so '
                                'keep one free.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Palette.uiTextDim,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              // The one loud object on the page, and only when there is
              // something for it to do. A permanently visible OPEN button
              // that is grey nine times out of ten teaches a child that the
              // biggest thing on the screen is usually a lie.
              if (readyIndex >= 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _OpenButton(
                    onPressed: () => _open(readyIndex, data, controller),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(int index, GameData data, ProfileController controller) {
    // The type is read *before* opening. Opening removes the chest from the
    // profile, so looking it up afterwards by the same index reads a list
    // that has already shifted under it.
    final type = data.chests.byId(
      ref.read(profileProvider).chests[index].typeId,
    );
    final reward = controller.openChest(index);
    // The sound belongs to the animation, which fires it on the burst rather
    // than on the press.
    if (reward != null) _showReward(reward, type.name);
  }

  /// One slot: filled, empty, or not yet unlocked.
  ///
  /// The chest's type is read once, here, and captured. Opening removes the
  /// chest from the profile, so a callback that looked the type up again by
  /// index would be reading a list that had already changed under it.
  Widget _slotAt(
    int index,
    int slots,
    PlayerProfile profile,
    GameData data,
    ProfileController controller,
  ) {
    if (index >= slots) {
      return _LockedSlot(atTrophies: data.chests.unlockAtTrophies);
    }
    if (index >= profile.chests.length) return const _EmptySlot();

    final slot = profile.chests[index];
    final type = data.chests.byId(slot.typeId);

    return _FilledSlot(
      slot: slot,
      type: type,
      controller: controller,
      index: index,
      onOpen: () => _open(index, data, controller),
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

/// The shared shape of a slot: a square tile with something in the middle,
/// a word, and a line under it.
///
/// Four states share it — filled, empty, locked, ready — and they differ only
/// in fill, edge and contents. Drawn rather than faded: an `Opacity` over a
/// whole tile takes the label down with the art, and a label a child cannot
/// read is a slot that says nothing at all.
class _SlotShell extends StatelessWidget {
  const _SlotShell({
    required this.body,
    required this.title,
    required this.line,
    this.titleColour = Palette.uiText,
    this.edge,
    this.dashed = false,
    this.onTap,
  });

  final Widget body;
  final String title;
  final String line;
  final Color titleColour;
  final Color? edge;
  final bool dashed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: dashed
            ? Palette.uiBackground
            : Palette.uiSurfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: edge == null
            ? null
            : Border.all(color: edge!, width: 2.5),
        boxShadow: dashed ? null : Panel.softShadow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: Center(child: body)),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Fonts.display,
              color: titleColour,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.uiTextDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return onTap == null ? tile : PressScale(onTap: onTap, child: tile);
  }
}

/// A slot with no chest in it yet.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) => _SlotShell(
    dashed: true,
    titleColour: Palette.uiTextDim,
    body: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Palette.uiTextDim.withValues(alpha: 0.35),
          width: 2.5,
        ),
      ),
    ),
    title: 'Empty',
    line: 'Win a match',
  );
}

/// A slot the save has not earned yet.
///
/// Shown alongside the ones that exist rather than left off the grid. It is
/// the only thing on this screen that says more boxes are coming, and a grid
/// that silently grows from two tiles to four reads as a glitch rather than
/// as a reward.
class _LockedSlot extends StatelessWidget {
  const _LockedSlot({required this.atTrophies});

  final int atTrophies;

  @override
  Widget build(BuildContext context) => _SlotShell(
    dashed: true,
    titleColour: Palette.uiTextDim,
    body: Icon(
      Icons.lock_rounded,
      size: 34,
      color: Palette.uiTextDim.withValues(alpha: 0.5),
    ),
    title: 'Locked',
    line: '$atTrophies trophies',
  );
}

/// A slot with a chest in it: sealed, filling, or ready.
class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.slot,
    required this.type,
    required this.controller,
    required this.index,
    required this.onOpen,
  });

  final ChestSlot slot;
  final ChestType type;
  final ProfileController controller;
  final int index;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ready = controller.isReady(slot);
    final remaining = controller.remainingOn(slot);
    final blocked = controller.isAnyChestUnlocking && !slot.isUnlocking;

    // How full the ring is. A sealed chest reads empty, a finished one full,
    // and one in flight is measured against its own type's duration rather
    // than against a fixed scale — a three-minute Wood and an eight-hour
    // Magic both fill their whole ring.
    final total = type.duration.inSeconds;
    final progress = ready
        ? 1.0
        : remaining == null || total <= 0
        ? 0.0
        : 1 - (remaining.inSeconds / total).clamp(0.0, 1.0);

    return _SlotShell(
      edge: ready ? Palette.gold : null,
      titleColour: ready ? Palette.gold : Palette.uiText,
      body: ProgressRing(
        value: progress,
        colour: ready ? Palette.gold : Palette.lime,
        child: Icon(
          Icons.inventory_2_rounded,
          size: 28,
          color: ready ? Palette.gold : Palette.uiTextDim,
        ),
      ),
      // The chest's own name, in every state. The mockup put "Ready!" here,
      // which loses the one fact that decides whether this is worth walking
      // over for — a Wood and a Magic are the same picture and very
      // different rewards. Ready is carried by the gold ring, the gold edge
      // and the line underneath, none of which had to borrow the name's
      // space to say it.
      title: '${type.name} chest',
      // No digits anywhere. "2h 41m" is two units, base sixty, and a sense of
      // how long an hour is — the ring already answers the only question
      // being asked, which is how much is left.
      line: ready
          ? 'Tap to open!'
          : !slot.isUnlocking
          ? (blocked ? 'Wait your turn' : 'Tap to start')
          : progress > 0.75
          ? 'Almost there!'
          : progress > 0.4
          ? 'Halfway'
          : 'Just started',
      onTap: ready
          ? onOpen
          : slot.isUnlocking || blocked
          ? null
          : () => controller.startUnlocking(index),
    );
  }
}

/// The rewarded offer, for whichever chest is counting down.
///
/// One row under the grid rather than a button on each tile: only one chest
/// unlocks at a time, so there is only ever one chest this could apply to,
/// and four tiles each carrying their own video button would make the page
/// an advert with some chests on it.
class _WatchToSkip extends StatelessWidget {
  const _WatchToSkip({
    required this.remaining,
    required this.watching,
    required this.onPressed,
  });

  final Duration remaining;
  final bool watching;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skip = Ads.chestSkip;
    // Says what the press will actually do. "Take 4 hours off" on a chest
    // with two minutes left would be nonsense, and "open now" on one with
    // eight hours left would be a lie — this is the only honest way to label
    // a flat reduction against timers running from three minutes to eight
    // hours.
    final finishes = remaining <= skip;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: watching ? null : onPressed,
        icon: const Icon(Icons.play_circle_outline, size: 18),
        label: Text(
          finishes ? 'Watch an ad to open now' : 'Watch an ad to hurry it up',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Palette.info,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// The gold button, on screen only while a chest is actually ready.
class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onPressed,
    scale: 0.96,
    child: Semantics(
      button: true,
      label: 'Open the chest',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.gold,
          borderRadius: BorderRadius.circular(18),
          boxShadow: Panel.softShadow,
        ),
        child: const Text(
          'OPEN IT!',
          style: TextStyle(
            fontFamily: Fonts.display,
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    ),
  );
}
