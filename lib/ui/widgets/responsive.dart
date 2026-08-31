import 'package:flutter/widgets.dart';

/// Layout classes from section 11 of the spec. Phone portrait is the primary
/// target; everything else is a variation on it.
enum LayoutClass {
  /// Under 600 dp wide.
  phone,

  /// 600 to 900 dp wide.
  tabletPortrait,

  /// Over 900 dp wide: arena centred and letterboxed, hand on a side rail.
  tabletWide,
}

class Breakpoints {
  const Breakpoints._();

  static const double tablet = 600;
  static const double wide = 900;

  /// The arena is never stretched past this. A wider aspect would change every
  /// deploy distance in the game.
  static const double maxArenaWidth = 620;

  static LayoutClass of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  static LayoutClass forWidth(double width) {
    if (width >= wide) return LayoutClass.tabletWide;
    if (width >= tablet) return LayoutClass.tabletPortrait;
    return LayoutClass.phone;
  }
}

extension LayoutClassX on LayoutClass {
  bool get isPhone => this == LayoutClass.phone;
  bool get isWide => this == LayoutClass.tabletWide;

  /// Hand cards move to a vertical right-hand rail on wide layouts.
  bool get handIsSideRail => this == LayoutClass.tabletWide;

  /// Card width in the hand.
  double get handCardWidth => switch (this) {
    LayoutClass.phone => 78,
    LayoutClass.tabletPortrait => 110,
    LayoutClass.tabletWide => 110,
  };

  double get handGap => switch (this) {
    LayoutClass.phone => 6,
    LayoutClass.tabletPortrait => 12,
    LayoutClass.tabletWide => 14,
  };

  /// Columns in the collection grid.
  int get collectionColumns => switch (this) {
    LayoutClass.phone => 3,
    LayoutClass.tabletPortrait => 4,
    LayoutClass.tabletWide => 5,
  };

  double get elixirBarHeight => switch (this) {
    LayoutClass.phone => 14,
    LayoutClass.tabletPortrait => 18,
    LayoutClass.tabletWide => 18,
  };
}

/// Rebuilds its child against the current [LayoutClass].
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, LayoutClass layout) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, Breakpoints.of(context));
}
