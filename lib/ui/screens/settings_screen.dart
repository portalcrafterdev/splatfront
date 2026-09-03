import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio.dart';
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
