import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ads/ads.dart';
import '../../core/palette.dart';

/// A banner slot that takes real layout space, or nothing at all.
///
/// **It never floats over content.** In a match the arena is the thing the
/// player is aiming at, and an ad laid over the board would both hide paint
/// and swallow deploy drags. The slot is a sibling in the column, so the
/// arena scales down inside what is left. That is safe where stretching would
/// not be: section 14 forbids changing the arena's *aspect*, because every
/// deploy distance in the game is measured against it, but the same 2:3 board
/// drawn smaller changes nothing mechanically.
///
/// **It reserves its height before the ad arrives.** A slot that appears when
/// an ad fills would shove the whole page down a second after it settles, and
/// on the battle screen it would resize the arena mid-countdown. The box is
/// there from the first frame or not at all.
///
/// With ads off — which is every widget test, since `Ads.start` is only
/// called from `main` — this builds a zero-sized box and never touches a
/// platform channel.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, required this.inMatch});

  /// Where this slot lives, which decides both whether it appears at all and
  /// which side of the screen it belongs on.
  ///
  /// **In a match the banner goes at the top**, above the coverage bar. Cards
  /// are dragged from the bottom of the battle screen to deploy, and an ad
  /// next to that is an accidental-click generator — AdMob suspends accounts
  /// for invalid traffic, so a bottom banner there puts at risk the revenue
  /// it exists to earn. In menus nothing is dragged and it sits at the
  /// bottom, above the nav bar.
  final bool inMatch;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  /// The whole slot, in both places, and the smallest a banner comes.
  ///
  /// **Fixed rather than adaptive, on the owner's call.** An anchored
  /// adaptive banner fills the width and Google's guidance is that it pays
  /// better, but the only non-deprecated adaptive size in the SDK is the
  /// *large* one, and it reserves up to 15% of the screen height — about
  /// 107dp on the test device. What actually rendered inside it was a 50dp
  /// creative with a band of dead grey above and below, so two thirds of what
  /// it cost the page bought nothing at all. Fifty is what a banner needs.
  static const double _height = 50;

  @override
  void initState() {
    super.initState();
    if (Ads.bannerIn(match: widget.inMatch)) _load();
  }

  void _load() {
    final ad = BannerAd(
      adUnitId: Ads.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // Disposed and forgotten. No retry: an offline device would spin
          // one forever, and the slot simply stays empty, which is what
          // section 16's "fully playable with no network" requires.
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Ads.bannerIn(match: widget.inMatch)) return const SizedBox.shrink();

    final ad = _ad;
    return SizedBox(
      height: _height,
      width: double.infinity,
      child: ColoredBox(
        // The slot is visible as a slot even while empty, so a banner
        // arriving does not read as the layout breaking. Two grounds, because
        // the match and the menus are two different rooms and section 14
        // keeps their palettes apart.
        color: widget.inMatch
            ? Palette.hudBezelLow
            : Palette.uiTextDim.withValues(alpha: 0.06),
        // The ad is given the whole slot rather than a box sized from
        // `ad.size`, so whatever the SDK returns is laid out at the height
        // the slot actually reserved and nothing is cropped.
        child: ad != null && _loaded ? AdWidget(ad: ad) : const SizedBox(),
      ),
    );
  }
}
