import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

AudioPlayer? _mobilePlayer;
File? _beepWavFile;

Future<void> _initAndPlayMobileBeep() async {
  try {
    if (_mobilePlayer == null) {
      _mobilePlayer = AudioPlayer();
    }

    if (_beepWavFile == null) {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/scanner_beep.wav');
      if (!await file.exists()) {
        final wavBytes = _generateBeepWav();
        await file.writeAsBytes(wavBytes);
      }
      _beepWavFile = file;
    }

    if (_beepWavFile != null) {
      await _mobilePlayer!.stop();
      await _mobilePlayer!.play(DeviceFileSource(_beepWavFile!.path));
    }
  } catch (e) {
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }
}

void playPlatformScannerBeep() {
  try {
    HapticFeedback.lightImpact();
    _initAndPlayMobileBeep();
  } catch (e) {
    // Safe fallback
  }
}

List<int> _generateBeepWav() {
  final sampleRate = 11025;
  final duration = 0.15; // 150ms
  final frequency = 1380.0; // Classic terminal beep sound frequency
  final numSamples = (sampleRate * duration).toInt();

  final subChunk1Size = 16;
  final audioFormat = 1;
  final numChannels = 1;
  final bitsPerSample = 8;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final subChunk2Size = numSamples * blockAlign;
  final chunkSize = 36 + subChunk2Size;

  final bytes = <int>[];

  // RIFF header
  bytes.addAll('RIFF'.codeUnits);
  bytes.addAll(_fourBytes(chunkSize));
  bytes.addAll('WAVE'.codeUnits);

  // fmt subchunk
  bytes.addAll('fmt '.codeUnits);
  bytes.addAll(_fourBytes(subChunk1Size));
  bytes.addAll(_twoBytes(audioFormat));
  bytes.addAll(_twoBytes(numChannels));
  bytes.addAll(_fourBytes(sampleRate));
  bytes.addAll(_fourBytes(byteRate));
  bytes.addAll(_twoBytes(blockAlign));
  bytes.addAll(_twoBytes(bitsPerSample));

  // data subchunk
  bytes.addAll('data'.codeUnits);
  bytes.addAll(_fourBytes(subChunk2Size));

  // Sine values (Centered around 128 for 8-bit unsigned PCM)
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final value = (127 * sin(2 * pi * frequency * t) + 128).round();
    bytes.add(value.clamp(0, 255));
  }

  return bytes;
}

List<int> _fourBytes(int val) {
  return [
    val & 0xFF,
    (val >> 8) & 0xFF,
    (val >> 16) & 0xFF,
    (val >> 24) & 0xFF,
  ];
}

List<int> _twoBytes(int val) {
  return [
    val & 0xFF,
    (val >> 8) & 0xFF,
  ];
}
