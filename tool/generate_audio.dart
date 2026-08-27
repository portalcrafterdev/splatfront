// Generates every sound in `assets/audio/` from scratch.
//
// Run with: dart run tool/generate_audio.dart
//
// The game shipped with no audio assets and none to license, so the sounds
// are synthesised here rather than recorded. That has one real advantage
// besides existing: a sound is a few lines of maths in version control, so
// retuning the splat is a code review, not a binary blob swap.
//
// Everything is 16-bit mono PCM. SFX run at 44.1 kHz because they are short
// and their top end matters; music runs at 22.05 kHz because a loop is
// hundreds of kilobytes and its top end does not.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sfxRate = 44100;
const int musicRate = 22050;

void main() {
  final dir = Directory('assets/audio');
  dir.createSync(recursive: true);

  write('deploy.wav', deploy(), sfxRate);
  write('hit.wav', hit(), sfxRate);
  write('death.wav', death(), sfxRate);
  // Three splats, pitched apart. The game randomises between them and then
  // detunes by another ±10%, so a busy fight never repeats one exactly.
  write('splat_1.wav', splat(1.0), sfxRate);
  write('splat_2.wav', splat(1.18), sfxRate);
  write('splat_3.wav', splat(0.85), sfxRate);
  write('elixir_full.wav', elixirFull(), sfxRate);
  write('lead_change.wav', leadChange(), sfxRate);
  write('victory.wav', victory(), sfxRate);
  write('defeat.wav', defeat(), sfxRate);
  write('chest_open.wav', chestOpen(), sfxRate);
  write('ui_tap.wav', uiTap(), sfxRate);

  write('music_menu.wav', menuLoop(), musicRate);
  write('music_match.wav', matchLoop(percussion: false), musicRate);
  write('music_match_final.wav', matchLoop(percussion: true), musicRate);

  stdout.writeln('Done.');
}

// --- Sounds --------------------------------------------------------------

/// A card landing: a soft thud with a short upward chirp over it.
Float64List deploy() {
  final out = buffer(0.30, sfxRate);
  layer(out, sfxRate, (t) {
    final thud = math.sin(2 * math.pi * (150 - 60 * t) * t) * decay(t, 12);
    final chirp = math.sin(2 * math.pi * (420 + 520 * t) * t) * decay(t, 22);
    return thud * 0.55 + chirp * 0.25;
  });
  return out;
}

/// A blow landing: a filtered noise crack with a low body under it.
Float64List hit() {
  final rng = math.Random(11);
  final out = buffer(0.14, sfxRate);
  layer(out, sfxRate, (t) {
    final crack = (rng.nextDouble() * 2 - 1) * decay(t, 45);
    final body = math.sin(2 * math.pi * 190 * t) * decay(t, 30);
    return crack * 0.42 + body * 0.35;
  });
  return lowpass(out, 0.42);
}

/// A unit going down: a pitch drop, deflating.
Float64List death() {
  final rng = math.Random(23);
  final out = buffer(0.55, sfxRate);
  layer(out, sfxRate, (t) {
    final fall = math.sin(2 * math.pi * (330 * math.exp(-2.6 * t)) * t);
    final air = (rng.nextDouble() * 2 - 1) * decay(t, 6) * 0.2;
    return (fall * 0.5 + air) * decay(t, 4.5);
  });
  return lowpass(out, 0.5);
}

/// Paint hitting the ground: a wet noise burst, no tone to speak of.
Float64List splat(double pitch) {
  final rng = math.Random((pitch * 1000).round());
  final out = buffer(0.22, sfxRate);
  layer(out, sfxRate, (t) {
    final wet = (rng.nextDouble() * 2 - 1) * decay(t, 26);
    final plop = math.sin(2 * math.pi * (240 * pitch) * math.exp(-7 * t) * t);
    return wet * 0.5 + plop * 0.22 * decay(t, 16);
  });
  // A heavier filter is what turns a dry click into something wet.
  return lowpass(out, 0.3 / pitch);
}

/// The bar topping out: a clean two-note lift.
Float64List elixirFull() => sequence(sfxRate, const [
  Note(784.0, 0.0, 0.13, 0.30), // G5
  Note(1046.5, 0.09, 0.22, 0.26), // C6
]);

/// The lead swapping hands: three notes going up, deliberately bright.
Float64List leadChange() => sequence(sfxRate, const [
  Note(587.3, 0.0, 0.10, 0.24), // D5
  Note(739.99, 0.07, 0.10, 0.24), // F#5
  Note(880.0, 0.14, 0.24, 0.26), // A5
]);

