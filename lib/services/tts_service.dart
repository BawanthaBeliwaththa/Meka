import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.52);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Try to pick a natural-sounding voice
    final voices = await _tts.getVoices;
    if (voices != null) {
      final voiceList = List<Map>.from(voices);
      final preferred = voiceList.firstWhere(
        (v) => (v['name'] as String).toLowerCase().contains('female') ||
               (v['name'] as String).toLowerCase().contains('samantha') ||
               (v['name'] as String).toLowerCase().contains('karen'),
        orElse: () => voiceList.isNotEmpty ? voiceList.first : {},
      );
      if (preferred.isNotEmpty) {
        await _tts.setVoice({'name': preferred['name'], 'locale': preferred['locale']});
      }
    }
    _initialized = true;
  }

  Future<void> speak(String text) async {
    await _init();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void onComplete(VoidCallback callback) {
    _tts.setCompletionHandler(callback);
  }
}
