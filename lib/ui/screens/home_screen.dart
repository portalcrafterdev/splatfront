import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio.dart';
import '../../core/game_data.dart';
import '../../core/games/game_services.dart';
import '../../core/games/player_account.dart';
import '../../core/palette.dart';
import '../../core/save/player_profile.dart';
import '../../game/arena/arena_layout.dart';
import '../../game/splatfront_game.dart';
import '../../meta/profile_controller.dart';
import '../../meta/quests.dart';
import '../widgets/card_tile.dart';
import '../widgets/meta_widgets.dart';
import '../widgets/dab.dart';
import '../widgets/motion.dart';
import '../widgets/responsive.dart';
import 'battle_screen.dart';
import 'campaign_screen.dart';
import 'chest_screen.dart';
import '../type.dart';

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
          const SizedBox(height: 12),
          // Play Games, on the owner's call. Above Dab rather than below it,
          // so the guide stays the last thing read before the Battle card —
          // the instruction should sit next to the thing it points at.
          const Entrance(child: _PlayGamesRow()),
          // Dab, saying the one thing worth doing next.
          Entrance(child: DabSays(_dabLine(ref))),
          const SizedBox(height: 12),
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

/// What Dab should say, in priority order.
///
/// **Always a thing to go and do, never a status.** The rule that keeps this
/// honest: every branch is phrased as an instruction with a verb, because a
/// guide that says "you have 0 trophies" has told a child nothing they can
/// act on.
///
/// Ordered by what is *finished and waiting* first, then what is in progress,
/// then the default. A reward sitting unclaimed is the most annoying thing to
/// walk past, so it goes to the top.
String _dabLine(WidgetRef ref) {
  final data = ref.watch(gameDataProvider);
  final profile = ref.watch(profileProvider);
  final controller = ref.read(profileProvider.notifier);

  final claimable = controller.todaysQuests.any((q) {
    final p = controller.progressFor(q.id);
    return !p.claimed && p.progress >= q.target;
  });
  if (claimable) return 'A job is done! Tap the coins to collect.';

  if (profile.chests.any(controller.isReady)) {
    return 'Your chest is ready. Go and open it!';
  }
  if (profile.chests.any((c) => !c.isUnlocking)) {
    return 'Tap a chest to start its timer.';
  }
  if (profile.campaignNextLevel > data.campaign.levelCount) {
    return 'You finished every level. Go back for more stars!';
  }
  if (profile.campaignStars.isEmpty) {
    return 'Tap Battle to paint your first level!';
  }
  return 'Tap Battle to paint level ${profile.campaignNextLevel}!';
}


/// Play Games on Home: sign in, or the two doors it opens.
///
/// **Back on Home on the owner's call**, having been moved to Settings during
/// the children's redesign. The argument for moving it stands and is worth
/// keeping written down: connecting an account is a parent's decision, and
/// this row occupies the best space on the first screen a child sees. What
/// outweighed it is that achievements and leaderboards are unreachable in
/// practice if the only door is three taps into a settings page — fourteen
/// achievements and two boards with nothing pointing at them.
///
/// It is built to cost the page as little as possible: one slim row, the
/// secondary accent rather than the action colour, and it never competes with
/// the Battle card for attention.
///
/// Signed out it offers the sign-in. Signed in it becomes the two buttons,
/// because that is the state the player spends the rest of the game in and a
/// row that just said "connected" would be a line of chrome doing nothing.
class _PlayGamesRow extends StatefulWidget {
  const _PlayGamesRow();

  @override
  State<_PlayGamesRow> createState() => _PlayGamesRowState();
}

class _PlayGamesRowState extends State<_PlayGamesRow> {
  bool _pressed = false;

  String get _serviceName => defaultTargetPlatform == TargetPlatform.iOS
      ? 'Game Center'
      : 'Play Games';

