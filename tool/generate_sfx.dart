import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const sampleRate = 44100;

void main() {
  final outDir = Directory('assets/audio')..createSync(recursive: true);
  final gen = SfxGenerator();

  _writeWav(File('${outDir.path}/shoot.wav'), gen.shoot());
  _writeWav(File('${outDir.path}/hit.wav'), gen.hit());
  _writeWav(File('${outDir.path}/death.wav'), gen.death());
  _writeWav(File('${outDir.path}/kick.wav'), gen.kick());
  _writeWav(File('${outDir.path}/bounce.wav'), gen.bounce());
  _writeWav(File('${outDir.path}/goal.wav'), gen.goal());
  _writeWav(File('${outDir.path}/whistle.wav'), gen.whistle());
  _writeWav(File('${outDir.path}/win.wav'), gen.win());
  _writeWav(File('${outDir.path}/tick.wav'), gen.tick());
  stdout.writeln('SFX written to ${outDir.path}');
}

class SfxGenerator {
  List<double> sineWave(
    double seconds,
    double frequency, {
    double? endFrequency,
    double amplitude = 0.5,
    double attack = 0.005,
    double release = 0.05,
  }) {
    final count = (sampleRate * seconds).floor();
    final freqEnd = endFrequency ?? frequency;
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      final t = i / sampleRate;
      final p = i / count;
      final freq = frequency + (freqEnd - frequency) * p;
      final envelop =
          min(1.0, t / max(attack, 0.0001)) * min(1.0, (seconds - t) / release);
      out.add(sin(2 * pi * freq * t) * (amplitude * envelop.clamp(0, 1)));
    }
    return out;
  }

  List<double> _add(List<double> a, List<double> b) {
    final n = max(a.length, b.length);
    final out = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      out[i] = (i < a.length ? a[i] : 0) + (i < b.length ? b[i] : 0);
    }
    return out;
  }

  List<double> noise(
    double seconds, {
    double amplitude = 0.4,
    double decay = 3,
  }) {
    final random = Random(42);
    final count = (sampleRate * seconds).floor();
    return List<double>.generate(count, (i) {
      final envelope = exp(-decay * i / count);
      return (random.nextDouble() * 2 - 1) * amplitude * envelope;
    });
  }

  List<double> shoot() {
    final zap = sineWave(0.16, 1250, endFrequency: 190, amplitude: 0.45);
    final crack = noise(0.04, amplitude: 0.12);
    return _add(zap, crack);
  }

  List<double> hit() {
    final blip = sineWave(0.09, 880, amplitude: 0.4);
    final tick = sineWave(0.04, 1600, amplitude: 0.2);
    return _add(blip, tick);
  }

  List<double> death() {
    final boom = sineWave(0.45, 130, endFrequency: 40, amplitude: 0.5);
    final static = noise(0.35, amplitude: 0.25, decay: 6);
    return _add(boom, static);
  }

  List<double> kick() {
    return sineWave(0.14, 220, endFrequency: 55, amplitude: 0.55);
  }

  List<double> bounce() {
    return sineWave(0.06, 420, endFrequency: 260, amplitude: 0.3);
  }

  List<double> goal() {
    final notes = [523.25, 659.25, 783.99, 1046.5];
    final out = <double>[];
    for (final note in notes) {
      out.addAll(sineWave(0.12, note, amplitude: 0.4, release: 0.08));
    }
    return out;
  }

  List<double> whistle() {
    final a = sineWave(0.45, 1174.66, amplitude: 0.32, release: 0.05);
    final b = sineWave(0.45, 1567.98, amplitude: 0.32, release: 0.05);
    final pause = List<double>.filled(sampleRate ~/ 25, 0);
    return [...a, ...pause, ...b];
  }

  List<double> win() {
    final notes = [523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5, 1318.5];
    final out = <double>[];
    for (final note in notes) {
      out.addAll(sineWave(0.12, note, amplitude: 0.38, release: 0.1));
    }
    return out;
  }

  List<double> tick() {
    return sineWave(0.05, 1000, amplitude: 0.3, release: 0.04);
  }
}

void _writeWav(File file, List<double> samples) {
  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    var sample = (samples[i] * 32767).round().clamp(-32767, 32767);
    pcm[i] = sample;
  }
  final bytes = Uint8List(44 + pcm.length * 2);
  final data = ByteData.view(bytes.buffer);

  void writeString(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeString(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length * 2, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  data.setUint32(40, pcm.length * 2, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    data.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  file.writeAsBytesSync(bytes);
}