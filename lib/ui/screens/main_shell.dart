import 'package:flutter/material.dart';

import '../../core/audio.dart';
import '../../core/palette.dart';
import '../widgets/ad_banner.dart';
import '../widgets/motion.dart';
import 'campaign_screen.dart';
import 'collection_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

/// The app's five places, and the bar that switches between them.
///
/// Home used to carry everything: the chests, the opponent picker, the battle
/// button, a row of links to three other screens and the day's quests, all
/// stacked down one page. Collection, Shop and Settings are destinations
/// rather than actions, and putting them in a bar takes a whole row off the
/// home screen and makes them reachable from anywhere instead of only from
/// the top of the stack.
///
/// Only the selected tab is built, rather than keeping them all alive in an
/// [IndexedStack]. Every screen reads its state from Riverpod, so nothing is
/// lost by rebuilding, and an IndexedStack would leave the other tabs sitting
/// in the widget tree — findable, testable and, worse, all answering to the
/// same text at once.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const List<_Tab> _tabs = [
    _Tab(icon: Icons.home_rounded, label: 'Home'),
    _Tab(icon: Icons.flag_rounded, label: 'Levels'),
    _Tab(icon: Icons.style_rounded, label: 'Cards'),
    _Tab(icon: Icons.storefront_rounded, label: 'Shop'),
    _Tab(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  void _select(int next) {
    if (next == _index) return;
    Audio.play(Sfx.uiTap);
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.uiBackground,
    body: switch (_index) {
      1 => const CampaignScreen(),
      2 => const CollectionScreen(),
      3 => const ShopScreen(),
      4 => const SettingsScreen(),
      _ => const HomeScreen(),
    },
    // The menu banner rides directly above the nav bar rather than inside
    // each screen, so it is one slot for all five tabs and switching tabs
    // does not tear it down and reload it — a banner that reloads on every
    // tap is both worse to look at and worse for fill.
    //
    // Bottom is safe here in a way it is not in a match: nothing on a menu is
    // dragged, so there is no gesture that can end on an ad by accident.
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AdBanner(inMatch: false),
        _BottomBar(tabs: _tabs, index: _index, onSelect: _select),
      ],
    ),
  );
}

class _Tab {
  const _Tab({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// The bar itself, drawn to match the rest of the menus rather than using
/// [NavigationBar], which brings its own Material 3 look and would be the one
/// stock-looking thing in the app.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tabs,
    required this.index,
    required this.onSelect,
  });

  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // Palette.outline is a *shape* edge: it wraps a tile on all four sides
    // and, with the flat shadow under it, reads as a chunky object. Stretched
    // into a single full-width rule it stops being an edge and becomes a
    // black crack across the bottom of the screen, which is what this used to
    // be. The bar is a raised surface rather than a tile, so it gets the
    // treatment every other surface gets — a gradient lighter at the top, so
    // the light source stays overhead, and a soft lift that puts it above the
    // page instead of butted against it. The hairline is only there to stop
    // the two near-white tones bleeding into each other.
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Palette.uiSurfaceHigh, Palette.uiSurface],
      ),
      border: Border(top: BorderSide(color: Color(0x1A15201C), width: 1)),
      boxShadow: [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 14,
          offset: Offset(0, -3),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: _BarItem(
                  tab: tabs[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? Palette.accent : Palette.uiTextDim;

    return PressScale(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The selected tab gets a filled pill behind its icon. Colour alone
          // is a weak signal at this size. It keeps the flat offset shadow the
          // rest of the app uses to make a control feel physical, but drops
          // the black stroke: a 2px outline around a 28pt pill is most of the
          // pill, and five of them in a row is where the bar went muddy.
          AnimatedContainer(
            duration: Motion.release,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? Palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Palette.accentShade,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : const [],
            ),
            child: Icon(
              tab.icon,
              size: 21,
              color: selected ? Colors.white : ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            tab.label,
            style: TextStyle(
              color: ink,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
