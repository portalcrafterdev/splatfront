import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../audio.dart';
import 'ad_config.dart';

/// The app's one door to AdMob.
///
/// Deliberately static and deliberately forgiving, the same way [Audio] is.
/// Three rules hold everywhere in here:
///
/// **Inert until started.** Nothing loads, and no platform channel is
/// touched, until [start] is called from `main`. The widget suite never calls
/// it, so 397 tests keep running offline and an ad SDK can never be the
/// reason one of them hangs.
///
/// **Nothing here is allowed to throw.** An ad that fails to fill, a device
/// with no network, a malformed config — all of it has to end in the player
/// simply not seeing an ad. Section 16 of `CLAUDE.md` requires the game to be
/// fully playable with no network connection, and that is not a promise an
/// ad layer gets to break.
///
/// **Nothing loads during a match.** This app has already been killed by
/// Android once for main-thread pressure: an unpooled sound per shot filled
/// the `DartMessenger` queue past 150,000 pending callbacks and the ANR trace
/// sat in `handleMessageFromDart`. Ad loading is platform-channel work of
/// exactly that kind, so the interstitial is fetched while a menu is idle and
/// only ever *shown* at a transition. [matchRunning] is the interlock.
abstract final class Ads {
  static AdConfig _config = AdConfig.off;
  static bool _started = false;

  /// Set while an arena is live. Blocks every load, so no ad request is in
  /// flight while the game is asking for sixty frames a second.
  static bool matchRunning = false;

  static AdConfig get config => _config;
  static bool get isStarted => _started;

  /// True when ads are on at all. Everything else checks this first.
  static bool get enabled => _started && _config.enabled;

  // --- Interstitial pacing -------------------------------------------------

  static InterstitialAd? _interstitial;
  static bool _interstitialLoading = false;
  static int _levelStarts = 0;
  static DateTime? _lastShown;

  /// Completed when the in-flight load settles, either way.
  static Completer<void>? _loadWaiter;

  /// How long a level start will wait for an ad that is due but not yet
  /// loaded.
  ///
  /// Zero was the original behaviour and it is why ads were missing: an ad
  /// takes a second or two to fetch, and the gap between leaving one level
  /// and starting the next is nearly nothing when the end screen offers NEXT
  /// LEVEL. The pacing said show, the slot was empty, and the start went
  /// through with nothing.
  ///
  /// Four seconds is a compromise, not a target. It is long enough that a
  /// normal fetch lands and short enough that a player on a bad connection
  /// is not left staring at a dead button. It is only ever spent when an ad
  /// is actually due.
  static const Duration _loadWait = Duration(seconds: 4);

  /// Level starts seen this launch, which is what `skipFirstSession` reads.
  @visibleForTesting
  static int get levelStarts => _levelStarts;

  /// Boots the SDK and reads `ads.json`. Safe to call twice; safe to call on
  /// a device with no network. Never throws.
  static Future<void> start() async {
    if (_started) return;
    try {
      _config = await AdConfig.load();
      if (!_config.enabled) {
        // Still counts as started: the getters have to return real answers
        // so callers can lay out without an ad slot.
        _started = true;
        return;
      }
      await MobileAds.instance.initialize();
      _started = true;
      _preloadInterstitial();
    } catch (error) {
      debugPrint('Ads.start failed, running without ads: $error');
      _config = AdConfig.off;
      _started = true;
    }
  }

  /// Whether a banner should be built into the layout right now.
  static bool bannerIn({required bool match}) {
    if (!enabled || !_config.banner.enabled) return false;
    return match ? _config.banner.inMatch : _config.banner.inMenus;
  }

  static String get bannerUnitId => AdUnits.banner(_config.banner.unitId);

  // --- Interstitial --------------------------------------------------------

