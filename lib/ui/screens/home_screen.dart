import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game_data.dart';
import '../../core/audio.dart';
import '../../core/palette.dart';
import '../../core/save/player_profile.dart';
import '../../game/arena/arena_layout.dart';
import '../../game/splatfront_game.dart';
import '../../meta/profile_controller.dart';
import '../../meta/quests.dart';
import '../widgets/card_tile.dart';
import '../widgets/meta_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/responsive.dart';
import 'battle_screen.dart';
import 'campaign_screen.dart';
import 'chest_screen.dart';

/// Home: chests, player card, daily quests and the button that starts a
/// match.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Back to the calm loop whenever Home is on screen, including on the
    // way out of a match.
    Audio.playMusic(Track.menu);
    // Roll today's quests in, if the day has turned over since last launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(profileProvider.notifier).refreshQuests();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          child: ResponsiveBuilder(
            builder: (context, layout) {
              const left = _PlayerPane();
              const right = _QuestPane();
              // Clears the bottom bar. At 16 the last line of the trophy road
              // ended up underneath it and was cut in half.
              const bottomGap = SizedBox(height: 28);

              if (layout.isWide) {
                return const Row(
                  children: [
                    Expanded(child: SingleChildScrollView(child: left)),
                    Expanded(child: right),
                  ],
                );
              }
              // One scroll for the whole page rather than a fixed block with a
              // scrolling list under it. Home outgrew the screen the moment it
              // started showing your deck, and a fixed column does not overflow
              // gracefully — it throws in debug and silently clips in release.
              //
              // The minimum height plus centre alignment is what shares out
              // the leftover space when the page is *shorter* than the screen.
              // Home lost a whole row when the difficulty picker went, and a
              // top-aligned column put every pixel it saved into one dead band
              // above the nav bar. Split evenly it reads as breathing room at
              // both ends instead. A page taller than the screen exceeds the
              // minimum, the alignment stops mattering, and it scrolls exactly
              // as before.
              return LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        left,
                        _QuestPane(fillsHeight: false),
                        bottomGap,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlayerPane extends ConsumerWidget {
  const _PlayerPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);
    final nextLevel = profile.campaignNextLevel;

    // Trophies pick the arena, exactly as section 10 lays out.
    final arena = data.arenaFor(profile.trophies);

    final done = nextLevel > data.campaign.levelCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Entrance(
            child: _TopBar(
              profile: profile,
              arenaNumber: data.arenas.indexOf(arena) + 1,
              arenaName: arena.name,
              nextAt: data.nextArenaThreshold(profile.trophies),
            ),
          ),
          const SizedBox(height: 14),
          // The hero, and the only loud thing on the page.
          //
          // Battle plays the level you are up to. There is no difficulty
          // picker any more: with one progression, the level number *is* the
          // difficulty, and a free-play match that fed nothing was the odd
          // one out — it paid trophies and chests without ever advancing the
          // thing the rest of the app is about.
          Entrance(
            index: 1,
            child: _NextLevelCard(
              level: done ? data.campaign.levelCount : nextLevel,
              // The level's own name, not a difficulty word. The tiers are
              // gone, and "Easy" beside a level number told the player
              // nothing the number did not already.
              name: data.campaign.nameFor(
                done ? data.campaign.levelCount : nextLevel,
              ),
              complete: done,
              onPressed: () => startCampaignLevel(context, ref, nextLevel),
            ),
          ),
          const SizedBox(height: 14),
          Entrance(
            index: 2,
            child: _ChestRow(profile: profile, slots: controller.chestSlots),
          ),
          // Debug builds only. These are development tools — a paint harness
          // and a unit spawner — and they have no business on a home screen
          // somebody is actually playing. The screens themselves stay: the
          // widget suite still drives the app through them, and tests run in
          // debug, so this hides them from the player without taking the tool
          // away from the next person who needs it.
          if (kDebugMode) ...[
            const SizedBox(height: 10),
            _SandboxLinks(data: data, arena: arena),
          ],
        ],
      ),
    );
  }
}

/// The chest slots on Home.
///
/// Every slot says what it is waiting for, because "a chest arrived and it
/// will not open" is exactly what a chest looks like when it is sealed and
/// nothing on screen mentions that you have to start its timer first. A
/// sealed chest now says TAP TO START, a running one shows its countdown,
/// and a finished one says READY in the team colour.
class _ChestRow extends ConsumerStatefulWidget {
  const _ChestRow({required this.profile, required this.slots});

