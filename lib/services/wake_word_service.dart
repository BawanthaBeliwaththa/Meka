import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'stt_service.dart';
import 'tts_service.dart';
import 'llm_service.dart';
import 'device_skills_service.dart';

enum WakeWordState {
  idle,
  listening,
  processing,
  speaking,
  error,
}

class WakeWordService {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

  final SttService _stt = SttService();
  final TtsService _tts = TtsService();
  final LlmService _llm = LlmService();

  final _stateController = StreamController<WakeWordState>.broadcast();
  final _transcriptController = StreamController<String>.broadcast();
  final _responseController = StreamController<String>.broadcast();

  Stream<WakeWordState> get stateStream => _stateController.stream;
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get responseStream => _responseController.stream;

  WakeWordState _state = WakeWordState.idle;
  bool _active = false;
  Timer? _wakeWordTimer;

  static const List<String> _wakeWords = [
    'hey meka',
    'hi meka',
    'ok meka',
    'okay meka',
    'meka',
  ];

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.speech,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> start() async {
    if (_active) return;
    final granted = await requestPermissions();
    if (!granted) {
      _setState(WakeWordState.error);
      return;
    }
    await _llm.loadSettings();
    _active = true;
    _setState(WakeWordState.idle);
    _startPassiveListening();
  }

  void stop() {
    _active = false;
    _wakeWordTimer?.cancel();
    _stt.stop();
    _tts.stop();
    _setState(WakeWordState.idle);
  }

  void _startPassiveListening() {
    if (!_active) return;
    _listenForWakeWord();
  }

  Future<void> _listenForWakeWord() async {
    if (!_active || _state == WakeWordState.speaking) return;

    try {
      final initialized = await _stt.initialize();
      if (!initialized) return;

      bool wakeWordDetected = false;
      final completer = Completer<void>();

      await (stt.SpeechToText()).listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase();
          _transcriptController.add(words);
          if (_wakeWords.any((w) => words.contains(w))) {
            wakeWordDetected = true;
            if (!completer.isCompleted) completer.complete();
          }
        },
        listenFor: const Duration(seconds: 5),
        pauseFor: const Duration(seconds: 2),
        localeId: 'en_US',
      );

      // Wait for wake word or timeout
      await Future.any([
        completer.future,
        Future.delayed(const Duration(seconds: 6)),
      ]);

      if (wakeWordDetected && _active) {
        await _handleWakeWordDetected();
      } else if (_active) {
        // Immediately restart passive listening
        _listenForWakeWord();
      }
    } catch (_) {
      if (_active) {
        await Future.delayed(const Duration(seconds: 2));
        _listenForWakeWord();
      }
    }
  }

  Future<void> _handleWakeWordDetected() async {
    _setState(WakeWordState.listening);

    // Chime-like short response
    await _tts.speak('Mmm?');
    await Future.delayed(const Duration(milliseconds: 600));

    // Listen for actual command
    _transcriptController.add('Listening...');
    final command = await _stt.listenOnce(timeoutSeconds: 8);

    if (command.isEmpty) {
      _setState(WakeWordState.idle);
      _listenForWakeWord();
      return;
    }

    _transcriptController.add(command);
    _setState(WakeWordState.processing);

    // Get AI response
    final rawResponse = await _llm.chat(command);
    final result = await DeviceSkillsService.handleResponse(rawResponse);

    _responseController.add(result.text);
    _setState(WakeWordState.speaking);

    await _tts.speak(result.text);
    await Future.delayed(const Duration(milliseconds: 500));

    _setState(WakeWordState.idle);
    if (_active) _listenForWakeWord();
  }

  /// Triggered from UI tap to start listening immediately (no wake word needed)
  Future<void> triggerManually() async {
    if (_state == WakeWordState.speaking || _state == WakeWordState.processing) {
      return;
    }
    _stt.stop();
    await _handleWakeWordDetected();
  }

  void _setState(WakeWordState state) {
    _state = state;
    _stateController.add(state);
  }

  WakeWordState get currentState => _state;

  void dispose() {
    _stateController.close();
    _transcriptController.close();
    _responseController.close();
  }
}
