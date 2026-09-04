import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio.dart';
import '../../core/game_data.dart';
import '../../core/palette.dart';
import '../../game/cards/card_registry.dart';
import '../../meta/campaign.dart';
import '../../meta/profile_controller.dart';
import '../widgets/meta_widgets.dart';
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
                subtitle:
                    'Single player. Win to earn a star, paint '
                    '${(campaign.twoStarCoverage * 100).round()}% for two and '
                    '${(campaign.threeStarCoverage * 100).round()}% for three.',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    current: false,
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
void startCampaignLevel(BuildContext context, WidgetRef ref, int number) {
  final data = ref.read(gameDataProvider);
  final profile = ref.read(profileProvider);
  final controller = ref.read(profileProvider.notifier);
  final campaign = data.campaign;

  final level = campaign.levelAt(number);
  final arena = data.arenas[level.arenaIndex % data.arenas.length];

  Audio.play(Sfx.uiTap);
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
    required this.name,
    required this.arenaName,
    required this.reward,
    required this.onPlay,
  });

  final CampaignLevel level;
  final int stars;
  final bool unlocked;

  /// The next level to beat. It gets the accent fill, so the eye lands on
  /// the one thing the page is asking the player to do.
  final bool current;

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

  @override
  Widget build(BuildContext context) {
    final ink = unlocked ? Palette.uiText : Palette.uiTextDim;

    // Three states, drawn rather than faded.
    //
    // A locked row used to be this same near-white tile wrapped in
    // `Opacity(0.55)`, and on a pale page that is very close to not being
    // there at all: seven of the eight rows on screen read as empty outlines,
    // and the level names — the only thing that makes scrolling a thousand
    // rows worth anything — went translucent with them. Opacity fades a whole
    // subtree indiscriminately, which is exactly the wrong tool for "this is
    // not available yet". A locked row now has its own solid fill and its own
    // ink, so it sits back without vanishing.
    final tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: current
            ? Palette.accent
            : unlocked
            ? Palette.uiSurface
            // A shade off the page rather than the same white as a playable
            // row. It reads as a row that is there but shut.
            : Color.alphaBlend(
                Palette.uiTextDim.withValues(alpha: 0.07),
                Palette.uiBackground,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? Palette.outline
              : Palette.outline.withValues(alpha: 0.3),
          width: Panel.stroke,
        ),
        // Only rows you can actually press stand off the page. The shadow is
        // the affordance, so a locked row not having one is information.
        boxShadow: unlocked
            ? const [
                BoxShadow(color: Palette.outlineShadow, offset: Offset(0, 4)),
              ]
            : null,
      ),
      child: Row(
        children: [
          _NumberChip(
            number: level.number,
            current: current,
            locked: !unlocked,
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
                    color: current ? Colors.white : ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: current
                        ? Colors.white.withValues(alpha: 0.85)
                        : Palette.uiTextDim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!unlocked)
            Icon(
              Icons.lock_rounded,
              size: 19,
              color: Palette.uiTextDim.withValues(alpha: 0.55),
            )
          else ...[
            _Stars(stars: stars, onAccent: current),
            // The one row on the whole ladder you can press right now says so.
            //
            // Every unlocked row is tappable, but only this one is the level
            // the campaign is actually offering, and colour alone was carrying
            // that — which is nothing to a colourblind player and not much to
            // anyone scrolling fast. A glyph is the cheapest way to say
            // "here", and it costs the row no height.
            if (current) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.play_arrow_rounded,
                size: 24,
                color: Colors.white,
              ),
            ],
          ],
        ],
      ),
    );

    // A locked row is not pressable, so it gets no press animation either —
    // a tile that squashes under a finger and then does nothing is a worse
    // answer than one that does not move.
    return unlocked ? PressScale(onTap: onPlay, child: tile) : tile;
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
    final parts = <String>[?arenaName];
    if (level.botCardLevel > 1) parts.add('cards level ${level.botCardLevel}');
    if (reward case final extra?) parts.add(extra);
    return parts.join(' · ');
  }
}

class _NumberChip extends StatelessWidget {
  const _NumberChip({
    required this.number,
    required this.current,
    required this.locked,
  });

  final int number;
  final bool current;
  final bool locked;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: current ? Colors.white : Palette.uiSurfaceHigh,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: locked
            ? Palette.outline.withValues(alpha: 0.35)
            : Palette.outline,
        width: 2,
      ),
    ),
    child: Text(
      '$number',
      style: TextStyle(
        color: locked ? Palette.uiTextDim : Palette.uiText,
        fontSize: number > 999 ? 13 : 15,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
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