  final PlayerProfile profile;
  final int slots;

  @override
  ConsumerState<_ChestRow> createState() => _ChestRowState();
}

class _ChestRowState extends ConsumerState<_ChestRow> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The countdown is the only thing on Home that moves on its own.
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
    final controller = ref.read(profileProvider.notifier);
    final data = ref.watch(gameDataProvider);

    return GestureDetector(
      // Opaque, so the gaps between the tiles are tappable too rather than
      // dropping the tap through to nothing.
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ChestScreen())),
      // With nothing to show, a row of tall empty boxes spends the best space
      // on the screen — the strip directly above the battle button — saying
      // "EMPTY", which the player can already see. One short line in its
      // place says the thing they actually need, which is where chests come
      // from, and hands the height back to the button.
      child: widget.profile.chests.isEmpty
          ? _noChests()
          : Row(
              children: [
                for (var i = 0; i < widget.slots; i++)
                  Expanded(
                    child: i < widget.profile.chests.length
                        ? _slot(
                            widget.profile.chests[i],
                            data.chests
                                .byId(widget.profile.chests[i].typeId)
                                .name,
                            controller,
                          )
                        : _empty(),
                  ),
              ],
            ),
    );
  }

  /// The whole row, when there is not a single chest to put in it.
  Widget _noChests() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Palette.uiSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Palette.uiTextDim.withValues(alpha: 0.25),
        width: 1,
      ),
    ),
    child: Row(
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: 20,
          color: Palette.uiTextDim.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'No chests yet. Win a match to earn one.',
            style: TextStyle(color: Palette.uiTextDim, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _slot(ChestSlot slot, String name, ProfileController controller) {
    final ready = controller.isReady(slot);
    final remaining = controller.remainingOn(slot);
    final label = ready
        ? 'READY'
        : remaining == null
        ? 'TAP TO START'
        : formatDuration(remaining);

    return _box(
      border: ready ? Palette.accent : Palette.accent.withValues(alpha: 0.6),
      borderWidth: ready ? 2 : 1,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2,
            color: ready ? Palette.accent : Palette.uiText,
            size: 22,
          ),
          const SizedBox(height: 3),
          Text(
            name,
            style: const TextStyle(color: Palette.uiTextDim, fontSize: 11),
          ),
          FittedBox(
            child: Text(
              label,
              style: TextStyle(
                color: ready ? Palette.accent : Palette.uiText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A spare slot sitting beside a full one.
  ///
  /// Says what fills it rather than that it is empty, which the gap already
  /// says. Tracked-out capitals are gone with it: "EMPTY" was a shout that
  /// carried no information.
  Widget _empty() => _box(
    border: Palette.uiTextDim.withValues(alpha: 0.2),
    borderWidth: 1,
    child: const Center(
      child: Text(
        'Win a match',
        textAlign: TextAlign.center,
        style: TextStyle(color: Palette.uiTextDim, fontSize: 11),
      ),
    ),
  );

  Widget _box({
    required Color border,
    required double borderWidth,
    required Widget child,
  }) => Container(
    height: 78,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      // A breath of gold rather than a wash of it: this is the rewards
      // corner and a row of plain white rectangles gave it no identity, but
      // at 0.3 the blend came out tan — a pair of beige boxes in a column
      // that is otherwise teal and white, and beige is not one of the app's
      // colours. At 0.10 it reads as warm paper and the gold on the icon and
      // the timer is left to do the actual signalling.
      color: border == Palette.uiTextDim.withValues(alpha: 0.2)
          ? Palette.uiSurface
          : Color.alphaBlend(
              Palette.gold.withValues(alpha: 0.10),
              Palette.uiSurfaceHigh,
            ),
      borderRadius: BorderRadius.circular(16),
      // The caller's colour only decides how strong the edge is; the edge
      // itself is always the dark outline, or the tile loses its shape.
      border: Border.all(
        color: border == Palette.uiTextDim.withValues(alpha: 0.2)
            ? Palette.outline.withValues(alpha: 0.35)
            : Palette.outline,
        width: Panel.stroke,
      ),
      boxShadow: const [
        BoxShadow(color: Palette.outlineShadow, offset: Offset(0, Panel.lift)),
      ],
    ),
    child: child,
  );
}

/// Today's three objectives, and the coins for finishing them.
class _QuestPane extends ConsumerWidget {
  const _QuestPane({this.fillsHeight = true});

  /// True when it owns the space below it and scrolls inside it, which is the
  /// tablet layout. False when the page above it scrolls instead, and it has
  /// to size to its own content or the two scrollables fight.
  final bool fillsHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);
    final quests = controller.todaysQuests;
    final done = quests
        .where((q) => controller.progressFor(q.id).progress >= q.target)
        .length;
    final slotsAt = ref.watch(gameDataProvider).chests.unlockAtTrophies;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sentence case with the count, like every other heading in the
          // app. Three tracked-out capitalised eyebrows were the loudest
          // thing on a page whose loudest thing should be BATTLE.
          SectionHeading(
            'Daily quests',
            trailing: quests.isEmpty
                ? null
                : done == quests.length
                ? 'all done'
                : '$done of ${quests.length}',
          ),
          _QuestList(
            fillsHeight: fillsHeight,
            children: [
              // One tile holding all three rather than three tiles.
              //
              // Each quest used to be its own outlined block with its own
              // hard shadow and a 16dp gap to clear it, which spent well over
              // a third of the page on three short lines of text. They are
              // one group — the heading above already says so — and a tile is
              // what does grouping in this app.
              Entrance(
                index: 3,
                child: Panel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, quest) in quests.indexed) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Palette.uiTextDim.withValues(alpha: 0.16),
                          ),
                        _QuestRow(
                          quest: quest,
                          progress: controller.progressFor(quest.id),
                          onClaim: () => controller.claimQuest(quest.id),
                        ),
                      ],
                      if (quests.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            'No quests today.',
                            style: TextStyle(
                              color: Palette.uiTextDim,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // What trophies actually buy.
              //
              // This used to promise that the trophy road unlocked Arenas 2,
              // 3 and 4 — and it does not, not any more. The campaign cycles
              // through all four arenas inside its first hundred levels
              // whatever your trophy count is, so that line was describing a
              // reward the player had already been given. Chest slots are the
              // one thing still gated on trophies, so that is what it says.
              Text(
                profile.trophies >= slotsAt
                    ? 'All four chest slots are open. Trophies now just '
                          'track how far you have come.'
                    : 'Chest slots go from two to four at '
                          '$slotsAt trophies. You have '
                          '${profile.trophies}.',
                style: const TextStyle(
                  color: Palette.uiTextDim,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              const _NextCard(),
            ],
          ),
        ],
      ),
    );
  }
}

