import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../game/cards/elixir_bar.dart';

/// Ten discrete segments with a partial fill on the active one, sitting
/// directly above the hand.
///
/// Driven off the [ElixirBar]'s notifier, so nothing above the arena rebuilds.
class ElixirMeter extends StatelessWidget {
  const ElixirMeter({super.key, required this.elixir, this.height = 14});

  final ElixirBar elixir;
  final double height;

  static const int _segments = 10;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: elixir.value,
      builder: (context, amount, _) {
        final full = amount.floor();
        final partial = amount - full;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (var i = 0; i < _segments; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _Segment(
                      height: height,
                      // Whole segments fill completely; the one after them
                      // shows how far the next point has come.
                      fill: i < full
                          ? 1.0
                          : (i == full ? partial.clamp(0.0, 1.0) : 0.0),
                    ),
                  ),
                ),
              const SizedBox(width: 8),

              // The count, as a readout rather than as a stray digit.
              //
              // This was a dim 12pt number pushed hard against the right edge
              // of the screen, which is a poor way to present the one number
              // a player checks before every single play — the bar shows how
              // full you are, but the number is what you compare against a
              // card's cost. On its own chip it stops being an afterthought,
              // and it goes bright at ten so a wasting bar is visible without
              // counting segments.
              _Count(amount: amount, full: full, height: height),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.height, required this.fill});

  final double height;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(3);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Palette.hudOutline.withValues(alpha: 0.16)),
            if (fill > 0)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill,
                child: const ColoredBox(color: Palette.elixir),
              ),
          ],
        ),
      ),
    );
  }
}

/// The elixir count, on a chip keyed to the bar's own colour.
class _Count extends StatelessWidget {
  const _Count({
    required this.amount,
    required this.full,
    required this.height,
  });

  final double amount;
  final int full;
  final double height;

  @override
  Widget build(BuildContext context) {
    final brimming = amount >= ElixirSpec.max;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 30,
      height: height + 6,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brimming
            ? Palette.elixir
            : Palette.elixir.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: brimming
              ? Palette.elixir
              : Palette.elixir.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        '$full',
        style: TextStyle(
          color: brimming ? Colors.white : Palette.elixir,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}
