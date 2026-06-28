import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'tts_service.dart';
import 'llm_service.dart';
import 'device_skills_service.dart';

enum WakeWordState { idle, listening, processing, speaking, error }

class WakeWordService {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

  // Single initialized STT instance — NEVER create a second one
  final stt.SpeechToText _speech = stt.SpeechToText();
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
  bool _sttReady = false;

  static const List<String> _wakeWords = [
    'hey meka', 'hi meka', 'ok meka', 'okay meka', 'meka',
  ];

  Future<void> start() async {
    if (_active) return;

    // Request permissions
    await [Permission.microphone, Permission.speech].request();

    // Initialize STT once
    _sttReady = await _speech.initialize(
      onStatus: (status) {
        // Android stops listening after silence — restart the loop
        if (status == 'done' || status == 'notListening') {
          if (_active && _state == WakeWordState.idle) {
            Future.delayed(const Duration(milliseconds: 300), _listenLoop);
          }
        }
      },
      onError: (error) {
        if (_active && _state == WakeWordState.idle) {
          Future.delayed(const Duration(seconds: 2), _listenLoop);
        }
      },
    );

    if (!_sttReady) {
      _setState(WakeWordState.error);
      return;
    }

    await _llm.loadSettings();
    _active = true;
    _setState(WakeWordState.idle);
    _listenLoop();
  }

  void stop() {
    _active = false;
    _speech.stop();
    _tts.stop();
    _setState(WakeWordState.idle);
  }

  /// Continuous passive listening loop for wake word detection
  Future<void> _listenLoop() async {
    if (!_active || _state != WakeWordState.idle) return;
    if (!_sttReady) return;
    if (_speech.isListening) await _speech.stop();

    await Future.delayed(const Duration(milliseconds: 200));

    String heard = '';
    bool wakeDetected = false;

    await _speech.listen(
      onResult: (result) {
        heard = result.recognizedWords.toLowerCase();
        _transcriptCtrl.add(heard);
        if (_wakeWords.any((w) => heard.contains(w)) && !wakeDetected) {
          wakeDetected = true;
        }
        if (result.finalResult && wakeDetected) {
          _onWakeWord();
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
      listenMode: stt.ListenMode.confirmation,
      cancelOnError: true,
    );
  }

  void _onWakeWord() {
    if (_state != WakeWordState.idle || !_active) return;
    _processCommand();
  }

  Future<void> _processCommand() async {
    if (_state != WakeWordState.idle) return;
    _setState(WakeWordState.listening);
    await _speech.stop();

    // Short acknowledgement beep via TTS
    _tts.speak('Mm?');
    await Future.delayed(const Duration(milliseconds: 700));

    // Now listen for the actual command
    _transcriptCtrl.add('Listening for your command...');
    String command = '';
    final cmdCompleter = Completer<void>();

    await _speech.listen(
      onResult: (result) {
        command = result.recognizedWords;
        _transcriptCtrl.add(command);
        if (result.finalResult && !cmdCompleter.isCompleted) {
          cmdCompleter.complete();
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 4),
      localeId: 'en_US',
      listenMode: stt.ListenMode.dictation,
      cancelOnError: true,
    );

    // Wait for final result or timeout
    await cmdCompleter.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {},
    );
    await _speech.stop();

    if (command.trim().isEmpty) {
      await _tts.speak("I didn't catch that. Try again?");
      _setState(WakeWordState.idle);
      if (_active) _listenLoop();
      return;
    }

    await _runCommand(command.trim());
  }

  Future<void> _runCommand(String command) async {
    _setState(WakeWordState.processing);
    _transcriptCtrl.add(command);

    try {
      final rawResponse = await _llm.chat(command);
      final result = await DeviceSkillsService.handleResponse(rawResponse);
      _responseCtrl.add(result.text);
      _setState(WakeWordState.speaking);
      await _tts.speak(result.text);
    } catch (e) {
      _responseCtrl.add("Sorry, something went wrong. Please try again.");
      await _tts.speak("Sorry, something went wrong.");
    }

    await Future.delayed(const Duration(milliseconds: 400));
    _setState(WakeWordState.idle);
    if (_active) _listenLoop();
  }

  /// Called when user taps the orb — skip the wake word
  Future<void> triggerManually() async {
    if (_state == WakeWordState.speaking || _state == WakeWordState.processing) {
      return;
    }
    if (_speech.isListening) await _speech.stop();
    _setState(WakeWordState.idle);
    await _processCommand();
  }

  void _setState(WakeWordState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  WakeWordState get currentState => _state;

  void dispose() {
    _stateCtrl.close();
    _transcriptCtrl.close();
    _responseCtrl.close();
  }
}
