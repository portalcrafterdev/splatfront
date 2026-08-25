import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splatfront/core/constants.dart';
import 'package:splatfront/core/palette.dart';
import 'package:splatfront/game/arena/paint_sampler.dart';
import 'package:splatfront/ui/widgets/coverage_bar.dart';

void main() {
  const barHeight = 26.0;
  const screenWidth = 800.0;

  Future<ValueNotifier<Coverage>> pumpBar(
    WidgetTester tester,
    Coverage coverage,
  ) async {
    final notifier = ValueNotifier(coverage);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(screenWidth, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topCenter,
            child: CoverageBar(
              coverage: notifier,
              playerTeam: Team.red,
              height: barHeight,
            ),
          ),
        ),
      ),
    );
    // Let the 300ms lerp finish.
    await tester.pump(Timings.coverageLerp + const Duration(milliseconds: 50));
    return notifier;
  }

  /// The rendered box for one team's segment of the bar.
  Size segmentSize(WidgetTester tester, Color colour) => tester.getSize(
    find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == colour,
      description: 'segment $colour',
    ),
  );

  testWidgets('every segment is actually painted, not zero-height', (
    tester,
  ) async {
    await pumpBar(tester, const Coverage(0.5, 0.3));

    // A ColoredBox with no child collapses to zero height unless the Row
    // stretches it, which makes the whole bar invisible on device.
    for (final colour in [Palette.red, Palette.neutral, Palette.blue]) {
      expect(
        segmentSize(tester, colour).height,
        barHeight,
        reason: '$colour segment must fill the bar height',
      );
    }
  });

  testWidgets('red fills from the left in proportion to its coverage', (
    tester,
  ) async {
    await pumpBar(tester, const Coverage(0.75, 0.25));

    expect(
      segmentSize(tester, Palette.red).width,
      closeTo(screenWidth * 0.75, 1.0),
    );
    expect(
      segmentSize(tester, Palette.blue).width,
      closeTo(screenWidth * 0.25, 1.0),
    );
  });

  testWidgets('neutral ground shows as the gap between the two sides', (
    tester,
  ) async {
    await pumpBar(tester, const Coverage(0.4, 0.4));

    expect(
      segmentSize(tester, Palette.neutral).width,
      closeTo(screenWidth * 0.2, 1.0),
    );
  });

  testWidgets('the split point moves when coverage changes', (tester) async {
    final notifier = await pumpBar(tester, const Coverage(0.2, 0.6));
    final before = segmentSize(tester, Palette.red).width;

    notifier.value = const Coverage(0.6, 0.2);
    await tester.pump(); // rebuild, which starts the lerp at t=0
    await tester.pump(Timings.coverageLerp + const Duration(milliseconds: 50));

    expect(segmentSize(tester, Palette.red).width, greaterThan(before));
  });

  testWidgets('a wiped-out side leaves the bar intact', (tester) async {
    await pumpBar(tester, const Coverage(1.0, 0.0));

    expect(
      segmentSize(tester, Palette.red).width,
      closeTo(screenWidth, 1.0),
    );
    // Zero-width is fine; zero-height would mean the bar vanished.
    expect(segmentSize(tester, Palette.blue).height, barHeight);
  });

  testWidgets('percentages are shown for both sides', (tester) async {
    await pumpBar(tester, const Coverage(0.63, 0.31));
    expect(find.text('63%'), findsOneWidget);
    expect(find.text('31%'), findsOneWidget);
  });
}
