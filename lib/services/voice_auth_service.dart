import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class VoiceAuthService {
  static final VoiceAuthService _instance = VoiceAuthService._internal();
  factory VoiceAuthService() => _instance;
  VoiceAuthService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  static const int _requiredSamples = 3;

  Future<String> get _samplesDir async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/voice_profiles';
    await Directory(path).create(recursive: true);
    return path;
  }

  Future<bool> get isEnrolled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('voice_enrolled') ?? false;
  }

  Future<double> get enrolledPitch async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('voice_pitch') ?? 0.0;
  }

  int get requiredSamples => _requiredSamples;

  /// Start recording raw PCM 16-bit mono audio at 16kHz
  Future<void> startRecording(int sampleIndex) async {
    final dir = await _samplesDir;
    final path = '$dir/sample_$sampleIndex.raw';

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }

    if (await _recorder.hasPermission()) {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    }
  }

  /// Stop recording and return the analyzed fundamental frequency (pitch)
  Future<double> stopAndAnalyze(int sampleIndex) async {
    try {
      await _recorder.stop();
      final dir = await _samplesDir;
      final path = '$dir/sample_$sampleIndex.raw';
      final file = File(path);

      if (!await file.exists()) return 0.0;

      final bytes = await file.readAsBytes();
      if (bytes.length < 1000) return 0.0;

      final pitch = _calculateFundamentalFrequency(bytes);
      return pitch;
    } catch (_) {
      return 0.0;
    }
  }

  /// Autocorrelation Pitch Detection Algorithm (YIN-simplified)
  double _calculateFundamentalFrequency(Uint8List bytes) {
    // Convert 8-bit bytes to 16-bit PCM samples
    final buffer = bytes.buffer.asByteData();
    final samples = Int16List(bytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = buffer.getInt16(i * 2, Endian.little);
    }

    const int sampleRate = 16000;
    const int minFreq = 75;  // Male voice minimum lower limit
    const int maxFreq = 300; // Female/child voice maximum upper limit

    const int minPeriod = sampleRate ~/ maxFreq; // ~53 samples
    const int maxPeriod = sampleRate ~/ minFreq; // ~213 samples

    // Find the voice window (highest energy section to avoid silence)
    int windowSize = 2000; // 125ms window
    if (samples.length < windowSize) {
      windowSize = samples.length;
    }

    // Find window starting index with highest RMS energy
    int bestStartIndex = 0;
    double maxRms = 0.0;
    for (int i = 0; i < samples.length - windowSize; i += 500) {
      double sumSq = 0;
      for (int j = 0; j < windowSize; j++) {
        final s = samples[i + j].toDouble();
        sumSq += s * s;
      }
      final rms = sqrt(sumSq / windowSize);
      if (rms > maxRms) {
        maxRms = rms;
        bestStartIndex = i;
      }
    }

    // Autocorrelation within the best window
    double maxCorrelation = -1.0;
    int bestPeriod = -1;

    for (int period = minPeriod; period <= maxPeriod; period++) {
      double sum = 0.0;
      double sumSq1 = 0.0;
      double sumSq2 = 0.0;

      for (int i = 0; i < windowSize - period; i++) {
        final double s1 = samples[bestStartIndex + i].toDouble();
        final double s2 = samples[bestStartIndex + i + period].toDouble();
        sum += s1 * s2;
        sumSq1 += s1 * s1;
        sumSq2 += s2 * s2;
      }

      if (sumSq1 > 0 && sumSq2 > 0) {
        final double correlation = sum / sqrt(sumSq1 * sumSq2);
        if (correlation > maxCorrelation) {
          maxCorrelation = correlation;
          bestPeriod = period;
        }
      }
    }

    if (bestPeriod != -1 && maxCorrelation > 0.65) {
      return sampleRate / bestPeriod;
    }

    return 0.0;
  }

  /// Complete enrollment by averaging valid sample pitches
  Future<void> completeEnrollment(List<double> pitches) async {
    final validPitches = pitches.where((p) => p > 50 && p < 350).toList();
    if (validPitches.isEmpty) return;

    final avgPitch = validPitches.reduce((a, b) => a + b) / validPitches.length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_enrolled', true);
    await prefs.setDouble('voice_pitch', avgPitch);
  }

  /// Verify if the speaking pitch matches the enrolled pitch within range
  Future<bool> verifySpeaker(double currentPitch) async {
    if (!await isEnrolled) return true; // Bypass if not enrolled

    final enrolled = await enrolledPitch;
    if (enrolled <= 0.0 || currentPitch <= 0.0) return false;

    // Tolerance range of +/- 22% matches Siri's typical biological deviation
    final minAllowed = enrolled * 0.78;
    final maxAllowed = enrolled * 1.22;

    return currentPitch >= minAllowed && currentPitch <= maxAllowed;
  }

  Future<void> clearEnrollment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_enrolled', false);
    await prefs.remove('voice_pitch');
  }
}
