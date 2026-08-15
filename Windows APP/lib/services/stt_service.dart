// lib/services/stt_service.dart — MEKA Desktop (Windows & Linux)
// Speech-to-text stub for desktop. Command transcription is handled
// directly by WakeWordService via Gemini audio API (chatWithAudio).
// This service exists for future direct STT integration.
import 'dart:async';

class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  bool _isListening = false;
  bool get isListening => _isListening;

  Future<bool> initialize() async {
    return true;
  }

  Future<String?> transcribeOnce() async {
    // Transcription is handled by WakeWordService.chatWithAudio (Gemini API)
    return null;
  }

  void stop() {
    _isListening = false;
  }
}
