import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ads/ads.dart';
import '../../core/audio.dart';
import '../../core/game_data.dart';
import '../../core/palette.dart';
import '../../game/cards/card_registry.dart';
import '../../meta/campaign.dart';
import '../../meta/profile_controller.dart';
import '../widgets/meta_widgets.dart';
import '../type.dart';
import '../widgets/motion.dart';
import 'battle_screen.dart';

/// The campaign: a thousand levels, three stars each.
///
/// The list is built lazily and the levels themselves are derived from their
/// number rather than stored, so a thousand of them cost no more to show
/// than a dozen — nothing is held in memory but the handful of tiles on
/// screen and the stars the player has actually earned.
class CampaignScreen extends ConsumerStatefulWidget {
  const CampaignScreen({super.key});

  @override
  ConsumerState<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends ConsumerState<CampaignScreen> {
  /// The list's own padding, needed in two places: on the list, and in the
  /// arithmetic that reads a row's height back out of it.
  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(12, 4, 12, 16);

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Placed after the first layout rather than as an initialScrollOffset.
    // The offset has to be clamped against maxScrollExtent, which does not
    // exist until the list has been measured, and jumping afterwards also
    // overrides any position restored from storage — a tab switch was
    // handing this list an offset belonging to a different screen and
    // opening it hundreds of levels from anything playable.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
  }

  /// The height one row was actually given, read back out of the list.
  ///
  /// This used to be a `static const 72` that the list was also *told* to use
  /// as its `itemExtent`, and the number was a guess at how tall the tile
  /// comes out. It was one pixel short on a real device — every row in the
  /// list drew Flutter's yellow overflow stripes — and it could not have been
  /// anything else, because a tile's height depends on the font the device
  /// happens to have and a constant in Dart cannot know that. The list now
  /// measures a real tile instead (see `prototypeItem`), so this only has to
  /// recover the number it landed on.
  double get _tileExtent {
    final position = _scroll.position;
    final content =
        position.maxScrollExtent +
        position.viewportDimension -
        _listPadding.vertical;
    final count = ref.read(gameDataProvider).campaign.levelCount;
    return count <= 0 ? 0 : content / count;
  }

