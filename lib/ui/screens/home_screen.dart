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
import '../widgets/match_header.dart';
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Entrance(
            child: _HeaderBand(
              profile: profile,
              arenaNumber: data.arenas.indexOf(arena) + 1,
              arenaName: arena.name,
              nextAt: data.nextArenaThreshold(profile.trophies),
            ),
          ),
          const SizedBox(height: 14),
          Entrance(
            index: 2,
            child: _ChestRow(profile: profile, slots: controller.chestSlots),
          ),
          const SizedBox(height: 16),
          // Battle plays the level you are up to. There is no difficulty
          // picker any more: with one progression, the level number *is* the
          // difficulty, and a free-play match that fed nothing was the odd
          // one out — it paid trophies and chests without ever advancing the
          // thing the rest of the app is about.
          _BigButton(
            label: 'BATTLE',
            sublabel: nextLevel > data.campaign.levelCount
                ? 'Campaign complete'
                : 'Level $nextLevel  ·  ${data.campaign.levelAt(nextLevel).tier.rankName}',
            onPressed: () => startCampaignLevel(context, ref, nextLevel),
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
              for (final quest in quests)
                _QuestRow(
                  quest: quest,
                  progress: controller.progressFor(quest.id),
                  onClaim: () => controller.claimQuest(quest.id),
                ),
              if (quests.isEmpty)
                const Text(
                  'No quests today.',
                  style: TextStyle(color: Palette.uiTextDim, fontSize: 12),
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

    return Container(
      // Sixteen, not eight: the tile drops a hard [Panel.lift] shadow, so a
      // gap has to clear that before any of it is visible. At 8 the shadow
      // ate half of it and three quests read as one block with lines through
      // it rather than three separate things to do.
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          (done ? Palette.success : Palette.info).withValues(alpha: 0.18),
          Palette.uiSurface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.outline, width: Panel.stroke),
        boxShadow: const [
          BoxShadow(
            color: Palette.outlineShadow,
            offset: Offset(0, Panel.lift),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quest.text,
                  style: TextStyle(
                    // Struck through is already the signal that it is done;
                    // dimming it as well left the text unreadable against the
                    // green tint, and a quest you cannot read is a quest you
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
                const SizedBox(height: 3),
                Text(
                  '${progress.progress} / ${quest.target}',
                  style: const TextStyle(
                    color: Palette.uiTextDim,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (progress.claimed)
            const Icon(Icons.check, color: Palette.success, size: 18)
          else
            FilledButton(
              onPressed: done ? onClaim : null,
              // A quest you have not finished still has to show what it pays,
              // and the unclaimable chip was filled with the page colour and
              // labelled in Material's default disabled grey — which on a
              // tinted quest tile left the number as a smudge. Filled and
              // outlined instead, so it reads as a reward waiting rather
              // than as a rendering fault.
              style: FilledButton.styleFrom(
                backgroundColor: Palette.accent,
                disabledBackgroundColor: Palette.uiSurfaceHigh,
                disabledForegroundColor: Palette.uiTextDim,
                side: done
                    ? null
                    : const BorderSide(color: Palette.outline, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                '${quest.coins}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
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

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.onPressed,
    this.sublabel,
  });

  final String label;

  /// What the button will actually do, when that is not obvious from one
  /// word. "BATTLE" alone no longer says which fight you are walking into,
  /// and the level number is the thing a player is keeping track of.
  final String? sublabel;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onPressed,
    // Deeper than a tile: this is the button the whole screen is built
    // around, and it should feel like it takes a real push.
    scale: 0.97,
    child: Semantics(
      button: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.accent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Palette.outline, width: 3),
          boxShadow: const [
            // Deeper than a tile: this is the one control the whole screen
            // is built around, and it should look like it stands off the page.
            BoxShadow(color: Palette.outlineShadow, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            if (sublabel case final sub?) ...[
              const SizedBox(height: 3),
              Text(
                sub,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Easy / Normal / Hard. The same brain runs all three; only the numbers in
/// `bot_decks.json` differ.
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

/// The orange block at the top: who you are and how far along you are.
///
/// The title, the two counters and the arena progress used to be three
/// separate lines of text floating on the page. A page of white tiles on
/// cream has no anchor and reads as washed out however tidy it is; a solid
/// block of colour at the top gives the screen somewhere to start.
class _HeaderBand extends StatelessWidget {
  const _HeaderBand({
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

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Palette.accent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.outline, width: 3),
        boxShadow: const [
          BoxShadow(color: Palette.outlineShadow, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'SPLATFRONT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
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
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'ARENA $arenaNumber',
                style: const TextStyle(
                  color: Colors.white,
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
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                target == null ? 'MAX' : '${profile.trophies} / $target',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: Palette.outline.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Palette.outline, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => FractionallySizedBox(
                    widthFactor: t.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A counter on the orange band. White so it reads against it, outlined like
/// everything else.
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
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