  Future<void> _signIn() async {
    setState(() => _pressed = true);
    final ok = await GameServices.signIn();
    if (!mounted) return;
    setState(() => _pressed = false);
    if (!ok) {
      // Said plainly. A button that silently does nothing is a broken button,
      // and sign-in fails for reasons the player can do nothing about —
      // no network, a device with no Play Games, an account that declines.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not connect to $_serviceName.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Asks first, then disconnects.
  ///
  /// **The dialog exists because the button is not reversible by accident.**
  /// What it costs has to be said in the words that are actually true: the
  /// game stops recording, the account keeps everything it already has, and
  /// reconnecting brings it all back. That last line is what makes this an
  /// honest confirmation rather than a scare.
  ///
  /// It deliberately does **not** say "sign out". The player stays signed in
  /// to Play Games on the device — nothing in this app can change that — and
  /// promising otherwise sends them hunting for a bug that is not there.
  Future<void> _disconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.uiSurfaceHigh,
        title: const Text(
          'Disconnect?',
          style: TextStyle(fontFamily: Fonts.display, color: Palette.uiText),
        ),
        content: Text(
          'Splatfront will stop recording your stars and achievements to '
          '$_serviceName.\n\n'
          'Everything you have already earned stays on your account, and '
          'your game on this phone is not touched. Sign in again any time '
          'to start recording again.',
          style: const TextStyle(
            color: Palette.uiTextDim,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          // The one honest route to an actual sign-out, offered next to the
          // thing people mistake for one. Disconnect stops *this game*
          // recording; only the Play Games app can release the account from
          // the device, and this is the moment somebody is looking for that.
          if (PlayerAccount.isSupported)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
                _openAccount(context);
              },
              child: const Text('PLAY GAMES APP'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Palette.danger),
            child: const Text('DISCONNECT'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await GameServices.disconnect();
  }

  /// Hands the player to the Play Games app.
  ///
  /// Says so plainly when there is nowhere to go, rather than doing nothing:
  /// on a device with no Play Games installed this is the only feedback the
  /// press produces.
  Future<void> _openAccount(BuildContext context) async {
    final opened = await PlayerAccount.openPlayGames();
    if (opened || !context.mounted) return;
    // Reached only when neither the Play Games app, the Play Store nor a
    // browser would open — a device with no Google services at all. The old
    // wording said "Play Games is not installed", which was wrong twice over:
    // it is now offered for install rather than refused, and the same message
    // used to appear on phones that *did* have it, because the manifest was
    // missing the <queries> entry that makes it visible.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open Play Games on this device.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    // Rebuilds when the service state changes, including a sign-in that
    // completes long after this row was built.
    valueListenable: GameServices.revision,
    builder: (context, _, _) {
      final signedIn = GameServices.isSignedIn;
      final busy = _pressed || GameServices.isBusy;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Panel(
          outlined: false,
          radius: 14,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                signedIn
                    ? Icons.sports_esports_rounded
                    : Icons.sports_esports_outlined,
                size: 20,
                color: Palette.info,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  signedIn
                      ? (GameServices.playerName ?? 'Signed in')
                      // Disconnected is not the same fact as never connected:
                      // one is a choice this player made and can undo, the
                      // other is a state they have never left. Saying "Sign
                      // in" to somebody who just pressed Disconnect reads as
                      // the button having failed.
                      : GameServices.isOptedOut
                      ? 'Disconnected'
                      : 'Sign in to $_serviceName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Palette.uiText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (signedIn) ...[
                _IconDoor(
                  icon: Icons.leaderboard_rounded,
                  tooltip: 'Leaderboards',
                  onTap: () => GameServices.showLeaderboards(),
                ),
                const SizedBox(width: 4),
                _IconDoor(
                  icon: Icons.military_tech_rounded,
                  tooltip: 'Achievements',
                  onTap: GameServices.showAchievements,
                ),
                const SizedBox(width: 4),
                _IconDoor(
                  icon: Icons.link_off_rounded,
                  tooltip: 'Disconnect',
                  onTap: () => _disconnect(context),
                ),
              ] else
                FilledButton(
                  onPressed: busy ? null : _signIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.info,
                    disabledBackgroundColor: Palette.uiBackground,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(busy ? '…' : 'Sign in'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// One of the two platform screens, as a tap target big enough for a thumb.
class _IconDoor extends StatelessWidget {
  const _IconDoor({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: Tooltip(
      message: tooltip,
      child: PressScale(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Palette.info.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 21, color: Palette.info),
        ),
      ),
    ),
  );
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
      // Soft, like everything else on this page now. The caller's colour still
      // decides how present the edge is — a ready chest reads a shade firmer
      // than an empty slot — it is just no longer a black line doing it.
      border: Border.all(
        color: border == Palette.uiTextDim.withValues(alpha: 0.2)
            ? Panel.softEdge
            : Palette.accent.withValues(alpha: 0.45),
        width: 1,
      ),
      boxShadow: Panel.softShadow,
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
          // "Today", not "Daily quests". Two words to one, and the one that
          // survives is the one a six-year-old already owns — "daily" and
          // "quest" are both above the reading age this UI is written for,
          // and the tile underneath says what they are without either.
          SectionHeading(
            'Today',
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
                  outlined: false,
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
      outlined: false,
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
              border: Border.all(color: Panel.softEdge, width: 1),
              boxShadow: Panel.softShadow,
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
      outlined: false,
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
    final countable = Pips.suits(quest.target);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          // What the job is, as a picture.
          //
          // It was a 4dp stripe, which carried done/not-done and nothing
          // else. A pre-reader cannot tell "play 15 spell cards" from "win 2
          // matches" without reading them, and the icon is what lets them.
          // Colour still carries the state on top of that: the tile goes
          // green the moment it is finished.
          _QuestBadge(type: quest.type, done: done),
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
                    // The count is dropped entirely where the pips replace
                    // it. Fifteen squares with four filled *is* "4 of 15",
                    // and printing both says the same thing twice — once in
                    // a form this reader can use and once in a form they
                    // cannot.
                    if (!countable) ...[
                      const SizedBox(width: 8),
                      // Still on the same line as the objective. Under the
                      // bar it was a third line of type per quest, and three
                      // quests were paying nine lines for six facts.
                      Text(
                        '${progress.progress} / ${quest.target}',
                        style: const TextStyle(
                          color: Palette.uiTextDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // Countable targets get squares to count; a percentage gets
                // a bar, because sixty dots is not something anyone counts.
                // `Pips.suits` owns that cutover so it happens in one place.
                if (countable)
                  Pips(done: progress.progress, target: quest.target)
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    // Tweened, so finishing an objective fills the bar rather
                    // than teleporting it. Finite: it settles at the value and
                    // stops, so it cannot hang a pumpAndSettle.
                    child: _AnimatedBar(
                      value: fraction,
                      minHeight: 8,
                      backgroundColor: Palette.uiBackground,
                      valueColor: AlwaysStoppedAnimation(
                        done ? Palette.success : Palette.lime,
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
              ? Palette.accentShade
              : Palette.uiTextDim.withValues(alpha: 0.3),
          width: 1,
        ),
        // A claimable chip keeps its tonal shade, which is not the black
        // outline — it is the same teal catching less light, and it is what
        // makes the chip look pressable without a line round it.
        boxShadow: ready
            ? const [
                BoxShadow(color: Palette.accentShade, offset: Offset(0, 2)),
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

  /// How tall the painted board is.
  ///
  /// Raised from 132 when the level number turned out to be sitting on the
  /// frontier. A frontier step is a whole grid cell and a cell is sized off
  /// the card's *width*, so on a wider phone a single step reaches further
  /// down the board while the type stays the same size — which is why this
  /// could look fine on one screen and overlap on another.
  static const double _boardHeight = 160;

  /// The strip along the bottom the frontier is not allowed into.
  ///
  /// Covers the two lines of type plus their padding, with room to spare, so
  /// whatever the painter does above it there is always flat player-colour
  /// behind the level number. This is the guarantee; the scrim and the text
  /// shadow are what make it look good on top of that.
  static const double _textBand = 64;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [_board(), const SizedBox(height: 12), _button()],
  );

  /// The board you are about to fight over, and which level it is.
  ///
  /// Still pressable. It shows the level you would play, so tapping it is the
  /// obvious thing to try — and taking the target away to make the button
  /// "the only way in" would punish exactly that instinct. It presses more
  /// shallowly than the button below, which is what says the button is the
  /// one being offered.
  Widget _board() => PressScale(
    onTap: onPressed,
    scale: 0.985,
    child: Semantics(
      button: true,
      label: complete ? 'Campaign cleared' : 'Level $level, $name',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          // No line. The board's own colour is what gives this card its
          // edge — it is the only object on Home with red and blue in it —
          // and a near-black ring around a card that is already high-contrast
          // reads as a frame rather than as shape.
          boxShadow: Panel.softShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _boardHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // CustomPaint does not clip, and the frontier steps run to
                    // the full width. The ClipRRect above is what holds it in.
                    CustomPaint(
                      painter: _BoardPreviewPainter(
                        seed: level,
                        reserve: _textBand,
                      ),
                      isComplex: true,
                      willChange: false,
                    ),
                    // The board is mid-tone red and blue, and white text on
                    // either is thin. A dark gradient rising from the bottom
                    // gives the two lines a ground of their own without
                    // dimming the paint they sit on.
                    //
                    // Three stops rather than two, and it holds its strength
                    // through the whole text band before falling away. At two
                    // stops it was already fading where the type started, so
                    // the busiest part of the board — the frontier itself —
                    // was showing through the tops of the letters at about a
                    // fifth of the intended darkness.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xCC0B1512),
                            Color(0x990B1512),
                            Color(0x000B1512),
                          ],
                          stops: [0, 0.45, 0.8],
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
                                fontFamily: Fonts.display,
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                height: 1.05,
                                // Belt and braces over a two-colour board. The
                                // scrim and the reserved band should already
                                // put blue behind every letter; this is what
                                // keeps the type readable if either is ever
                                // retuned and stops being enough.
                                shadows: [
                                  Shadow(
                                    color: Color(0x8C0B1512),
                                    blurRadius: 6,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x8C0B1512),
                                    blurRadius: 5,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// The button, as its own object.
  ///
  /// It used to be a footer strip inside the card, sharing its corners and
  /// its shadow — one tall block that happened to be teal along the bottom.
  /// A button that is part of a picture does not look like a button, and the
  /// one question this screen has to answer without words is *where do I
  /// press*. Standing on its own, with its own shadow and its own squash, it
  /// answers that from across the room.
  Widget _button() => PressScale(
    onTap: onPressed,
    // Deeper than the board above it. This is the one control the whole
    // screen is built around, and it should feel like it takes a real push.
    scale: 0.96,
    child: Semantics(
      button: true,
      label: 'BATTLE',
      child: Container(
        width: double.infinity,
        // The one thing on the page a child is meant to press, so it is the
        // one thing sized for a thumb rather than for a pointer: 18 of
        // padding puts the tap target over 56dp.
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.accent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: Panel.softShadow,
        ),
        child: const Text(
          'BATTLE',
          style: TextStyle(
            fontFamily: Fonts.display,
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
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
  const _BoardPreviewPainter({required this.seed, this.reserve = 0});

  final int seed;

  /// A strip along the bottom the frontier may not cross into, so the level
  /// number always has flat player-colour behind it.
  ///
  /// The clamp is in pixels rather than in cells on purpose. A cell is sized
  /// off the card's width, so one step down reaches further on a wide phone
  /// than on a narrow one while the type stays the same size — a reserve
  /// counted in cells would hold on the screen it was tuned on and fail on
  /// the next one.
  final double reserve;

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
      final split = math.min(
        (mid + step) * cell,
        math.max(0.0, size.height - reserve),
      );
      final x = c * cell;

      canvas
        ..drawRect(
          Rect.fromLTWH(x, 0, cell + 0.5, split),
          paint..color = Palette.red,
        )
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
      canvas.drawLine(Offset(c * cell, 0), Offset(c * cell, size.height), line);
    }
    for (var r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * cell), Offset(size.width, r * cell), line);
    }
  }

  @override
  bool shouldRepaint(_BoardPreviewPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.reserve != reserve;
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
                    fontFamily: Fonts.display,
                    color: Palette.uiText,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
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
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Palette.uiSurfaceHigh,
      borderRadius: BorderRadius.circular(20),
      // Tinted by what it counts rather than ringed in black. The icon inside
      // is already the colour; a matching hairline is enough to make the pill
      // read as a container without a 2px line doing it.
      border: Border.all(color: colour.withValues(alpha: 0.4), width: 1),
      boxShadow: Panel.softShadow,
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

/// What kind of job a quest is, as a picture on a coloured square.
///
/// The icon is the point: a child who cannot yet read "play 15 spell cards"
/// can still tell it apart from "win 2 matches", and can learn which is which
/// once and recognise it every day after. The colour carries the state on top
/// of that — every square goes green the moment its job is done, so a
/// finished list reads as finished from across the room.
///
/// Hues come from the chrome set and dodge both sides, as section 14 requires.
class _QuestBadge extends StatelessWidget {
  const _QuestBadge({required this.type, required this.done});

  final QuestType type;
  final bool done;

  static const Map<QuestType, (IconData, Color)> _marks = {
    QuestType.winMatches: (Icons.emoji_events_rounded, Palette.gold),
    QuestType.playMatches: (Icons.sports_esports_rounded, Palette.accent),
    QuestType.playCards: (Icons.style_rounded, Palette.info),
    QuestType.playSpells: (Icons.auto_awesome_rounded, Palette.elixir),
    QuestType.paintShare: (Icons.format_paint_rounded, Palette.lime),
    QuestType.unknown: (Icons.flag_rounded, Palette.accent),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = _marks[type] ?? _marks[QuestType.unknown]!;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: done ? Palette.success : colour,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        done ? Icons.check_rounded : icon,
        size: 19,
        color: Colors.white,
      ),
    );
  }
}
