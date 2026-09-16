import 'package:flutter/widgets.dart';

import 'coach_mark.dart';
import 'hand_gesture_indicator.dart';

/// The first-match coach marks, in one place so the copy can be read without
/// going through the battle screen's layout code.
///
/// Three steps, and the choice of three is the whole design. The arena has
/// exactly one thing a player can do — drag a card onto the board — and two
/// things they have to be told or the first match makes no sense: that paint
/// is the score, and that elixir is what cards cost. So two steps point, one
/// asks, and it is over before the clock has moved.
///
/// **The match is held while these are up.** It is a 90 second game with a
/// running clock; a coach mark that blocks the hand while that clock counts
/// down teaches the player their first lesson by losing the match for them.
/// [BattleScreen] pauses the engine for the duration — see `_holdForTutorial`.
abstract final class BattleTutorial {
  /// The `TutorialFlags` key. One per sequence.
  static const String id = 'battle_basics';

  static const String scoreStep = 'score';
  static const String elixirStep = 'elixir';
  static const String deployStep = 'deploy';

  static List<CoachMarkStep> steps({
    required GlobalKey header,
    required GlobalKey elixir,
    required GlobalKey hand,
  }) => [
    CoachMarkStep(
      id: scoreStep,
      target: header,
      title: 'Blue is you',
      message:
          'This bar is the score. Whoever has painted more of the board when '
          'the clock runs out wins.',
      advanceOn: CoachMarkAdvance.anywhere,
    ),
    CoachMarkStep(
      id: elixirStep,
      target: elixir,
      title: 'Cards cost elixir',
      message:
          'It fills on its own — and faster the more of the board you hold. '
          'Painting buys the next push.',
      advanceOn: CoachMarkAdvance.anywhere,
    ),
    CoachMarkStep(
      id: deployStep,
      target: hand,
      title: 'Send one in',
      // The rule that is genuinely not guessable, and the reason the other
      // two steps are worth saying at all: you cannot drop a card wherever
      // you like, so painting forward is what extends your reach.
      message:
          'Drag a card up onto your own blue paint. Blue ground only — that '
          'is why taking ground matters.',
      gesture: HandGesture.swipe,
      // Up, out of the tray and onto the board.
      travel: const Offset(0, -110),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
  ];
}
