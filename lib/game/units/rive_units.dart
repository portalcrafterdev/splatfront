/// The Rive half of unit animation.
///
/// The spec puts unit animation on Rive state machines and will not call a
/// unit done without idle/walk/attack/die. The hand-drawn vector characters
/// in `unit_art.dart` are what stands in until the `.riv` files exist, and
/// this file is the seam between the two: it loads whatever art has actually
/// landed in `assets/rive/`, and every card it finds no file for keeps its
/// vector character. Nothing here has to be edited when art arrives —
/// dropping `roller.riv` into `assets/rive/` is the whole job.
///
/// `docs/rive-art-contract.md` is what an artist needs: file name, artboard
/// name, state machine, inputs, and how big to draw the character.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

import '../../core/palette.dart';
import 'unit_art.dart';

/// Where unit art is looked for. A file in here named `<card id>.riv` is
/// picked up on the next launch.
const String riveAssetDir = 'assets/rive/';

/// The card ids [assets] carries Rive art for.
///
/// Pulled out of [RiveUnitLibrary.load] so the naming rule can be tested
/// without a native runtime: the test suite runs headless and rive_native is
/// FFI, so nothing below this function is reachable from `flutter test`.
/// Only files sitting directly in [riveAssetDir] count — a `.riv` in a
/// subfolder is an artist's working file, not a unit.
@visibleForTesting
List<String> riveCardIds(Iterable<String> assets) {
  final ids = assets
      .where((key) => key.startsWith(riveAssetDir) && key.endsWith('.riv'))
      .map((key) => key.substring(riveAssetDir.length, key.length - 4))
      .where((id) => id.isNotEmpty && !id.contains('/'))
      .toList();
  ids.sort();
  return ids;
}

/// Every `.riv` the build shipped, decoded once and instanced per unit.
///
/// A Rive artboard carries its own animation state, so forty units on the
/// field need forty artboards — but they all come out of one decoded file
/// per card, which is the expensive half. [create] is the per-unit call and
/// is cheap; whatever it hands back has to be disposed.
abstract final class RiveUnitLibrary {
  static final Map<String, rive.File> _files = <String, rive.File>{};
  static bool _loaded = false;
  static Object? _failure;

  /// True once [load] has run, whether or not it found anything.
  static bool get isLoaded => _loaded;

  /// Why the runtime is unavailable, or null if it is fine.
  ///
  /// A device that cannot start rive_native is not a broken device: it plays
  /// the whole game on vector characters. This is here so the unit sandbox
  /// can say which of the two it is looking at.
  static Object? get failure => _failure;

  /// The cards that have Rive art, sorted.
  static List<String> get cardIds => _files.keys.toList()..sort();

  static bool has(String cardId) => _files.containsKey(cardId);

  /// Decodes every `.riv` in [riveAssetDir].
  ///
  /// Never throws and never blocks the app: a missing native library, a
  /// corrupt file or an empty folder all end the same way, with the game on
  /// vector art. Called once from `main`.
  static Future<void> load({AssetBundle? bundle}) async {
    if (_loaded) return;
    _loaded = true;
    final source = bundle ?? rootBundle;

    List<String> ids;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(source);
      ids = riveCardIds(manifest.listAssets());
    } catch (error) {
      _failure = error;
      return;
    }
    if (ids.isEmpty) return;