  void _jumpToCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    final next = ref.read(profileProvider).campaignNextLevel;
    // Two tiles of lead-in, so the level you are up to is not jammed against
    // the top edge with its cleared history invisible above it.
    final target = (next - 3) * _tileExtent;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(gameDataProvider);
    final profile = ref.watch(profileProvider);
    final campaign = data.campaign;

    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MetaHeader(
                title: 'Levels',
                profile: profile,
                // Shorter, and in words a seven-year-old has. The old line
                // spent three clauses and two percentages explaining the star
                // thresholds — true, and unreadable at this age. Paint more,
                // get more is the whole rule; the exact numbers are something
                // you learn by playing, and the result screen says them at
                // the moment they matter.
                //
                // "Play on your own" also keeps section 14's promise that v1
                // never pretends to be multiplayer — it just keeps it in
                // language the reader actually parses.
                subtitle: 'Play on your own. Win to get a star, '
                    'paint more to get three.',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                // Not the arena name. The mockup showed a "Primer Yard" band
                // over the trail, which works for one screenful and not for a
                // thousand levels across four arenas — a header that is right
                // at the top of the list is wrong by level 30 and cannot
                // follow the scroll without becoming a sticky section, which
                // a fixed-extent list does not give for free. The arena is
                // already named on the row where it actually changes, which
                // is the only place it is news.
                child: SectionHeading(
                  'Level ${profile.campaignNextLevel}',
                  trailing:
                      '${profile.campaignTotalStars} '
                      'of ${campaign.levelCount * 3} stars',
                ),
              ),
              Expanded(
                child: ListView.builder(
                  // Its own storage bucket, so it can never be handed a scroll
                  // offset that belonged to a different tab.
                  key: const PageStorageKey<String>('campaign-levels'),
                  controller: _scroll,
                  padding: _listPadding,
                  itemCount: campaign.levelCount,
                  // Measured, not guessed.
                  //
                  // Every row is the same shape, so the list still gets one
                  // fixed extent and stays O(1) to scroll through a thousand
                  // levels — but the extent comes from laying out a real tile
                  // at the device's real font rather than from a constant
                  // somebody typed. The constant was 72 against a tile that
                  // wanted 73, and a one-pixel shortfall on a fixed extent is
                  // an overflow banner on every row.
                  //
                  // The prototype is deliberately a fully loaded tile — stars
                  // showing, a subtitle with a reward on it — because it sets
                  // the height for every row, and a prototype shorter than the
                  // busiest real row puts the overflow straight back.
                  prototypeItem: _LevelTile(
                    level: campaign.levelAt(1),
                    stars: 3,
                    unlocked: true,
                    current: true,
                    firstLocked: false,
                    name: campaign.nameFor(1),
                    arenaName: data.arenas.first.name,
                    reward: _rewardLabel(data, campaign, 1) ?? 'unlocks a card',
                    onPlay: () {},
                  ),
                  itemBuilder: (context, index) {
                    final number = index + 1;
                    final level = campaign.levelAt(number);
                    return _LevelTile(
                      level: level,
                      stars: profile.starsOnLevel(number),
                      unlocked: profile.isLevelUnlocked(number),
                      current: number == profile.campaignNextLevel,
                      firstLocked: number == profile.campaignNextLevel + 1,
                      name: campaign.nameFor(number),
                      // The board is named on the level it changes on and
                      // nowhere else. It is the same arena for twenty-five
                      // levels at a stretch, so printing it on every row was
                      // the repetition, and the boundary is the only place it
                      // is actually news.
                      arenaName: campaign.arenaChangesAt(number)
                          ? data
                                .arenas[level.arenaIndex % data.arenas.length]
                                .name
                          : null,
                      // What this level pays over and above its stars. Most
                      // levels pay nothing extra and say nothing.
                      //
                      // A card unlock outranks the rest: it is the only reward
                      // that changes what the player can do next, so it is the
                      // one worth naming even on a level that also pays coins.
                      reward: _rewardLabel(data, campaign, number),
                      onPlay: () => _play(context, campaign, number),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The extras a level pays, or null for the majority that pay none.
  static String? _rewardLabel(
    GameData data,
    CampaignConfig campaign,
    int number,
  ) {
    final parts = <String>[];

    final card = campaign.cardUnlockedAt(number);
    if (card != null) parts.add('unlocks ${data.cards[card].name}');
    if (campaign.chestOn(number)) parts.add('chest');

    final coins = campaign.milestoneCoinsOn(number);
    if (coins > 0) parts.add('$coins coins');

    return parts.isEmpty ? null : parts.join(' + ');
  }

  void _play(BuildContext context, CampaignConfig campaign, int number) =>
      startCampaignLevel(context, ref, number);
}

/// Opens the arena on campaign level [number].
///
/// Top-level rather than a method, because two screens start a level: the
/// list here, and the battle button on Home, which plays whichever level you
/// are up to. One function so the two can never drift on what a level scores
/// or how its result is banked.
Future<void> startCampaignLevel(
  BuildContext context,
  WidgetRef ref,
  int number,
) async {
  final data = ref.read(gameDataProvider);
  final profile = ref.read(profileProvider);
  final controller = ref.read(profileProvider.notifier);
  final campaign = data.campaign;

  final level = campaign.levelAt(number);
  final arena = data.arenas[level.arenaIndex % data.arenas.length];

  Audio.play(Sfx.uiTap);

  // The interstitial goes here, before the arena is built, and it is awaited.
  //
  // Two reasons it cannot go inside the battle screen. Ad loading is
  // platform-channel work, and this app has already been killed by Android
  // once for flooding that queue — so nothing may be fetched or shown while a
  // game loop is asking for sixty frames a second. And an ad appearing *over*
  // a started match would run the countdown behind it.
  //
  // With ads off, no fill, or the pacing rules saying no, this returns
  // immediately and the player never knows it was here. It never blocks and
  // never shows a spinner: a level start that waits on a network is a level
  // start that fails on a train.
  await Ads.maybeShowOnLevelStart();
  if (!context.mounted) return;

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BattleScreen(
        layout: arena,
        cards: data.cards,
        deck: controller.deck,
        levels: profile.levels,
        botDeck: data.bot.deckFor(arena.id),
        botDifficulty: level.difficulty,
        botStrength: campaign.rampAt(number),
        botLevels: CardLevels.uniform(level.botCardLevel),
        campaign: CampaignBattle(level: number, config: campaign),
        // The clock and sudden death come from these rules; the trophy
        // change they produce is ignored, because the campaign has its own
        // progression and grinding level 1 should not move the ladder.
        trophyRules: data.trophies,
        economy: data.economy,
        startingTrophies: profile.trophies,
        onFinished: (result, tally) {
          final reward = controller.applyCampaignLevel(
            level: number,
            stars: campaign.starsFor(
              won: result.won,
              playerShare: result.playerShare,
            ),
            tally: tally,
          );
          return reward.chestKept;
        },
        // Straight into the next level from the end screen, rather than out
        // to Home and back in through BATTLE.
        //
        // It recurses through this same function rather than building a
        // BattleScreen for level+1 inline, so the next level is assembled
        // exactly like every other one — same deck, same ramp, same banking,
        // and the same interstitial pacing. Popping first keeps the route
        // stack flat: without it, a run of twenty levels would be twenty
        // battle screens deep and HOME would only ever go back one.
        onNextLevel: number < campaign.levelCount
            ? () {
                Navigator.of(context).pop();
                startCampaignLevel(context, ref, number + 1);
              }
            : null,
      ),
    ),
  );
}

/// One row of the ladder.
class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.stars,
    required this.unlocked,
    required this.current,
    required this.firstLocked,
    required this.name,
    required this.arenaName,
    required this.reward,
    required this.onPlay,
  });

  final CampaignLevel level;
  final int stars;
  final bool unlocked;

  /// The next level to beat. It gets the accent fill and the bigger marker,
  /// so the eye lands on the one thing the page is asking the player to do.
  final bool current;

  /// The first level you cannot play yet — and only that one.
  ///
  /// It carries "Win level N first". The rows below it are locked for the
  /// same reason and say nothing, because repeating the explanation down a
  /// screen of grey circles teaches nobody anything and makes the wall of
  /// locked levels look longer than it is.
  final bool firstLocked;

  /// This level's own name, so that no two rows in the list read alike.
  final String name;

  /// The board, named only on the level the board changes on.
  final String? arenaName;

  /// What this level pays on top of its stars, or null for the majority that
  /// pay nothing extra. Twenty-five identical rows is what a list of derived
  /// levels looks like without this — the reward is the thing that actually
  /// differs between one level and the next this early on.
  final String? reward;

  final VoidCallback onPlay;

  /// How far each row is pushed in from the left.
  ///
  /// This is the whole trail. A thousand left-aligned rows is a spreadsheet;
  /// the same rows stepping in and back out read as a route going somewhere,
  /// which is the one thing a child wants to know about a list of levels —
  /// where am I on it, and what is next.
  ///
  /// It is a padding value per row rather than a drawn curve on purpose. A
  /// painted path would need to know about the rows above and below it, and
  /// the list is virtualised — at level 400 there is nothing above to ask.
  static const List<double> _indents = [0, 18, 34, 18];

  @override
  Widget build(BuildContext context) {
    final ink = unlocked ? Palette.uiText : Palette.uiTextDim;
    final cleared = stars > 0;

    final row = Padding(
      padding: EdgeInsets.fromLTRB(
        12 + _indents[(level.number - 1) % _indents.length],
        4,
        12,
        4,
      ),
      child: Row(
        children: [
          _NumberChip(
            number: level.number,
            current: current,
            locked: !unlocked,
            cleared: cleared,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: current ? Palette.accent : Palette.uiTextDim,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                // Stars sit under the name rather than out at the right
                // edge. Three small marks floating in the far corner of a
                // row are the last thing the eye finds; under the level's
                // own name they belong to it.
                if (unlocked) ...[
                  const SizedBox(height: 3),
                  _Stars(stars: stars, onAccent: false),
                ],
              ],
            ),
          ),
          // Kept for locked rows even though the grey bubble already says
          // it. The bubble's colour is the only other signal, and colour
          // alone is nothing to a colourblind player.
          if (!unlocked)
            Icon(
              Icons.lock_rounded,
              size: 18,
              color: Palette.uiTextDim.withValues(alpha: 0.45),
            ),
        ],
      ),
    );

    // A locked row is not pressable, so it gets no press animation either —
    // a tile that squashes under a finger and then does nothing is a worse
    // answer than one that does not move.
    return unlocked ? PressScale(onTap: onPlay, child: row) : row;
  }

  /// What makes this level different from the last one. The bot's card level
  /// only appears once it has actually started climbing — saying "cards
  /// level 1" on the first hundred levels would be noise.
  ///
  /// The opponent carries no difficulty word at all any more.
  ///
  /// This said "Novice Bot", then "Easy" — first ladder vocabulary that
  /// teaches a player nothing, then a plain word that was at least honest.
  /// Both are gone with the tiers: **the level number is the difficulty**, it
  /// is already the largest thing on the tile, and a label repeated across
  /// three hundred rows said less than the number beside it. What is left
  /// here is what actually varies — the board, the opponent's card level once
  /// it starts climbing, and what the level still owes you.
  String get _subtitle {
    // The two that speak to the player directly outrank the facts about the
    // level, because they are the only lines on this screen that say what to
    // do rather than what is true.
    if (current) return 'Tap to play';
    if (firstLocked) return 'Win level ${level.number - 1} first';

    final parts = <String>[?arenaName];
    if (level.botCardLevel > 1) parts.add('cards level ${level.botCardLevel}');
    if (reward case final extra?) parts.add(extra);
    return parts.join(' · ');
  }
}