/// The card the campaign hands over next, and how far off it is.
///
/// This sits where the page used to simply run out. It is not filler: cards
/// now arrive by clearing levels, so "what am I playing towards" is a real
/// question the home screen was not answering anywhere. It also closes the
/// loop the battle button opens — that button says which level is next, this
/// says what beating a few of them is worth.
class _NextCard extends ConsumerWidget {
  const _NextCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);
    final campaign = data.campaign;

    final locked = data.cards.playable
        .where((c) => !controller.isCardUnlocked(c.id))
        .toList();
    if (locked.isEmpty) return const _AllCardsCollected();

    locked.sort(
      (a, b) => (campaign.unlockLevelFor(a.id) ?? 0).compareTo(
        campaign.unlockLevelFor(b.id) ?? 0,
      ),
    );
    final card = locked.first;
    final at = campaign.unlockLevelFor(card.id) ?? 0;
    final away = at - profile.campaignCleared;

    return Panel(
      child: Row(
        children: [
          // The same light mount the Collection gives every card. A CardTile
          // is drawn against the dark hud* set, so on a pale page it reads as
          // a hole punched in the paper without one.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Palette.uiSurfaceHigh,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Palette.outline, width: Panel.stroke),
              boxShadow: const [
                BoxShadow(
                  color: Palette.outlineShadow,
                  offset: Offset(0, Panel.lift),
                ),
              ],
            ),
            child: CardTile(card: card, width: 62),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Next card',
                  style: TextStyle(
                    color: Palette.uiTextDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Palette.uiText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // The distance, not the destination. "Level 12" is a fact
                  // about the ladder; "2 levels away" is a fact about you,
                  // and it is the one that decides whether you play now.
                  away <= 1
                      ? 'Win the next level to unlock it'
                      : '$away levels away  ·  level $at',
                  style: const TextStyle(
                    color: Palette.uiTextDim,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the slot says once there is nothing left to unlock.
class _AllCardsCollected extends ConsumerWidget {
  const _AllCardsCollected();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final total = data.campaign.levelCount * 3;

    return Panel(
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: Palette.gold, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'All ${data.cards.playable.length} cards collected. '
              '${profile.campaignTotalStars} of $total stars.',
              style: const TextStyle(
                color: Palette.uiText,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({
    required this.quest,
    required this.progress,
    required this.onClaim,
  });

  final Quest quest;
  final QuestProgress progress;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final done = progress.progress >= quest.target;
    final fraction = (progress.progress / quest.target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          // The state, as a stripe rather than as a wash over the whole tile.
          //
          // These were three lavender blocks — `info` at 18% on white — and
          // between them they were the loudest thing on the page, on a screen
          // whose loudest thing should be the Battle card. Lavender is also
          // nowhere else in the app, so the bottom half of Home read as a
          // different product from the top half. A 4dp stripe says the same
          // thing in the space it deserves.
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: done ? Palette.success : Palette.info,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        quest.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // Struck through is already the signal that it is
                          // done; dimming it as well left the text hard to
                          // read, and a quest you cannot read is a quest you
                          // cannot check.
                          color: progress.claimed
                              ? Palette.uiText.withValues(alpha: 0.72)
                              : Palette.uiText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          decoration: progress.claimed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // The count sits on the same line as the objective now.
                    // Under the bar it was a third line of type per quest,
                    // and three quests were paying nine lines for six facts.
                    Text(
                      '${progress.progress} / ${quest.target}',
                      style: const TextStyle(
                        color: Palette.uiTextDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  // Tweened, so finishing an objective fills the bar rather
                  // than teleporting it. Finite: it settles at the value and
                  // stops, so it cannot hang a pumpAndSettle.
                  child: _AnimatedBar(
                    value: fraction,
                    minHeight: 5,
                    backgroundColor: Palette.uiBackground,
                    valueColor: AlwaysStoppedAnimation(
                      done ? Palette.success : Palette.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (progress.claimed)
            const SizedBox(
              width: 44,
              child: Icon(Icons.check, color: Palette.success, size: 18),
            )
          else
            SizedBox(
              width: 44,
              child: _ClaimChip(
                coins: quest.coins,
                ready: done,
                onClaim: onClaim,
              ),
            ),
        ],
      ),
    );
  }
}

/// What a quest pays, and the button it becomes once you have earned it.
///
/// A quest you have not finished still has to show what it is worth, so this
/// is never blank — it just stops looking pressable. Material's disabled grey
/// on a pale tile left the number as a smudge, so the unearned state is drawn
/// rather than dimmed: the page colour, the standard outline, dim ink.
class _ClaimChip extends StatelessWidget {
  const _ClaimChip({
    required this.coins,
    required this.ready,
    required this.onClaim,
  });

  final int coins;
  final bool ready;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ready ? Palette.accent : Palette.uiBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: ready
              ? Palette.outline
              : Palette.uiTextDim.withValues(alpha: 0.35),
          width: ready ? 2 : 1.5,
        ),
        boxShadow: ready
            ? const [
                BoxShadow(color: Palette.accentShade, offset: Offset(0, 2.5)),
              ]
            : null,
      ),
      child: Text(
        '$coins',
        style: TextStyle(
          color: ready ? Colors.white : Palette.uiTextDim,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    return ready ? PressScale(onTap: onClaim, child: chip) : chip;
  }
}

class _SandboxLinks extends StatelessWidget {
  const _SandboxLinks({required this.data, required this.arena});

  final GameData data;
  final ArenaLayout arena;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BattleScreen(
              layout: arena,
              cards: data.cards,
              sandbox: SandboxMode.paint,
            ),
          ),
        ),
        child: const Text(
          'Paint test',
          style: TextStyle(color: Palette.uiTextDim, fontSize: 11),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BattleScreen(
              layout: arena,
              cards: data.cards,
              sandbox: SandboxMode.units,
            ),
          ),
        ),
        child: const Text(
          'Unit sandbox',
          style: TextStyle(color: Palette.uiTextDim, fontSize: 11),
        ),
      ),
    ],
  );
}

