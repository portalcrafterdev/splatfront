import 'package:flutter/material.dart';

import '../../core/audio.dart';
import '../../core/palette.dart';
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
    bottomNavigationBar: _BottomBar(
      tabs: _tabs,
      index: _index,
      onSelect: _select,
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
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Palette.uiSurface,
      border: Border(
        top: BorderSide(color: Palette.outline, width: Panel.stroke),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
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
    final ink = selected ? Palette.uiText : Palette.uiTextDim;

    return PressScale(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The selected tab gets a filled, outlined pill behind its icon.
          // Colour alone is a weak signal at this size, and the pill is the
          // same chunky shape language as every other control.
          AnimatedContainer(
            duration: Motion.release,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? Palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? Palette.outline : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              tab.icon,
              size: 20,
              color: selected ? Colors.white : ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tab.label,
            style: TextStyle(
              color: ink,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