/// One stop on the trail.
///
/// Round rather than a rounded rectangle, because the row is no longer a tile
/// — with the card gone this is the only object on the line, and a circle
/// reads as a marker on a route where a box reads as a button that lost its
/// label.
///
/// Four states, each drawn rather than faded: the next level is filled and
/// **bigger**, a cleared one is lime, an unlocked-but-unbeaten one is plain
/// white, and a locked one is a shade off the page. Size is doing real work
/// here — it is the one difference that survives being glanced at, and there
/// is exactly one bigger circle in the whole thousand-level list.
class _NumberChip extends StatelessWidget {
  const _NumberChip({
    required this.number,
    required this.current,
    required this.locked,
    required this.cleared,
  });

  final int number;
  final bool current;
  final bool locked;

  /// Beaten at least once, whatever the star count.
  final bool cleared;

  /// The next level's marker. Every other one is [_size].
  static const double _currentSize = 54;
  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final diameter = current ? _currentSize : _size;
    final fill = current
        ? Palette.accent
        : cleared
        ? Palette.lime
        : locked
        ? Color.alphaBlend(
            Palette.uiTextDim.withValues(alpha: 0.08),
            Palette.uiBackground,
          )
        : Palette.uiSurfaceHigh;

    // Every marker occupies the width of the biggest one, so the names beside
    // them line up down the column. Without this the current level's text
    // would be pushed 8dp right of every other row and the trail would look
    // like a mistake rather than a step.
    return SizedBox(
      width: _currentSize,
      height: _currentSize,
      child: Center(
        child: Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            boxShadow: locked ? null : Panel.softShadow,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontFamily: Fonts.display,
              color: current
                  ? Colors.white
                  : locked
                  ? Palette.uiTextDim.withValues(alpha: 0.75)
                  : Palette.uiText,
              fontSize: number > 999
                  ? 15
                  : current
                  ? 22
                  : 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.stars, required this.onAccent});

  final int stars;
  final bool onAccent;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 3; i++)
        Icon(
          i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 19,
          color: i <= stars
              ? (onAccent ? Colors.white : Palette.gold)
              : (onAccent
                    ? Colors.white.withValues(alpha: 0.45)
                    : Palette.uiTextDim.withValues(alpha: 0.4)),
        ),
    ],
  );
}
