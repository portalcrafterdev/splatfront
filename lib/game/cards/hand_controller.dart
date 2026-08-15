import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import 'card_registry.dart';

/// The hand of four plus the next-card preview.
///
/// Playing anything locks the whole hand for [refillSeconds], so a turn is
/// one card rather than as many as the elixir bar can pay for.
///
/// Classic rotation, no random redraw. The deck is a cycle of eight: four sit
/// in the hand and the rest queue behind them, front first. Playing a card
/// sends it to the back and pulls the front of the queue into **the slot it
/// vacated** — the other three cards do not move. That keeps the cycle
/// countable, which is the point, and stops a card sliding out from under a
/// finger mid-drag.
class HandController {
  HandController({
    required this.deck,
    required this.levels,
    this.refillSeconds = 0,
  }) {
    reset();
  }

  final Deck deck;
  final CardLevels levels;

  /// How long the whole hand stays locked after any card is played.
  ///
  /// Every slot goes at once, not just the one you spent. The replacement
  /// card appears immediately — you can see what is coming — but nothing can
  /// be played until the lockout runs out. Zero restores the original
  /// behaviour, where cards were limited only by elixir.
  final double refillSeconds;

  /// The four slots, in the order they sit on screen.
  late List<String> _slots;

  /// The rest of the deck, front first. The front is the preview.
  late List<String> _pending;

  /// The four playable slots, by card id.
  final ValueNotifier<List<String>> hand = ValueNotifier(const []);

  /// The card that will fill whichever slot is played next.
  final ValueNotifier<String> next = ValueNotifier('');

  int get handSize => ElixirSpec.handSize;

  /// The whole rotation as it currently stands, hand first. Test-facing.
  List<String> get queue => List.unmodifiable([..._slots, ..._pending]);

  String cardIdAt(int slot) => _slots[slot];

  int levelOf(String cardId) => levels.of(cardId);

  // --- The lockout ---------------------------------------------------------

  /// Seconds until the hand can be played again. Zero means it is open.
  ///
  /// One number for the whole hand rather than one per slot: playing any card
  /// locks all four. That makes a card a commitment — you get one play every
  /// [refillSeconds], so *which* card matters far more than how many you can
  /// afford, and neither side can dump a full hand into one push.
  double _lockout = 0;

  /// True when [slot] may be played right now. The answer is the same for
  /// every slot; the argument is kept so callers read naturally and so a
  /// future per-slot rule would not change every call site.
  bool isReady(int slot) =>
      slot >= 0 && slot < handSize && _lockout <= 0;

  /// Seconds left on the lockout.
  double secondsLeft(int slot) => _lockout;

  /// How much of the lockout is left, 1 down to 0. What the shutter on the
  /// card is drawn from.
  double cooldownFraction(int slot) {
    if (refillSeconds <= 0) return 0;
    return (_lockout / refillSeconds).clamp(0.0, 1.0);
  }

  /// True while the hand is locked.
  bool get hasCooldowns => _lockout > 0;

  /// Runs the lockout down. Called once a frame by the game.
  void update(double dt) {
    if (refillSeconds <= 0 || _lockout <= 0) return;
    _lockout -= dt;
    if (_lockout <= 0) {
      _lockout = 0;
      // Republished only on the frame the hand reopens, not every frame of
      // the countdown.
      _publish();
    }
  }

  /// Sends the card in [slot] to the back, refills that slot from the front
  /// of the queue, and locks the whole hand for [refillSeconds].
  ///
  /// The replacement is visible at once, so you can plan the next play while
  /// you wait for it.
  ///
  /// Returns the id that was played, or null if the slot is out of range or
  /// the hand is locked.
  String? play(int slot) {
    if (slot < 0 || slot >= handSize) return null;
    if (!isReady(slot)) return null;

    final played = _slots[slot];
    _pending.add(played);
    _slots[slot] = _pending.removeAt(0);
    _lockout = refillSeconds;
    _publish();
    return played;
  }

  /// Puts the rotation back to the deck's starting order, lockout cleared.
  void reset() {
    _slots = List<String>.of(deck.cardIds.take(handSize));
    _pending = List<String>.of(deck.cardIds.skip(handSize));
    _lockout = 0;
    _publish();
  }

  void _publish() {
    hand.value = List.unmodifiable(_slots);
    next.value = _pending.isEmpty ? '' : _pending.first;
  }

  void dispose() {
    hand.dispose();
    next.dispose();
  }
}