    for (final id in ids) {
      try {
        // Factory.flutter, not Factory.rive: these artboards are drawn onto
        // the same ui.Canvas Flame hands every other component, so they have
        // to be built for the Flutter renderer. A file decoded for the Rive
        // renderer draws nothing here and reports no error for it.
        final file = await rive.File.asset(
          '$riveAssetDir$id.riv',
          riveFactory: rive.Factory.flutter,
          bundle: source,
        );
        if (file != null) _files[id] = file;
      } catch (error) {
        // One bad file costs one card its animation, not the launch.
        _failure ??= error;
      }
    }
  }

  /// A fresh artboard for [cardId], or null if it has no Rive art.
  ///
  /// The caller owns it and must [RiveUnitAnimation.dispose] it — these hold
  /// native memory that Dart's collector does not account for.
  static RiveUnitAnimation? create(String cardId) {
    final file = _files[cardId];
    if (file == null) return null;
    try {
      return RiveUnitAnimation._forFile(file, cardId);
    } catch (_) {
      return null;
    }
  }

  /// Drops every decoded file. Tests only; the app holds them for its life.
  @visibleForTesting
  static void reset() {
    for (final file in _files.values) {
      file.dispose();
    }
    _files.clear();
    _loaded = false;
    _failure = null;
    _renderer?.dispose();
    _renderer = null;
    _rendererCanvas = null;
  }

  static rive.Renderer? _renderer;
  static ui.Canvas? _rendererCanvas;

  /// A [rive.Renderer] wrapping [canvas], reused frame to frame.
  ///
  /// A renderer holds a native pointer with a finalizer attached, so building
  /// one per unit per frame is forty native allocations a frame for a value
  /// that does not change: Flame hands every component in a pass the same
  /// canvas. Identity is the cache key, so the frame the canvas changes is
  /// the only frame it is rebuilt.
  static rive.Renderer rendererFor(ui.Canvas canvas) {
    final cached = _renderer;
    if (cached != null && identical(_rendererCanvas, canvas)) return cached;
    cached?.dispose();
    final made = rive.Renderer.make(canvas);
    _renderer = made;
    _rendererCanvas = canvas;
    return made;
  }
}

/// One unit's artboard, wired to the state machine inputs the game drives.
///
/// Deliberately forgiving about names. The contract doc asks for `walking`,
/// `attack` and `die`, but art arrives from whoever drew it, so each role
/// accepts a short list of the names it turns up under, and an input that is
/// missing costs that one signal rather than the whole character.
class RiveUnitAnimation {
  RiveUnitAnimation._(this._artboard, this._machine)
    : _walking = _boolIn(_machine, const ['walking', 'walk', 'moving', 'run']),
      _dyingFlag = _boolIn(_machine, const ['dying', 'dead']),
      _attack = _triggerIn(_machine, const [
        'attack',
        'swing',
        'fire',
        'shoot',
      ]),
      _death = _triggerIn(_machine, const ['die', 'death', 'killed']),
      _flash = _numberIn(_machine, const ['flash', 'hurt', 'damage']),
      _facingX = _numberIn(_machine, const ['facingX', 'faceX', 'directionX']),
      _facingY = _numberIn(_machine, const ['facingY', 'faceY', 'directionY']),
      _team = _numberIn(_machine, const ['team', 'colour', 'color', 'side']) {
    final bounds = _artboard.bounds;
    final height = bounds[3] - bounds[1];
    // Fits the artboard's own frame to the height the vector characters are
    // drawn at, so a card that switches to Rive does not change size. Guarded
    // because a zero-height artboard would scale everything to infinity.
    _scale = height > 0 ? artboardHeight / height : 1.0;
  }

  factory RiveUnitAnimation._forFile(rive.File file, String cardId) {
    // Looked up by card id first — one file per unit is the contract, but an
    // artist working in one big file gets found too.
    final artboard = file.artboard(cardId) ?? file.defaultArtboard();
    if (artboard == null) {
      throw StateError('$cardId.riv has no artboard to draw');
    }
    final machine =
        artboard.defaultStateMachine() ?? artboard.stateMachineAt(0);
    return RiveUnitAnimation._(artboard, machine);
  }

  /// How tall a character stands, in art units — the space [UnitArt] draws
  /// in, where 1.0 is the unit's collision radius.
  ///
  /// The vector characters put their feet on y = 1.0 and their crown near
  /// y = -1.6. Rive art is fitted to the same 2.6, plus a little air, so the
  /// two sets are interchangeable at a glance.
  static const double artboardHeight = 2.8;

  /// Where the feet sit. Shared with the vector convention.
  static const double feetY = 1.0;

