import 'package:flutter/material.dart';

import 'core/palette.dart';
import 'ui/tutorial/game_hud_screen.dart';
import 'ui/type.dart';

/// Standalone entry point for the coach-mark demo.
///
///     flutter run -t lib/tutorial_demo_main.dart
///
/// Separate from `main.dart` on purpose: the demo screen is a worked example,
/// not a feature, and keeping it off the app's entry point means Dart never
/// compiles it into the release binary.
void main() => runApp(const TutorialDemoApp());

class TutorialDemoApp extends StatelessWidget {
  const TutorialDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coach marks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: Fonts.body,
        scaffoldBackgroundColor: Palette.uiBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.accent,
          brightness: Brightness.light,
        ).copyWith(surface: Palette.uiSurface, onSurface: Palette.uiText),
        popupMenuTheme: const PopupMenuThemeData(color: Palette.uiSurface),
      ),
      home: const GameHudScreen(),
    );
  }
}