Float64List victory() => sequence(sfxRate, const [
  Note(523.25, 0.00, 0.16, 0.26), // C5
  Note(659.25, 0.13, 0.16, 0.26), // E5
  Note(783.99, 0.26, 0.16, 0.26), // G5
  Note(1046.5, 0.39, 0.55, 0.30), // C6
]);

Float64List defeat() => sequence(sfxRate, const [
  Note(392.0, 0.00, 0.22, 0.24), // G4
  Note(329.63, 0.18, 0.22, 0.24), // E4
  Note(261.63, 0.36, 0.70, 0.26), // C4
]);

/// A chest opening: a rising shimmer with a little sparkle on top.
Float64List chestOpen() {
  final out = buffer(0.9, sfxRate);
  layer(out, sfxRate, (t) {
    final sweep = math.sin(2 * math.pi * (300 + 900 * t) * t) * decay(t, 3.0);
    final sparkle =
        math.sin(2 * math.pi * 2100 * t) * decay(t, 9) * (t > 0.25 ? 1 : 0);
    return sweep * 0.22 + sparkle * 0.14;
  });
  return out;
}

/// A menu press. Short enough not to get tiring.
Float64List uiTap() {
  final out = buffer(0.07, sfxRate);
  layer(out, sfxRate, (t) {
    return math.sin(2 * math.pi * 1250 * t) * decay(t, 60) * 0.28;
  });
  return out;
}

// --- Music ---------------------------------------------------------------

/// Chord roots for the loop, one bar each. Am - F - C - G, which is calm and
/// goes round forever without asking for a resolution.
const List<double> _roots = [220.00, 174.61, 261.63, 196.00];

/// Which scale degrees the arpeggio walks, as semitone offsets from the root.
const List<int> _arp = [0, 7, 12, 16, 12, 7];

/// The menu: a slow pad with a soft arpeggio over it. No drums.
Float64List menuLoop() {
  const bar = 2.4; // seconds
  final total = bar * _roots.length;
  final out = buffer(total, musicRate);

  for (var b = 0; b < _roots.length; b++) {
    final root = _roots[b];
    final start = b * bar;

    // Pad: root, fifth and octave, all detuned a hair so it breathes.
    for (final ratio in const [1.0, 1.5, 2.0]) {
      addTone(
        out,
        musicRate,
        start: start,
        length: bar * 1.05,
        frequency: root * ratio,
        gain: 0.075,
        attack: 0.5,
        release: 0.8,
        detune: 0.4,
      );
    }

    // Arpeggio, one note per eighth of a bar.
    for (var i = 0; i < _arp.length; i++) {
      addTone(
        out,
        musicRate,
        start: start + i * (bar / _arp.length),
        length: bar / _arp.length * 1.4,
        frequency: root * 2 * semitone(_arp[i]),
        gain: 0.045,
        attack: 0.02,
        release: 0.25,
      );
    }
  }
  return lowpass(out, 0.55);
}

/// The match: the same harmony taken faster, with a bass pulse. The final
/// twenty seconds swap to the [percussion] version, which adds the kick and
/// hat layer section 12 asks for.
Float64List matchLoop({required bool percussion}) {
  const bar = 1.8;
  final total = bar * _roots.length;
  final out = buffer(total, musicRate);
  final rng = math.Random(7);

  for (var b = 0; b < _roots.length; b++) {
    final root = _roots[b];
    final start = b * bar;

    for (final ratio in const [1.0, 1.5]) {
      addTone(
        out,
        musicRate,
        start: start,
        length: bar * 1.02,
        frequency: root * ratio,
        gain: 0.07,
        attack: 0.25,
        release: 0.5,
        detune: 0.5,
      );
    }

    // Bass on every quarter, driving it along.
    for (var q = 0; q < 4; q++) {
      addTone(
        out,
        musicRate,
        start: start + q * bar / 4,
        length: bar / 4 * 0.8,
        frequency: root / 2,
        gain: 0.10,
        attack: 0.005,
        release: 0.12,
      );
    }

    for (var i = 0; i < _arp.length; i++) {
      addTone(
        out,
        musicRate,
        start: start + i * (bar / _arp.length),
        length: bar / _arp.length * 1.2,
        frequency: root * 2 * semitone(_arp[i]),
        gain: 0.05,
        attack: 0.01,
        release: 0.18,
      );
    }

    if (!percussion) continue;

    for (var q = 0; q < 4; q++) {
      addKick(out, musicRate, start + q * bar / 4);
      addHat(out, musicRate, start + q * bar / 4 + bar / 8, rng);
    }
  }
  return lowpass(out, 0.7);
}

// --- Synthesis helpers ---------------------------------------------------

/// One plucked note in a [sequence].
class Note {
  const Note(this.frequency, this.start, this.length, this.gain);
  final double frequency;
  final double start;
  final double length;
  final double gain;
}

