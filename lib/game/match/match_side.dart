import '../../core/palette.dart';
import '../cards/card_registry.dart';
import '../cards/elixir_bar.dart';
import '../cards/hand_controller.dart';

/// One side of a match: its colour, its elixir and its rotation.
///
/// The player and the bot are the same shape, so the deploy rule, the elixir
/// cost and the card rotation all run through one code path for both. The bot
/// gets no discount and no special case.
class MatchSide {
  MatchSide({
    required this.team,
    required Deck? deck,
    CardLevels? levels,
    double cardRefillSeconds = 0,
  }) : elixir = ElixirBar(),
       hand = deck == null
           ? null
           : HandController(
               deck: deck,
               levels: levels ?? const CardLevels(),
               refillSeconds: cardRefillSeconds,
             );

  final Team team;
  final ElixirBar elixir;

  /// Null only for a side with no cards at all, which is what the debug
  /// sandboxes use.
  final HandController? hand;

  bool get hasHand => hand != null;

  void reset() {
    elixir.reset();
    hand?.reset();
  }

  void dispose() {
    elixir.dispose();
    hand?.dispose();
  }
}
