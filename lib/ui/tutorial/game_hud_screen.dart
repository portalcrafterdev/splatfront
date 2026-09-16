import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../type.dart';
import '../widgets/motion.dart';
import 'coach_mark.dart';
import 'hand_gesture_indicator.dart';
import 'tutorial_flags.dart';

/// A worked example of the coach-mark system on a live HUD.
///
/// Run it on its own with `flutter run -t lib/tutorial_demo_main.dart`. It is
/// not reachable from the app's own entry point, so nothing here ships in the
/// release binary — Dart only compiles what the entry point can reach.
///
/// Everything that makes it a tutorial is in three lines of this file:
/// a [GlobalKey] on each target, [TutorialController.startIfUnseen] after the
/// first frame, and a [TutorialController.report] at the end of each action's
/// own handler. The buttons themselves know nothing about it.
class GameHudScreen extends StatefulWidget {
  const GameHudScreen({super.key});

  /// The flag key for the combat sequence, exposed so a settings screen can
  /// offer to replay it without reaching into the widget's state.
  static const String combatTutorial = 'combat_basics';

  /// The flag key for the one-step movement tip.
  static const String movementTutorial = 'movement_tip';

  @override
  State<GameHudScreen> createState() => _GameHudScreenState();
}

class _GameHudScreenState extends State<GameHudScreen> {
  // The three things the tutorial points at. A key has to sit on a widget
  // that is actually laid out — see CoachMarkStep.target.
  final _attackKey = GlobalKey(debugLabel: 'attack');
  final _potionKey = GlobalKey(debugLabel: 'potion');
  final _moveKey = GlobalKey(debugLabel: 'move');

  final _combat = TutorialController(id: GameHudScreen.combatTutorial);
  final _movement = TutorialController(id: GameHudScreen.movementTutorial);

  static const int _heroMaxHp = 100;
  static const int _enemyMaxHp = 120;

  int _heroHp = 68;
  int _enemyHp = _enemyMaxHp;
  int _potions = 3;

  /// Where the hero token sits in the movement pad, 0 to 1 on each axis.
  Offset _position = const Offset(0.5, 0.5);

  String _log = 'A slime blocks the path.';

  @override
  void initState() {
    super.initState();
    // After the first frame: the targets have to have been laid out before
    // there is anything to cut a hole around.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerTutorial());
  }

  @override
  void dispose() {
    _combat.dispose();
    _movement.dispose();
    super.dispose();
  }

  Future<void> _offerTutorial() async {
    if (!mounted) return;
    await _combat.startIfUnseen(
      context,
      steps: _combatSteps,
      onFinished: () {
        if (!mounted) return;
        setState(() => _log = 'Tutorial complete. The slime looks nervous.');
      },
    );
  }

  List<CoachMarkStep> get _combatSteps => [
    CoachMarkStep(
      id: 'attack',
      target: _attackKey,
      title: 'Swing at it',
      message: 'Tap Attack to hit whatever is in front of you.',
      shape: CoachMarkShape.round,
    ),
    CoachMarkStep(
      id: 'potion',
      target: _potionKey,
      title: 'Patch yourself up',
      message: 'Low on health? Tap Potion. You start with three.',
      shape: CoachMarkShape.round,
    ),
  ];

  List<CoachMarkStep> get _movementSteps => [
    CoachMarkStep(
      id: 'move',
      target: _moveKey,
      title: 'Get around',
      message: 'Drag anywhere on the pad to walk. Let go to stop.',
      gesture: HandGesture.swipe,
      travel: const Offset(150, 0),
    ),
  ];

  // --- Actions --------------------------------------------------------------
  //
  // Each one does its own job and then tells the tutorial what happened. The
  // report is unconditional: if no sequence is running, or the current step
  // is a different one, it does nothing.

  void _attack() {
    setState(() {
      _enemyHp = math.max(0, _enemyHp - 22);
      _heroHp = math.max(0, _heroHp - 9);
      _log = _enemyHp == 0
          ? 'The slime bursts. Nothing left but a puddle.'
          : 'You swing for 22. It hits back for 9.';
    });
    _combat.report('attack');
  }