  final rive.Artboard _artboard;
  final rive.StateMachine? _machine;

  final rive.BooleanInput? _walking;
  final rive.BooleanInput? _dyingFlag;
  final rive.TriggerInput? _attack;
  final rive.TriggerInput? _death;
  final rive.NumberInput? _flash;
  final rive.NumberInput? _facingX;
  final rive.NumberInput? _facingY;
  final rive.NumberInput? _team;

  late final double _scale;
  bool _disposed = false;

  /// True when the file actually carries a state machine to drive. Without
  /// one the artboard still draws, frozen at its rest pose.
  bool get isDriven => _machine != null;

  /// Pushes this frame's [pose] at the state machine.
  ///
  /// Setting an input to the value it already holds is free on the runtime
  /// side, so this does not bother tracking what changed.
  void apply(UnitPose pose) {
    if (_disposed) return;
    _walking?.value = pose.moving;
    _flash?.value = pose.flash;
    _facingX?.value = pose.facingX;
    _facingY?.value = pose.facingY;
    // Red is 0 and blue is 1, matching the enum, so art can switch a colour
    // group without knowing what the two teams are called.
    _team?.value = pose.team == Team.red ? 0 : 1;
  }

  /// Fired the instant a swing lands, not when its damage is dealt.
  void attack() {
    if (!_disposed) _attack?.fire();
  }

  /// Fired once, when the unit starts dying.
  ///
  /// A unit is removed `Timings.deathFadeOut` after this, so a die state that
  /// runs longer than that is cut off part way. The contract doc says so.
  void die() {
    if (_disposed) return;
    _dyingFlag?.value = true;
    _death?.fire();
  }

  /// Advances animation by [dt]. Safe to call while dying.
  void advance(double dt) {
    if (_disposed) return;
    final machine = _machine;
    if (machine != null) {
      machine.advanceAndApply(dt);
    } else {
      _artboard.advance(dt);
    }
  }

  /// Draws into art space: origin at the unit's centre, 1.0 == its radius.
  ///
  /// [alpha] fades the whole character out as it dies. That is a backstop
  /// rather than the intended exit — art with a proper die state fades
  /// itself and this stays at 1.
  void draw(ui.Canvas canvas, {double alpha = 1}) {
    if (_disposed) return;
    final renderer = RiveUnitLibrary.rendererFor(canvas);
    canvas.save();
    // The artboard is instanced with frameOrigin on, so its own origin is the
    // centre of its frame. Dropping that centre half a character above the
    // feet line puts it on the ground the vector art stands on.
    canvas.translate(0, feetY - artboardHeight / 2);
    canvas.scale(_scale);
    renderer.save();
    if (alpha < 1) renderer.modulateOpacity(alpha);
    _artboard.draw(renderer);
    renderer.restore();
    canvas.restore();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _machine?.dispose();
    _artboard.dispose();
  }

  // --- Input lookup ------------------------------------------------------
  // The typed input API is deprecated in favour of data binding, which asks
  // the artboard to declare a view model. Inputs are the older and far more
  // common contract, and they are what a state machine built to the spec's
  // "idle / walk / attack / die" shape exposes, so they are what this drives.

  static rive.BooleanInput? _boolIn(rive.StateMachine? m, List<String> names) {
    if (m == null) return null;
    for (final name in names) {
      // ignore: deprecated_member_use
      final input = m.boolean(name);
      if (input != null) return input;
    }
    return null;
  }

  static rive.NumberInput? _numberIn(rive.StateMachine? m, List<String> names) {
    if (m == null) return null;
    for (final name in names) {
      // ignore: deprecated_member_use
      final input = m.number(name);
      if (input != null) return input;
    }
    return null;
  }

  static rive.TriggerInput? _triggerIn(
    rive.StateMachine? m,
    List<String> names,
  ) {
    if (m == null) return null;
    for (final name in names) {
      // ignore: deprecated_member_use
      final input = m.trigger(name);
      if (input != null) return input;
    }
    return null;
  }
}
