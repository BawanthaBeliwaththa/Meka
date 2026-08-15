// lib/services/wake_word_service.dart — MEKA Linux Desktop
// Autonomous voice engine for Linux Desktop.
// Uses record for high-fidelity audio capture + Gemini audio API for speech processing.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'tts_service.dart';
import 'llm_service.dart';
import 'device_skills_service.dart';

enum WakeWordState { idle, listening, processing, speaking, error }

class WakeWordService {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

  final AudioRecorder _commandRecorder = AudioRecorder();
  final TtsService _tts = TtsService();
  final LlmService _llm = LlmService();

  final _stateCtrl = StreamController<WakeWordState>.broadcast();
  final _transcriptCtrl = StreamController<String>.broadcast();
  final _responseCtrl = StreamController<String>.broadcast();

  Stream<WakeWordState> get stateStream => _stateCtrl.stream;
  Stream<String> get transcriptStream => _transcriptCtrl.stream;
  Stream<String> get responseStream => _responseCtrl.stream;

  WakeWordState _state = WakeWordState.idle;
  bool _active = false;

  WakeWordState get currentState => _state;

  void _setState(WakeWordState state) {
    _state = state;
    _stateCtrl.add(state);
  }

  Future<void> start() async {
    if (_active) return;
    await _llm.loadSettings();
    _active = true;
    _setState(WakeWordState.idle);
  }

  void stop() {
    _active = false;
    _commandRecorder.stop();
    _tts.stop();
    _setState(WakeWordState.idle);
  }

  Future<void> processVoiceCommand() async {
    if (!_active) return;
    _setState(WakeWordState.listening);

    final dir = await getApplicationDocumentsDirectory();
    final pcmPath = '${dir.path}/meka_desktop_cmd.raw';
    final file = File(pcmPath);
    if (await file.exists()) await file.delete();

    _transcriptCtrl.add('Listening for your command...');

    if (await _commandRecorder.hasPermission()) {
      await _commandRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: pcmPath,
      );
    }

    // Dynamic silence detection — stops recording when user finishes speaking
    int silenceTicks = 0;
    const int checkIntervalMs = 150;
    const int maxRecordTimeMs = 8000;
    const int minRecordTimeMs = 800;
    int elapsedMs = 0;

    while (elapsedMs < maxRecordTimeMs && _active) {
      await Future.delayed(const Duration(milliseconds: checkIntervalMs));
      elapsedMs += checkIntervalMs;
      try {
        final amp = await _commandRecorder.getAmplitude();
        if (amp.current < -38.0) {
          silenceTicks++;
        } else {
          silenceTicks = 0;
        }
      } catch (_) {
        silenceTicks++;
      }
      if (elapsedMs >= minRecordTimeMs && silenceTicks >= 5) break;
    }

    await _commandRecorder.stop();

    if (!await file.exists()) {
      _setState(WakeWordState.idle);
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 2000) {
      _setState(WakeWordState.idle);
      return;
    }

    _setState(WakeWordState.processing);
    _transcriptCtrl.add('Processing voice command...');

    final wavBytes = _addWavHeader(bytes, 16000);

    try {
      final rawResponse = await _llm.chatWithAudio(wavBytes);
      final result = await DeviceSkillsService.handleResponse(rawResponse);
      _responseCtrl.add(result.text);
      _transcriptCtrl.add(result.text);
      _setState(WakeWordState.speaking);
      await _tts.speak(result.text);
    } catch (_) {
      const msg = 'Neural core connection error. Please try again.';
      _responseCtrl.add(msg);
      _transcriptCtrl.add(msg);
      await _tts.speak(msg);
    }

    await Future.delayed(const Duration(milliseconds: 600));
    _setState(WakeWordState.idle);
  }

  /// WAV header builder for 16-bit PCM audio
  Uint8List _addWavHeader(Uint8List pcmBytes, int sampleRate) {
    final int fileSize = pcmBytes.length + 36;
    final int byteRate = sampleRate * 2;
    final header = ByteData(44);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6d); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);          // PCM
    header.setUint16(22, 1, Endian.little);          // Mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, pcmBytes.length, Endian.little);
    final wav = Uint8List(44 + pcmBytes.length);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, wav.length, pcmBytes);
    return wav;
  }

  /// Manually trigger microphone command (called by mic button in UI)
  Future<void> triggerManually() async {
    if (_state == WakeWordState.speaking || _state == WakeWordState.processing) return;
    await processVoiceCommand();
  }

  void dispose() {
    _stateCtrl.close();
    _transcriptCtrl.close();
    _responseCtrl.close();
  }
}