  /// Fetches the next interstitial if there is not one waiting.
  ///
  /// Called from Home rather than from the battle route, so the fetch happens
  /// while the player is reading a menu and not while a match is starting.
  static void _preloadInterstitial() {
    final cfg = _config.interstitial;
    if (!enabled || !cfg.enabled) return;
    if (_interstitial != null || _interstitialLoading) return;
    if (matchRunning) return;

    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdUnits.interstitial(cfg.unitId),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
          _settleWaiter();
        },
        onAdFailedToLoad: (error) {
          // No retry loop on purpose. A device with no network would spin one
          // forever, and the next natural transition asks again anyway.
          _interstitialLoading = false;
          _interstitial = null;
          debugPrint('Interstitial failed to load: ${error.code}');
          _settleWaiter();
        },
      ),
    );
  }

  /// Releases anything waiting on the in-flight load, loaded or failed.
  static void _settleWaiter() {
    final waiter = _loadWaiter;
    _loadWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// Waits a bounded time for an interstitial that is due but not ready.
  ///
  /// Only called once the pacing rules have already said yes, so the wait is
  /// never spent on a start that was not going to show an ad anyway.
  static Future<void> _waitForLoad() async {
    if (_interstitial != null) return;
    _preloadInterstitial();
    // Nothing actually in flight — ads off, or a load that failed instantly.
    // Waiting on that would just burn four seconds for nothing.
    if (!_interstitialLoading) return;
    final waiter = _loadWaiter ??= Completer<void>();
    await waiter.future.timeout(_loadWait, onTimeout: () {});
  }

  /// Warms the next interstitial. Call from a menu, never from a match.
  static void prefetch() => _preloadInterstitial();

  /// True when the pacing rules allow an interstitial right now.
  ///
  /// Split out from [maybeShowOnLevelStart] so the rules can be tested
  /// without an SDK anywhere near them.
  @visibleForTesting
  static bool shouldShowOnLevelStart({
    required int startsSoFar,
    required DateTime now,
    DateTime? lastShown,
  }) {
    final cfg = _config.interstitial;
    if (!enabled || !cfg.enabled || cfg.afterMatchInstead) return false;
    // The very first level of a launch is the one that decides whether a new
    // player stays. `startsSoFar` is the count *before* this start.
    if (cfg.skipFirstSession && startsSoFar == 0) return false;
    if (startsSoFar % cfg.everyNthStart != 0) return false;
    if (lastShown != null &&
        now.difference(lastShown).inSeconds < cfg.minSecondsBetween) {
      return false;
    }
    return true;
  }

  /// Shows an interstitial if one is loaded and the pacing allows it, then
  /// returns once it is gone. Always completes — a missing ad returns at once.
  ///
  /// The caller awaits this *before* building the arena, so the ad is never
  /// on screen over a running game loop.
  static Future<void> maybeShowOnLevelStart() async {
    // A level is starting, so by definition no arena is live yet — and the
    // one that was is already being torn down. Clearing the interlock here
    // matters for NEXT LEVEL off the end screen: that pops the battle route
    // and starts the next level in the same breath, and the old screen's
    // `dispose` has not necessarily run, so this flag was still true and was
    // silently blocking the very load the next line asks for.
    matchRunning = false;

    final startsSoFar = _levelStarts;
    _levelStarts++;

    if (!shouldShowOnLevelStart(
      startsSoFar: startsSoFar,
      now: DateTime.now(),
      lastShown: _lastShown,
    )) {
      _preloadInterstitial();
      return;
    }

    // Due, so it is worth a short wait if the fetch has not landed. Without
    // this the ad was simply skipped whenever the gap between levels was
    // shorter than a network round trip, which off the end screen is always.
    await _waitForLoad();

    final ad = _interstitial;
    if (ad == null) {
      // Still nothing after the wait — no fill, or no network. The player
      // goes straight into the match rather than being held any longer.
      _preloadInterstitial();
      return;
    }
    _interstitial = null;
    _lastShown = DateTime.now();
    await _show(ad);
  }

  /// The end-of-match variant, used when `afterMatchInstead` is true.
  static Future<void> maybeShowAfterMatch() async {
    final cfg = _config.interstitial;
    if (!enabled || !cfg.enabled || !cfg.afterMatchInstead) return;
    if (_lastShown != null &&
        DateTime.now().difference(_lastShown!).inSeconds <
            cfg.minSecondsBetween) {
      return;
    }
    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }
    _interstitial = null;
    _lastShown = DateTime.now();
    await _show(ad);
  }

  /// Puts a loaded interstitial on screen and waits for it to close.
  ///
  /// The music is suspended for the duration. An ad brings its own audio, and
  /// the menu loop playing underneath a video is the kind of thing nobody
  /// notices in review and everybody notices on a phone.
  static Future<void> _show(InterstitialAd ad) async {
    final done = Completer<void>();
    void finish() {
      Audio.handleLifecycleState(AppLifecycleState.resumed);
      if (!done.isCompleted) done.complete();
      _preloadInterstitial();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        debugPrint('Interstitial failed to show: ${error.code}');
        finish();
      },
    );

    try {
      Audio.handleLifecycleState(AppLifecycleState.paused);
      await ad.show();
    } catch (error) {
      debugPrint('Interstitial show threw: $error');
      finish();
    }
    // A show that never calls back would strand the caller on a black screen
    // with no way into the match, so the wait is bounded.
    await done.future.timeout(const Duration(seconds: 30), onTimeout: finish);
  }

  /// Drops everything held. For tests and for a clean shutdown.
  @visibleForTesting
  static void reset() {
    _interstitial?.dispose();
    _interstitial = null;
    _interstitialLoading = false;
    _levelStarts = 0;
    _lastShown = null;
    _config = AdConfig.off;
    _started = false;
    matchRunning = false;
  }

  /// Installs a config directly, for tests of the pacing rules.
  @visibleForTesting
  static void debugConfigure(AdConfig config) {
    _config = config;
    _started = true;
  }
}
