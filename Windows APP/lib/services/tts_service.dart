import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init(String text) async {
    // Detect if text contains Sinhala Unicode characters (range 0D80 to 0DFF)
    final bool isSinhala = RegExp(r'[\u0D80-\u0DFF]').hasMatch(text);

    if (isSinhala) {
      await _tts.setLanguage('si-LK');
    } else {
      // Use en-US as primary for natural English voices (wavenet/premium)
      await _tts.setLanguage('en-US');
    }

    await _tts.setSpeechRate(0.48); // Calmer, proper English rate
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.12); // Slightly higher pitch for natural female tone

    // Try to pick a natural-sounding female voice for the chosen locale
    final voices = await _tts.getVoices;
    if (voices != null) {
      final voiceList = List<Map>.from(voices);
      final String currentLocale = isSinhala ? 'si-lk' : 'en-us';
      
      final preferred = voiceList.firstWhere(
        (v) {
          final name = (v['name'] as String).toLowerCase();
          final locale = (v['locale'] as String).toLowerCase();
          final matchLocale = locale.contains(currentLocale) || locale.contains('en-gb') || locale.contains('en-lk');
          // Prioritize high-quality female and wavenet voices
          final matchFemale = name.contains('female') || 
                              name.contains('zari') || 
                              name.contains('samantha') || 
                              name.contains('wavenet') || 
                              name.contains('network') ||
                              name.contains('local') ||
                              name.contains('a-female') ||
                              name.contains('c-female');
          return matchLocale && matchFemale;
        },
        orElse: () => voiceList.firstWhere(
          (v) => (v['locale'] as String).toLowerCase().contains(currentLocale),
          orElse: () => voiceList.firstWhere(
            (v) => (v['name'] as String).toLowerCase().contains('female'),
            orElse: () => voiceList.isNotEmpty ? voiceList.first : {},
          ),
        ),
      );
      if (preferred.isNotEmpty) {
        await _tts.setVoice({'name': preferred['name'], 'locale': preferred['locale']});
      }
    }
    _initialized = true;
  }

  Future<void> speak(String text) async {
    await _init(text);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void onComplete(void Function() callback) {
    _tts.setCompletionHandler(callback);
  }
}