/// The screen's one loud object: the board you are about to fight over, the
/// level number that is now the whole difficulty curve, and the button.
///
/// It replaced a flat teal bar that said BATTLE. The bar worked, but it sat
/// under an identical teal band carrying the title, so the page led with two
/// slabs of the same colour and weight and neither won. More to the point, a
/// screen for a game about painting ground had no ground on it anywhere: the
/// page could have belonged to a fitness tracker.
///
/// So the board came onto the page. The preview is the real start state from
/// section 3 — a straight 50/50 split, the opponent holding the top and the
/// player the bottom, meeting along the middle row — drawn in whole cells,
/// because that is how the paint layer actually stamps. It is the one place
/// team colour is allowed outside the arena, and section 14 names the reason:
/// without the board a menu is a generic mobile skin.
class _NextLevelCard extends StatelessWidget {
  const _NextLevelCard({
    required this.level,
    required this.name,
    required this.complete,
    required this.onPressed,
  });

  final int level;
  final String name;

  /// Every level cleared. The card still shows a board and still plays, but
  /// it stops promising a level that is not there.
  final bool complete;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onPressed,
    // Deeper than a tile: this is the one control the whole screen is built
    // around, and it should feel like it takes a real push.
    scale: 0.97,
    child: Semantics(
      button: true,
      label: 'BATTLE',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.outline, width: 3),
          boxShadow: const [
            BoxShadow(color: Palette.outlineShadow, offset: Offset(0, 6)),
          ],
        ),
        // The border draws on the outside edge, so the board has to be
        // clipped to the inner radius or its corners square off over it.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 132,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // CustomPaint does not clip, and the frontier steps run to
                    // the full width. The ClipRRect above is what holds it in.
                    CustomPaint(
                      painter: _BoardPreviewPainter(seed: level),
                      isComplex: true,
                      willChange: false,
                    ),
                    // The board is mid-tone red and blue, and white text on
                    // either is thin. A dark gradient rising from the bottom
                    // gives the two lines a ground of their own without
                    // dimming the paint they sit on.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xB80B1512), Color(0x000B1512)],
                          stops: [0, 0.55],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              complete ? 'CAMPAIGN CLEARED' : 'LEVEL $level',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // The footer is the button. Separated from the board by the same
              // heavy line every other edge in the app uses, so the card reads
              // as one object with a control on it rather than two stacked
              // rectangles.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Palette.accent,
                  border: Border(
                    top: BorderSide(color: Palette.outline, width: 3),
                  ),
                ),
                child: const Text(
                  'BATTLE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The arena at kick-off, in miniature.
///
/// Cell-stepped rather than smooth, and that is the honest shape: the paint
/// layer claims whole grid cells edge to edge with no blur, so a soft wave
/// here would be a picture of a game we are not shipping. The frontier is
/// dead level — section 3's straight 50/50 split — with a cell of jitter
/// either way so it reads as painted rather than as a ruled line.
///
/// Deterministic from the level number: the same level always draws the same
/// board, so this never repaints and never flickers under a rebuild.
class _BoardPreviewPainter extends CustomPainter {
  const _BoardPreviewPainter({required this.seed});

  final int seed;

  /// Columns across the board. The real grid is 64 wide, which at this size
  /// would be hairlines; this keeps a cell big enough to read as a tile.
  ///
  /// Raised from 18 because a step is a whole cell, so a wide cell is a tall
  /// step: at 18 columns a single cell was a seventh of the board's height and
  /// the frontier came out as a row of towers rather than as an edge.
  static const int _columns = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _columns;
    final rows = (size.height / cell).ceil();
    final mid = rows / 2;

    final paint = Paint();
    canvas.drawRect(Offset.zero & size, paint..color = Palette.arenaFloor);

    // One deterministic step per column, from a cheap integer hash. No
    // Random: this has to give the same board on every repaint.
    for (var c = 0; c < _columns; c++) {
      final h = (seed * 73856093) ^ (c * 19349663);
      // Weighted toward no step at all: three columns in five sit exactly on
      // the middle row and the rest take a single cell either way. An even
      // three-way roll put a step on two columns out of every three, which is
      // not a frontier — it is noise, and it read as a bar chart. Kick-off is
      // a straight 50/50 split, so the line wants to be level with a few
      // bites out of it.
      final roll = (h.abs() >> 3) % 5;
      final step = roll == 0
          ? -1
          : roll == 4
          ? 1
          : 0;
      final split = (mid + step) * cell;
      final x = c * cell;

      canvas
        ..drawRect(Rect.fromLTWH(x, 0, cell + 0.5, split), paint
          ..color = Palette.red)
        ..drawRect(
          Rect.fromLTWH(x, split, cell + 0.5, size.height - split),
          paint..color = Palette.blue,
        );
    }

    // The grid the board is scored on, faint over the top, so the paint reads
    // as tiles claimed rather than as two flat blocks of colour.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x14000000);
    for (var c = 1; c < _columns; c++) {
      canvas.drawLine(
        Offset(c * cell, 0),
        Offset(c * cell, size.height),
        line,
      );
    }
    for (var r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * cell), Offset(size.width, r * cell), line);
    }
  }

  @override
  bool shouldRepaint(_BoardPreviewPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({
    required this.value,
    required this.minHeight,
    required this.backgroundColor,
    required this.valueColor,
  });

  final double value;
  final double minHeight;
  final Color backgroundColor;
  final Animation<Color?> valueColor;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value),
    duration: const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
    builder: (context, t, _) => LinearProgressIndicator(
      value: t,
      minHeight: minHeight,
      backgroundColor: backgroundColor,
      valueColor: valueColor,
    ),
  );
}

