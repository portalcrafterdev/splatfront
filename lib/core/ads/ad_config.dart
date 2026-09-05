import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;

/// Everything about ad placement that can change without a rebuild.
///
/// Section 10 of `CLAUDE.md` said no ads in v1. That was reversed on the
/// owner's call; this file and `assets/data/ads.json` are where the reversal
/// is tuned, so backing any of it out is a JSON edit rather than a code
/// change — the same rule the balance numbers follow.
class AdConfig {
  const AdConfig({
    required this.enabled,
    required this.banner,
    required this.interstitial,
    required this.rewarded,
  });

  /// The master switch. False and nothing loads, shows, or allocates.
  final bool enabled;

  final BannerConfig banner;
  final InterstitialConfig interstitial;
  final RewardedConfig rewarded;

  /// What the app runs with before `ads.json` is read, and what it keeps if
  /// reading fails. Off, on purpose: an ad layer that silently switches
  /// itself on when its own config is unreadable is not a thing anyone can
  /// debug.
  static const AdConfig off = AdConfig(
    enabled: false,
    banner: BannerConfig.off,
    interstitial: InterstitialConfig.off,
    rewarded: RewardedConfig.off,
  );

  static Future<AdConfig> load() async {
    try {
      final raw = await rootBundle.loadString('assets/data/ads.json');
      return AdConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Section 16: fully playable with no network and no surprises. A
      // missing or malformed ads.json takes the ads away, never the game.
      return AdConfig.off;
    }
  }

  factory AdConfig.fromJson(Map<String, dynamic> json) => AdConfig(
    enabled: json['enabled'] as bool? ?? false,
    banner: BannerConfig.fromJson(
      json['banner'] as Map<String, dynamic>? ?? const {},
    ),
    interstitial: InterstitialConfig.fromJson(
      json['interstitial'] as Map<String, dynamic>? ?? const {},
    ),
    rewarded: RewardedConfig.fromJson(
      json['rewarded'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

class BannerConfig {
  const BannerConfig({
    required this.enabled,
    required this.unitId,
    required this.inMenus,
    required this.inMatch,
  });

  final bool enabled;
  final String unitId;
  final bool inMenus;
  final bool inMatch;

  static const BannerConfig off = BannerConfig(
    enabled: false,
    unitId: '',
    inMenus: false,
    inMatch: false,
  );

  factory BannerConfig.fromJson(Map<String, dynamic> json) => BannerConfig(
    enabled: json['enabled'] as bool? ?? false,
    unitId: json['unitId'] as String? ?? '',
    inMenus: json['inMenus'] as bool? ?? false,
    inMatch: json['inMatch'] as bool? ?? false,
  );
}

class InterstitialConfig {
  const InterstitialConfig({
    required this.enabled,
    required this.unitId,
    required this.everyNthStart,
    required this.minSecondsBetween,
    required this.skipFirstSession,
    required this.afterMatchInstead,
  });

  final bool enabled;
  final String unitId;

  /// Show on every Nth level start. 1 is every one, which is what the owner
  /// asked for; a match is 90 seconds, so that is an ad roughly every 90
  /// seconds of play.
  final int everyNthStart;

  /// A hard floor between two interstitials whatever the count says, so
  /// quitting and restarting a level cannot chain ads back to back.
  final int minSecondsBetween;

  /// Never on the first level of a fresh launch.
  final bool skipFirstSession;

  /// Move it from the start of a match to the end of one. Same frequency,
  /// but it stops blocking the thing the player just pressed.
  final bool afterMatchInstead;

  static const InterstitialConfig off = InterstitialConfig(
    enabled: false,
    unitId: '',
    everyNthStart: 1,
    minSecondsBetween: 45,
    skipFirstSession: true,
    afterMatchInstead: false,
  );

  factory InterstitialConfig.fromJson(Map<String, dynamic> json) =>
      InterstitialConfig(
        enabled: json['enabled'] as bool? ?? false,
        unitId: json['unitId'] as String? ?? '',
        // Zero or a negative would mean "show on every start and also divide
        // by zero", so the floor is 1.
        everyNthStart: ((json['everyNthStart'] as num?)?.toInt() ?? 1).clamp(
          1,
          1000,
        ),
        minSecondsBetween: (json['minSecondsBetween'] as num?)?.toInt() ?? 45,
        skipFirstSession: json['skipFirstSession'] as bool? ?? true,
        afterMatchInstead: json['afterMatchInstead'] as bool? ?? false,
      );
}

class RewardedConfig {
  const RewardedConfig({
    required this.enabled,
    required this.unitId,
    required this.chestSkipMinutes,
  });

  final bool enabled;
  final String unitId;

  /// How much time one watched ad takes off a chest timer.
  ///
  /// Four hours, on the owner's call, and the two worked examples are the
  /// spec: a Magic chest at eight hours takes two ads — four off, then the
  /// remaining four — and a Wood chest at three minutes takes one, because a
  /// single reduction already covers everything left.
  ///
  /// It is a flat amount rather than a fraction of the chest, which is what
  /// makes the short chests a single watch. The consequence worth knowing is
  /// that Silver (8 min) and Gold (3 h) are also one ad each; only Magic ever
  /// asks for two. Lower this and the longer chests start costing more
  /// watches.
  final int chestSkipMinutes;

  Duration get chestSkip => Duration(minutes: chestSkipMinutes);

  static const RewardedConfig off = RewardedConfig(
    enabled: false,
    unitId: '',
    chestSkipMinutes: 240,
  );

  factory RewardedConfig.fromJson(Map<String, dynamic> json) => RewardedConfig(
    enabled: json['enabled'] as bool? ?? false,
    unitId: json['unitId'] as String? ?? '',
    chestSkipMinutes:
        (json['chestSkipMinutes'] as num?)?.toInt() ?? 240,
  );
}

/// Google's own always-fill test units, and the rule for when to use them.
///
/// **Debug builds never touch a live unit id.** Tapping your own live ad is
/// invalid traffic, and AdMob suspends accounts for it — which, on a game
/// that gets driven from a laptop onto a phone twenty times an afternoon, is
/// not a theoretical risk. The switch is on [kDebugMode] rather than on a
/// flag someone has to remember to set, so it cannot be got wrong.
abstract final class AdUnits {
  static const String _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  /// True when the app is serving Google's test ads rather than real ones.
  static bool get usingTestAds => kDebugMode;

  static String banner(String live) => kDebugMode ? _testBanner : live;

  static String interstitial(String live) =>
      kDebugMode ? _testInterstitial : live;

  static String rewarded(String live) => kDebugMode ? _testRewarded : live;
}
