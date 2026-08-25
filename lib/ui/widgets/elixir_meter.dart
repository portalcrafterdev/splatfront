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
              const SizedBox(width: 6),
              SizedBox(
                width: 22,
                child: Text(
                  '$full',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: amount >= ElixirSpec.max
                        ? Palette.elixir
                        : Palette.hudTextDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
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
            const ColoredBox(color: Palette.hudSurface),
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
