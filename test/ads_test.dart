import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/ads/ad_config.dart';
import 'package:splatfront/core/ads/ads.dart';

/// Section 10 of `CLAUDE.md` said no ads in v1. That was reversed on the
/// owner's call, and these are the parts of the reversal that fail silently
/// if they rot: an ad layer that switches itself on in tests, a live unit id
/// reaching a debug build, or a pacing rule that lets two ads run back to
/// back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Ads.reset);

  group('the suite never runs ads', () {
    test('Ads is inert until something calls start', () {
      // The guarantee the whole widget suite rests on. `Ads.start` is called
      // from main() and nowhere else, so in a test nothing here has ever run
      // — no SDK init, no platform channel, no network. If this ever flips,
      // 397 tests start depending on an ad server being reachable.
      expect(Ads.isStarted, isFalse);
      expect(Ads.enabled, isFalse);
      expect(Ads.bannerIn(match: false), isFalse);
      expect(Ads.bannerIn(match: true), isFalse);
    });

    test('a banner slot asks for nothing while ads are off', () {
      // AdBanner builds a zero-sized box on this, so a menu in a test never
      // constructs a BannerAd and never needs a platform channel to answer.
      Ads.debugConfigure(AdConfig.off);
      expect(Ads.bannerIn(match: false), isFalse);
      expect(Ads.bannerIn(match: true), isFalse);
    });
  });

  group('debug builds never touch a live unit id', () {
    // Tapping your own live ad is invalid traffic and AdMob suspends accounts
    // for it. This app gets driven onto a phone dozens of times an afternoon
    // in debug, so the switch has to be automatic rather than remembered.
    const live = 'ca-app-pub-8244651657160773/7539597097';

    test('test units stand in for live ones under kDebugMode', () {
      // Tests run in debug, so this is the branch that must be active here.
      expect(AdUnits.usingTestAds, isTrue);
      expect(AdUnits.banner(live), isNot(live));
      expect(AdUnits.banner(live), startsWith('ca-app-pub-3940256099942544/'));
      expect(
        AdUnits.interstitial(live),
        startsWith('ca-app-pub-3940256099942544/'),
      );
      expect(AdUnits.rewarded(live), startsWith('ca-app-pub-3940256099942544/'));
    });
  });

  group('ads.json', () {
    test('parses, and carries the ids the owner supplied', () async {
      final raw = await rootBundle.loadString('assets/data/ads.json');
      final config = AdConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );

      expect(config.enabled, isTrue);
      // The unit ids all belong to one publisher account. A digit wrong here
      // is an ad that never fills and no error anywhere to say why.
      for (final id in [
        config.banner.unitId,
        config.interstitial.unitId,
        config.rewarded.unitId,
      ]) {
        expect(id, startsWith('ca-app-pub-8244651657160773/'));
      }
      // All three must be different units. Reusing one across formats is a
      // policy violation and reports as a single blended number.
      expect(
        {
          config.banner.unitId,
          config.interstitial.unitId,
          config.rewarded.unitId,
        },
        hasLength(3),
      );
    });

    test('the shipped config really does mean every level start', () async {
      // The owner asked for an interstitial on every new start and was not
      // getting one. Two settings in here were suppressing some of them, and
      // both are easy to reinstate by accident, so the intent is pinned.
      final raw = await rootBundle.loadString('assets/data/ads.json');
      final cfg = AdConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>)
          .interstitial;

      expect(cfg.enabled, isTrue);
      expect(cfg.everyNthStart, 1, reason: 'every start, not every Nth');
      expect(
        cfg.skipFirstSession,
        isFalse,
        reason: 'the first level of a launch is a start too',
      );
      expect(
        cfg.afterMatchInstead,
        isFalse,
        reason: 'the ask was the start of a level, not the end of one',
      );
      // Not zero: back-to-back ads from quit-and-restart are both miserable
      // and something Google throttles serving over. Low enough that a real
      // match, at 90 seconds, always clears it.
      expect(cfg.minSecondsBetween, greaterThan(0));
      expect(cfg.minSecondsBetween, lessThan(90));
    });

    test('a broken config takes the ads away, never the game', () async {
      // Section 16: fully playable with no network. Malformed JSON, a missing
      // file, a half-written key — every one of them has to land on "off".
      expect(AdConfig.fromJson(const {}).enabled, isFalse);
      expect(AdConfig.fromJson(const {'enabled': true}).banner.enabled, isFalse);
      expect(
        AdConfig.fromJson(const {'enabled': true}).interstitial.enabled,
        isFalse,
      );
    });

    test('everyNthStart can never be zero', () {
      // It is a modulus divisor. A zero in the JSON would throw on the first
      // level start of the session rather than showing an ad.
      final zero = InterstitialConfig.fromJson(const {'everyNthStart': 0});
      expect(zero.everyNthStart, greaterThanOrEqualTo(1));
      final negative = InterstitialConfig.fromJson(const {
        'everyNthStart': -4,
      });
      expect(negative.everyNthStart, greaterThanOrEqualTo(1));
    });
  });

  group('interstitial pacing', () {
    AdConfig withInterstitial({
      int everyNth = 1,
      int minSeconds = 45,
      bool skipFirst = true,
      bool afterMatch = false,
    }) => AdConfig(
      enabled: true,
      banner: BannerConfig.off,
      interstitial: InterstitialConfig(
        enabled: true,
        unitId: 'x',
        everyNthStart: everyNth,
        minSecondsBetween: minSeconds,
        skipFirstSession: skipFirst,
        afterMatchInstead: afterMatch,
      ),
      rewarded: RewardedConfig.off,
    );

    final now = DateTime(2026, 9, 5, 12);

    test('the first level of a launch is never interrupted', () {
      // An ad before anyone has seen the game once is the single biggest
      // driver of a one-star review, and it is the one impression that costs
      // more than it earns.
      Ads.debugConfigure(withInterstitial());
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 0, now: now), isFalse);
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 1, now: now), isTrue);
    });

    test('every start after that, at everyNthStart 1', () {
      // What the owner asked for. Worth seeing written down: a match is 90
      // seconds, so this is an ad roughly every 90 seconds of play.
      Ads.debugConfigure(withInterstitial());
      for (var n = 1; n < 6; n++) {
        expect(
          Ads.shouldShowOnLevelStart(startsSoFar: n, now: now),
          isTrue,
          reason: 'start $n',
        );
      }
    });

    test('raising everyNthStart thins it out without a rebuild', () {
      Ads.debugConfigure(withInterstitial(everyNth: 3));
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 3, now: now), isTrue);
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 4, now: now), isFalse);
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 5, now: now), isFalse);
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 6, now: now), isTrue);
    });

    test('the cooldown outranks the count', () {
      // Quitting a level and restarting it repeatedly must not chain ads back
      // to back, however the count falls.
      Ads.debugConfigure(withInterstitial(minSeconds: 45));
      expect(
        Ads.shouldShowOnLevelStart(
          startsSoFar: 4,
          now: now,
          lastShown: now.subtract(const Duration(seconds: 20)),
        ),
        isFalse,
        reason: '20s after the last one is inside the floor',
      );
      expect(
        Ads.shouldShowOnLevelStart(
          startsSoFar: 4,
          now: now,
          lastShown: now.subtract(const Duration(seconds: 60)),
        ),
        isTrue,
      );
    });

    test('afterMatchInstead moves it off the level start entirely', () {
      // The escape hatch for the frequency, and it has to actually silence
      // the start-of-level path rather than doubling up with it.
      Ads.debugConfigure(withInterstitial(afterMatch: true));
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 5, now: now), isFalse);
    });

    test('nothing shows while the master switch is off', () {
      Ads.debugConfigure(AdConfig.off);
      expect(Ads.shouldShowOnLevelStart(startsSoFar: 9, now: now), isFalse);
    });
  });
}
