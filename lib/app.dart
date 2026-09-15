import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/palette.dart';
import 'ui/screens/main_shell.dart';
import 'ui/type.dart';

class SplatfrontApp extends StatelessWidget {
  const SplatfrontApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Splatfront',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Light, matching Palette.ui*. This line is not cosmetic: every
        // Material widget we do not paint ourselves reads it — a slider's
        // unfilled track, a switch, an AlertDialog, a bottom sheet. Left out
        // of step with the palette, those turn up as fragments of the wrong
        // scheme in an otherwise consistent app, which is exactly what
        // happened both times the ground changed.
        brightness: Brightness.light,
        // Set once, here, so every widget that does not name a family gets
        // it. See lib/ui/type.dart: Lexend is the body face and the default;
        // Baloo 2 is the display face and is always asked for by name.
        fontFamily: Fonts.body,
        scaffoldBackgroundColor: Palette.uiBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.accent,
          brightness: Brightness.light,
        ).copyWith(surface: Palette.uiSurface, onSurface: Palette.uiText),
        dialogTheme: const DialogThemeData(backgroundColor: Palette.uiSurface),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Palette.uiSurface,
        ),
        textTheme: Typography.blackMountainView.apply(
          bodyColor: Palette.uiText,
          displayColor: Palette.uiText,
        ),
      ),
      // Dark icons in the status bar, because the menus are light. The
      // battle screen overrides this for itself — it is the one dark place
      // in the app, and dark-on-dark would leave the clock invisible.
      home: const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Palette.uiSurface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: MainShell(),
      ),
    );
  }
}