  void _drinkPotion() {
    setState(() {
      if (_potions == 0) {
        _log = 'No potions left. Should have rationed those.';
      } else {
        _potions--;
        _heroHp = math.min(_heroMaxHp, _heroHp + 30);
        _log = 'You drink a potion. Back up 30 health.';
      }
    });
    // Reported even when the flask is empty: during the tutorial there are
    // always three, and a step that could not be finished because of an
    // unrelated resource check would trap the player behind the scrim.
    _combat.report('potion');
  }

  void _moveTo(Offset fraction) {
    setState(() {
      _position = Offset(
        fraction.dx.clamp(0.0, 1.0),
        fraction.dy.clamp(0.0, 1.0),
      );
    });
    _movement.report('move');
  }

  Future<void> _replay(TutorialController controller, List<CoachMarkStep> steps) async {
    // Clear the flag as well as starting it. A player who backs out of a
    // replay should still be offered it on the next launch.
    await TutorialFlags.reset(controller.id);
    if (!mounted) return;
    controller.start(context, steps: steps);
  }

  // --- Layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Palette.hudSkyHigh, Palette.hudSkyLow],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(),
                const SizedBox(height: 12),
                _healthRow(),
                const SizedBox(height: 12),
                Expanded(child: _movementPad()),
                const SizedBox(height: 12),
                _logLine(),
                const SizedBox(height: 12),
                _actionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Slime Hollow',
            style: Fonts.shout(size: 24, colour: Palette.hudText),
          ),
        ),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          radius: 14,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.menu_rounded, color: Palette.uiText),
            tooltip: 'Menu',
            onSelected: (choice) => switch (choice) {
              'combat' => _replay(_combat, _combatSteps),
              'movement' => _replay(_movement, _movementSteps),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'combat', child: Text('Replay tutorial')),
              PopupMenuItem(value: 'movement', child: Text('Replay movement tip')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _healthRow() {
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          _bar('You', _heroHp, _heroMaxHp, Palette.success),
          const SizedBox(height: 10),
          _bar('Slime', _enemyHp, _enemyMaxHp, Palette.danger),
        ],
      ),
    );
  }

  Widget _bar(String who, int hp, int max, Color colour) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            who,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Palette.uiTextDim,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 14,
              color: Palette.uiBackground,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                // Without heightFactor a ColoredBox with no child is
                // zero-sized and the fill never appears.
                heightFactor: 1,
                widthFactor: max == 0 ? 0 : hp / max,
                child: ColoredBox(color: colour),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            '$hp/$max',
            textAlign: TextAlign.right,
            style: Fonts.shout(size: 14, colour: Palette.uiText),
          ),
        ),
      ],
    );
  }

  Widget _movementPad() {
    return Panel(
      key: _moveKey,
      padding: EdgeInsets.zero,
      radius: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            void handle(Offset local) => _moveTo(
              Offset(local.dx / size.width, local.dy / size.height),
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => handle(d.localPosition),
              onPanUpdate: (d) => handle(d.localPosition),
              onTapDown: (d) => handle(d.localPosition),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: const _PadPainter()),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Drag to move',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Palette.uiTextDim.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _position.dx * size.width - 17,
                    top: _position.dy * size.height - 17,
                    child: const _HeroToken(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _logLine() {
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      radius: 12,
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline_rounded,
              size: 16, color: Palette.uiTextDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _log,
              style: const TextStyle(fontSize: 13.5, color: Palette.uiText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            key: _attackKey,
            label: 'Attack',
            icon: Icons.bolt_rounded,
            colour: Palette.accent,
            onTap: _attack,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _ActionButton(
            key: _potionKey,
            label: 'Potion',
            icon: Icons.local_drink_rounded,
            colour: Palette.info,
            badge: '$_potions',
            onTap: _drinkPotion,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.colour,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Panel(
        accent: colour,
        radius: 999,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: Fonts.shout(size: 17, colour: Colors.white),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: Fonts.shout(size: 13, colour: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroToken extends StatelessWidget {
  const _HeroToken();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Palette.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Palette.outline, width: Panel.stroke),
      ),
      child: const Icon(Icons.person_rounded, size: 18, color: Colors.white),
    );
  }
}

/// A faint grid on the movement pad, so dragging visibly moves the token
/// against something. Painted once — `shouldRepaint` is false, because a pad
/// that redrew every frame would be an animation that never ends.
class _PadPainter extends CustomPainter {
  const _PadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Palette.uiBackground,
    );
    final line = Paint()
      ..color = Palette.uiTextDim.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    const step = 32.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => false;
}