Float64List buffer(double seconds, int rate) =>
    Float64List((seconds * rate).ceil());

/// Exponential decay, [rate] per second. The workhorse envelope.
double decay(double t, double rate) => math.exp(-rate * t);

double semitone(int steps) => math.pow(2, steps / 12).toDouble();

/// Fills [out] from a function of time in seconds.
void layer(Float64List out, int rate, double Function(double t) sample) {
  for (var i = 0; i < out.length; i++) {
    out[i] += sample(i / rate);
  }
}

/// A run of plucked notes, sized to fit them all.
Float64List sequence(int rate, List<Note> notes) {
  var end = 0.0;
  for (final n in notes) {
    end = math.max(end, n.start + n.length);
  }
  final out = buffer(end + 0.05, rate);
  for (final n in notes) {
    addTone(
      out,
      rate,
      start: n.start,
      length: n.length,
      frequency: n.frequency,
      gain: n.gain,
      attack: 0.005,
      release: n.length * 0.9,
    );
  }
  return out;
}

/// One voice: a sine with a soft second harmonic, shaped by an attack and an
/// exponential release. [detune] in cents widens a pad against its neighbours.
void addTone(
  Float64List out,
  int rate, {
  required double start,
  required double length,
  required double frequency,
  required double gain,
  double attack = 0.01,
  double release = 0.2,
  double detune = 0,
}) {
  final from = (start * rate).round();
  final count = (length * rate).round();
  final freq = frequency * math.pow(2, detune / 1200);

  for (var i = 0; i < count; i++) {
    final index = from + i;
    if (index < 0 || index >= out.length) continue;
    final t = i / rate;

    final rise = attack <= 0 ? 1.0 : math.min(1.0, t / attack);
    final fall = math.exp(-t / math.max(release, 1e-4));
    final env = rise * fall;

    final phase = 2 * math.pi * freq * t;
    out[index] += (math.sin(phase) + 0.3 * math.sin(2 * phase)) * gain * env;
  }
}

/// A kick: a sine whose pitch collapses, which is all a kick really is.
void addKick(Float64List out, int rate, double start) {
  final from = (start * rate).round();
  final count = (0.16 * rate).round();
  for (var i = 0; i < count; i++) {
    final index = from + i;
    if (index < 0 || index >= out.length) continue;
    final t = i / rate;
    final freq = 120 * math.exp(-24 * t) + 45;
    out[index] += math.sin(2 * math.pi * freq * t) * decay(t, 22) * 0.30;
  }
}

void addHat(Float64List out, int rate, double start, math.Random rng) {
  final from = (start * rate).round();
  final count = (0.05 * rate).round();
  for (var i = 0; i < count; i++) {
    final index = from + i;
    if (index < 0 || index >= out.length) continue;
    final t = i / rate;
    out[index] += (rng.nextDouble() * 2 - 1) * decay(t, 90) * 0.07;
  }
}

/// One-pole low pass. [amount] is 0 (silent) to 1 (untouched).
Float64List lowpass(Float64List input, double amount) {
  final a = amount.clamp(0.01, 1.0);
  final out = Float64List(input.length);
  var last = 0.0;
  for (var i = 0; i < input.length; i++) {
    last += (input[i] - last) * a;
    out[i] = last;
  }
  return out;
}

// --- WAV output ----------------------------------------------------------

/// Normalises to a consistent headroom and writes 16-bit mono PCM.
///
/// Normalising matters more than it sounds: without it the volume sliders
/// would be fighting fifteen different recording levels.
void write(String name, Float64List samples, int rate) {
  var peak = 0.0;
  for (final s in samples) {
    peak = math.max(peak, s.abs());
  }
  final scale = peak > 0 ? 0.89 / peak : 0.0;

  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = (samples[i] * scale * 32767).round().clamp(-32768, 32767);
  }

  final body = pcm.buffer.asUint8List();
  final header = ByteData(44)
    ..setUint32(4, 36 + body.length, Endian.little)
    ..setUint32(16, 16, Endian.little) // fmt chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little) // byte rate
    ..setUint16(32, 2, Endian.little) // block align
    ..setUint16(34, 16, Endian.little) // bits per sample
    ..setUint32(40, body.length, Endian.little);

  final bytes = header.buffer.asUint8List();
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  bytes.setRange(36, 40, 'data'.codeUnits);

  File('assets/audio/$name').writeAsBytesSync([...bytes, ...body]);
  stdout.writeln(
    '$name  ${(samples.length / rate).toStringAsFixed(2)}s  '
    '${((bytes.length + body.length) / 1024).round()} KB',
  );
}
