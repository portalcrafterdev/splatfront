import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio.dart';
import '../../core/games/game_services.dart';
import '../../core/palette.dart';
import '../../core/save/player_profile.dart';
import '../../meta/profile_controller.dart';
import '../widgets/meta_widgets.dart';
import '../widgets/motion.dart';

/// Volume, haptics and language. Every change saves immediately.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);
    final settings = profile.settings;

    return Scaffold(
      backgroundColor: Palette.uiBackground,
      body: MenuBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MetaHeader(
                title: 'Settings',
                profile: profile,
                subtitle: 'Everything here saves as you change it.',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    // Grouped into tiles rather than under tracked-out capitals.
                    // "AUDIO" over a slider labelled Music is a label on a label; the
                    // tile does the grouping and costs no line of text.
                    Panel(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                      child: Column(
                        children: [
                          _VolumeSlider(
                            label: 'Music',
                            value: settings.musicVolume,
                            onChanged: (v) {
                              final next = settings.copyWith(musicVolume: v);
                              controller.updateSettings(next);
                              _applyVolumes(next);
                            },
                          ),
                          _VolumeSlider(
                            label: 'Sound effects',
                            value: settings.sfxVolume,
                            // Previewed on release rather than on every drag frame, so
                            // sliding does not machine-gun the sample.
                            onChangeEnd: (v) => Audio.play(Sfx.uiTap),
                            onChanged: (v) {
                              final next = settings.copyWith(sfxVolume: v);
                              controller.updateSettings(next);
                              _applyVolumes(next);
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Your device volume and its silent switch still win.',
                                style: TextStyle(
                                  color: Palette.uiTextDim,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.haptics,
                        activeThumbColor: Palette.accent,
                        title: const Text(
                          'Haptics',
                          style: TextStyle(color: Palette.uiText, fontSize: 14),
                        ),
                        subtitle: const Text(
                          'A short buzz on deploys and results.',
                          style: TextStyle(
                            color: Palette.uiTextDim,
                            fontSize: 11,
                          ),
                        ),
                        onChanged: (v) => controller.updateSettings(
                          settings.copyWith(haptics: v),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    const _PlayGamesTile(),

                    const SizedBox(height: 12),
                    const Panel(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Language: English',
                          style: TextStyle(color: Palette.uiText, fontSize: 14),
                        ),
                        subtitle: Text(
                          'The only one in this build. Your choice is saved, so it '
                          'survives the build that adds more.',
                          style: TextStyle(
                            color: Palette.uiTextDim,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Icon(
                          Icons.check,
                          color: Palette.success,
                          size: 18,
                        ),
                      ),
                    ),

                    const SizedBox(height: 26),
                    // No "DANGER" heading over it. The button is red, it says what it
                    // does, and it asks before doing it — a shouted label above would
                    // be the fourth thing telling you the same fact.
                    OutlinedButton(
                      onPressed: () => _confirmReset(context, controller),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Palette.danger,
                        side: const BorderSide(color: Palette.danger, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Reset all progress',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pushes the saved numbers into the mixer. The profile is the source of
  /// truth; [Audio] just follows it.
  void _applyVolumes(Settings settings) =>
      Audio.setVolumes(music: settings.musicVolume, sfx: settings.sfxVolume);

  void _confirmReset(BuildContext context, ProfileController controller) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.uiSurface,
        title: const Text(
          'Reset everything?',
          style: TextStyle(color: Palette.uiText),
        ),
        content: const Text(
          'Trophies, coins, cards, chests and your deck all go back to a '
          'fresh start. This cannot be undone.',
          style: TextStyle(color: Palette.uiTextDim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              controller.resetProgress();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Palette.danger),
            child: const Text('RESET'),
          ),
        ],
      ),
    );
  }
}

/// Sign in to Play Games on Android, Game Center on iOS.
///
/// **It is a tile in Settings and not a banner on Home**, because this is a
/// single-player game and the sign-in buys the player nothing they need. It
/// is an account they may want connected, not a step in front of the thing
/// they opened the app to do — and section 14's rule that v1 never pretends
/// to be multiplayer cuts the same way. Nothing here gates a level, a chest
/// or a card.
///
/// The platform name is not hard-coded: the same button says "Play Games" on
/// Android and "Game Center" on iOS, because those are the two things the
/// player will recognise and neither name means anything on the other
/// platform.
class _PlayGamesTile extends StatefulWidget {
  const _PlayGamesTile();

  @override
  State<_PlayGamesTile> createState() => _PlayGamesTileState();
}

class _PlayGamesTileState extends State<_PlayGamesTile> {
  bool _pressed = false;

  String get _serviceName => defaultTargetPlatform == TargetPlatform.iOS
      ? 'Game Center'
      : 'Play Games';

  Future<void> _signIn() async {
    setState(() => _pressed = true);
    final ok = await GameServices.signIn();
    if (!mounted) return;
    setState(() => _pressed = false);
    if (!ok) {
      // Said out loud rather than left as a button that did nothing. The
      // usual cause in a debug build is a signing certificate that is not
      // registered against the Play Games project, which the player can do
      // nothing about — so the wording blames the connection, not them, and
      // does not pretend to diagnose it.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not connect to $_serviceName.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt off the notifier, not just off this widget's own setState. The
    // silent sign-in at launch resolves in the background and the Home prompt
    // can sign in too, so this tile has to be able to catch up on a state
    // change it did not cause.
    return ValueListenableBuilder<int>(
      valueListenable: GameServices.revision,
      builder: (context, revision, _) => _tile(context),
    );
  }

  Widget _tile(BuildContext context) {
    final signedIn = GameServices.isSignedIn;
    final name = GameServices.playerName;
    final busy = _pressed || GameServices.isBusy;

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          signedIn ? Icons.sports_esports : Icons.sports_esports_outlined,
          color: signedIn ? Palette.success : Palette.uiTextDim,
        ),
        title: Text(
          signedIn ? (name ?? 'Signed in') : _serviceName,
          style: const TextStyle(color: Palette.uiText, fontSize: 14),
        ),
        subtitle: Text(
          signedIn
              ? 'Connected to $_serviceName.'
              // Says what it is for rather than just what it is. A sign-in
              // with no stated purpose on a single-player game reads as the
              // app asking for something.
              : 'Optional. Connect an account to carry achievements and '
                    'leaderboards when they arrive.',
          style: const TextStyle(color: Palette.uiTextDim, fontSize: 11),
        ),
        trailing: signedIn
            ? const Icon(Icons.check, color: Palette.success, size: 18)
            : FilledButton(
                onPressed: busy ? null : _signIn,
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.accent,
                  disabledBackgroundColor: Palette.uiBackground,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(busy ? '…' : 'Sign in'),
              ),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;

  /// 0..1, shown to the player as 0..100.
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 110,
        child: Text(
          label,
          style: const TextStyle(color: Palette.uiText, fontSize: 14),
        ),
      ),
      Expanded(
        child: Slider(
          value: value,
          activeColor: Palette.accent,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
      SizedBox(
        width: 34,
        child: Text(
          '${(value * 100).round()}',
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: Palette.uiTextDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}
