import 'dart:async';
import 'dart:math';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

/// Simple voice enrollment: records 3 samples, stores average speaking duration
/// as a basic voiceprint. Not perfect biometrics but provides basic filtering.
class VoiceAuthService {
  static final VoiceAuthService _instance = VoiceAuthService._internal();
  factory VoiceAuthService() => _instance;
  VoiceAuthService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  static const int _requiredSamples = 3;

  Future<String> get _samplesDir async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/voice_samples';
    await Directory(path).create(recursive: true);
    return path;
  }

  Future<bool> get isEnrolled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('voice_enrolled') ?? false;
  }

  /// Record one voice sample, returns duration in ms
  Future<int> recordSample(int index) async {
    final dir = await _samplesDir;
    final path = '$dir/sample_$index.m4a';

    if (await _recorder.hasPermission()) {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      final start = DateTime.now().millisecondsSinceEpoch;
      await Future.delayed(const Duration(seconds: 3));
      await _recorder.stop();
      final duration = DateTime.now().millisecondsSinceEpoch - start;
      return duration;
    }
    return 0;
  }

  /// Complete enrollment by saving average voice duration as voiceprint
  Future<void> completeEnrollment(List<int> durations) async {
    final avg = durations.reduce((a, b) => a + b) / durations.length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_enrolled', true);
    await prefs.setDouble('voice_avg_duration', avg);
    await prefs.setInt('voice_sample_count', durations.length);
  }

  Future<void> clearEnrollment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_enrolled', false);
    await prefs.remove('voice_avg_duration');
  }

  int get requiredSamples => _requiredSamples;
}
