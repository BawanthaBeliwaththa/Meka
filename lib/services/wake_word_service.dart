import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'tts_service.dart';
import 'llm_service.dart';
import 'device_skills_service.dart';

enum WakeWordState { idle, listening, processing, speaking, error }

class WakeWordService {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

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

    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _setState(WakeWordState.error);
      return;
    }

    // Keep CPU awake while listening
    await WakelockPlus.enable();

    // Initialize STT — ONE instance, ONE time
    _sttReady = await _speech.initialize(
      onStatus: (status) {
        if (_active && _state == WakeWordState.idle &&
            (status == 'done' || status == 'notListening')) {
          Future.delayed(const Duration(milliseconds: 400), _listenLoop);
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
    WakelockPlus.disable();
    _setState(WakeWordState.idle);
  }

  Future<void> _listenLoop() async {
    if (!_active || _state != WakeWordState.idle || !_sttReady) return;
    if (_speech.isListening) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    String heard = '';
    bool detected = false;

    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase();
          if (words.isNotEmpty) {
            heard = words;
            _transcriptCtrl.add(heard);
          }
          if (!detected && _wakeWords.any((w) => words.contains(w))) {
            detected = true;
            _speech.stop().then((_) => _processCommand());
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_US',
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: false,
      );
    } catch (_) {
      if (_active) {
        await Future.delayed(const Duration(seconds: 2));
        _listenLoop();
      }
    }
  }

  Future<void> _processCommand() async {
    if (!_active || _state != WakeWordState.idle) return;
    _setState(WakeWordState.listening);
    _tts.speak('Mmm?');
    await Future.delayed(const Duration(milliseconds: 800));

    _transcriptCtrl.add('Listening...');
    String command = '';
    final done = Completer<void>();

    try {
      await _speech.listen(
        onResult: (result) {
          command = result.recognizedWords;
          _transcriptCtrl.add(command);
          if (result.finalResult && !done.isCompleted) done.complete();
        },
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 4),
        localeId: 'en_US',
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
      );
    } catch (_) {}

    await done.future.timeout(const Duration(seconds: 14), onTimeout: () {});
    if (_speech.isListening) await _speech.stop();

    if (command.trim().isEmpty) {
      await _tts.speak("I didn't catch that.");
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
    } catch (_) {
      const msg = "Something went wrong. Please try again.";
      _responseCtrl.add(msg);
      await _tts.speak(msg);
    }

    await Future.delayed(const Duration(milliseconds: 400));
    _setState(WakeWordState.idle);
    if (_active) _listenLoop();
  }

  Future<void> triggerManually() async {
    if (_state == WakeWordState.speaking || _state == WakeWordState.processing) return;
    if (_speech.isListening) await _speech.stop();
    _setState(WakeWordState.idle);
    _processCommand();
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