/// The strip at the top: who you are, what you hold, and which arena the
/// trophies have opened.
///
/// **It used to be a filled teal band and it should not have been.** The
/// argument for the fill was real — a page of white tiles has no anchor and
/// reads as washed out — but the Battle button is teal too, and side by side
/// they were two slabs of one colour at one weight, so the page led with a
/// tie. There is only one thing on Home worth shouting, and a title is not
/// it. Unfilled, the shouting is all spent on the card below.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.profile,
    required this.arenaNumber,
    required this.arenaName,
    required this.nextAt,
  });

  final PlayerProfile profile;
  final int arenaNumber;
  final String arenaName;
  final int? nextAt;

  @override
  Widget build(BuildContext context) {
    final target = nextAt;
    final fraction = target == null || target <= 0
        ? 1.0
        : (profile.trophies / target).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Gives way to the counters rather than shoving them off the
            // screen. A fixed-size wordmark next to a `Spacer` reads fine
            // until somebody has five digits of coins on a 360dp phone, and
            // then the row overflows by whatever the numbers grew by — the
            // title is the one thing here that can afford to lose a point.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'SPLATFRONT',
                  maxLines: 1,
                  style: TextStyle(
                    color: Palette.uiText,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _BandChip(
              icon: Icons.emoji_events,
              value: profile.trophies,
              colour: Palette.info,
            ),
            const SizedBox(width: 6),
            _BandChip(
              icon: Icons.monetization_on,
              value: profile.coins,
              colour: Palette.gold,
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Text(
              'ARENA $arenaNumber',
              style: const TextStyle(
                color: Palette.uiText,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                arenaName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.uiTextDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Trophies buy the third and fourth chest slot and nothing else
            // now, so the bar is a footnote rather than a headline: thin, no
            // outline of its own, and no number shouted beside it.
            Text(
              target == null ? 'MAX' : '${profile.trophies} / $target',
              style: const TextStyle(
                color: Palette.uiTextDim,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 5,
            child: ColoredBox(
              // An empty bar used to be a black pill, because the track was a
              // dark outline wash on teal. At zero trophies — which is where
              // every player starts — that read as a broken widget rather
              // than as a bar with nothing in it yet.
              color: Palette.uiTextDim.withValues(alpha: 0.22),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction),
                  duration: Motion.of(
                    context,
                    const Duration(milliseconds: 700),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => FractionallySizedBox(
                    widthFactor: t.clamp(0.0, 1.0),
                    // A ColoredBox with no child is zero-sized, so the fill
                    // needs to be told to take the full height.
                    heightFactor: 1,
                    child: const ColoredBox(color: Palette.accent),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A counter in the top strip: the page colour behind it, outlined like
/// everything else on the page.
class _BandChip extends StatelessWidget {
  const _BandChip({
    required this.icon,
    required this.value,
    required this.colour,
  });

  final IconData icon;
  final int value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Palette.uiSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Palette.outline, width: 2),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 5),
        AnimatedCount(
          value: value,
          style: const TextStyle(
            color: Palette.uiText,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

/// The quest list, scrolling on its own or not depending on who owns the
/// height.
///
/// A [ListView] inside a page that already scrolls is two scrollables fighting
/// over one gesture, and the inner one needs a bounded height it does not
/// have. On the phone the page scrolls and this is a plain column; on a tablet
/// the pane owns its half of the screen and scrolls inside it.
class _QuestList extends StatelessWidget {
  const _QuestList({required this.fillsHeight, required this.children});

  final bool fillsHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => fillsHeight
      ? Expanded(child: ListView(children: children))
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
}
