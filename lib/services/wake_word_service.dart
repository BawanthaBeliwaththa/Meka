import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'tts_service.dart';
import 'llm_service.dart';
import 'device_skills_service.dart';
import 'voice_auth_service.dart';

enum WakeWordState { idle, listening, processing, speaking, error }

class WakeWordService {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _commandRecorder = AudioRecorder();
  final TtsService _tts = TtsService();
  final LlmService _llm = LlmService();
  final VoiceAuthService _voiceAuth = VoiceAuthService();

  final _stateCtrl = StreamController<WakeWordState>.broadcast();
  final _transcriptCtrl = StreamController<String>.broadcast();
  final _responseCtrl = StreamController<String>.broadcast();

  Stream<WakeWordState> get stateStream => _stateCtrl.stream;
  Stream<String> get transcriptStream => _transcriptCtrl.stream;
  Stream<String> get responseStream => _responseCtrl.stream;

  WakeWordState _state = WakeWordState.idle;
  bool _active = false;
  bool _sttReady = false;
  bool _isSpeechListening = false;

  static const List<String> _wakeWords = [
    'hey meka', 'hi meka', 'ok meka', 'okay meka', 'meka',
    'හේ මේකා', 'හයි මේකා', 'මේකා', 'මෙක්කා', 'හේ මෙකා', 'හේමේකා'
  ];

  Future<void> start() async {
    if (_active) return;

    final statuses = await [
      Permission.microphone,
      Permission.phone,
      Permission.sms,
      Permission.contacts,
      Permission.manageExternalStorage,
      Permission.systemAlertWindow,
    ].request();

    if (statuses[Permission.microphone]?.isGranted != true) {
      _setState(WakeWordState.error);
      return;
    }

    await WakelockPlus.enable();

    _sttReady = await _speech.initialize(
      onStatus: (status) {
        if (status == 'listening') {
          _isSpeechListening = true;
        } else if (status == 'done' || status == 'notListening') {
          _isSpeechListening = false;
          if (_active && _state == WakeWordState.idle) {
            Future.delayed(const Duration(milliseconds: 300), _listenLoop);
          }
        }
      },
      onError: (error) {
        _isSpeechListening = false;
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
    _commandRecorder.stop();
    _tts.stop();
    WakelockPlus.disable();
    _setState(WakeWordState.idle);
  }

  Future<void> _listenLoop() async {
    if (!_active || _state != WakeWordState.idle || !_sttReady) return;
    if (_isSpeechListening) return;

    try {
      _isSpeechListening = true;
      final systemLocale = await _speech.systemLocale();
      final locale = systemLocale?.localeId ?? 'en_US';

      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase();
          if (words.isNotEmpty) {
            _transcriptCtrl.add(words);
          }
          if (_wakeWords.any((w) => words.contains(w))) {
            _speech.cancel().then((_) => _processCommand());
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        localeId: locale,
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: false,
      );
    } catch (_) {
      _isSpeechListening = false;
      if (_active) {
        await Future.delayed(const Duration(seconds: 2));
        _listenLoop();
      }
    }
  }

  Future<void> _processCommand({bool bypassVoiceVerification = false}) async {
    if (!_active) return;
    _setState(WakeWordState.listening);

    // Audio chime to indicate listening
    await _tts.speak('Mm?');
    await Future.delayed(const Duration(milliseconds: 700));

    final dir = await getApplicationDocumentsDirectory();
    final pcmPath = '${dir.path}/current_command.raw';
    final file = File(pcmPath);
    if (await file.exists()) {
      await file.delete();
    }

    // Start recording command using record package (PCM format for pitch detection)
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

    // Record for up to 5 seconds
    await Future.delayed(const Duration(seconds: 5));
    await _commandRecorder.stop();

    if (!await file.exists()) {
      _setState(WakeWordState.idle);
      if (_active) _listenLoop();
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 2000) {
      _setState(WakeWordState.idle);
      if (_active) _listenLoop();
      return;
    }

    _setState(WakeWordState.processing);
    _transcriptCtrl.add('Verifying voice print...');

    // 1. Verify speaker pitch
    final double pitch = _calculateFundamentalFrequency(bytes);
    final bool isUser = bypassVoiceVerification || await _voiceAuth.verifySpeaker(pitch);

    if (!isUser) {
      _transcriptCtrl.add('Voice print verification failed.');
      _responseCtrl.add('Access denied. Voice print mismatch.');
      await _tts.speak('Voice print mismatch.');
      await Future.delayed(const Duration(seconds: 2));
      _setState(WakeWordState.idle);
      if (_active) _listenLoop();
      return;
    }

    _transcriptCtrl.add('Voice print verified. Processing command...');

    // 2. Add WAV header to PCM bytes
    final wavBytes = _addWavHeader(bytes, 16000);

    // 3. Send audio WAV directly to Gemini for multimodal answer and actions
    try {
      final rawResponse = await _llm.chatWithAudio(wavBytes);
      final result = await DeviceSkillsService.handleResponse(rawResponse);
      
      _responseCtrl.add(result.text);
      _setState(WakeWordState.speaking);
      await _tts.speak(result.text);
    } catch (_) {
      const msg = "Neural core connection error. Please try again.";
      _responseCtrl.add(msg);
      await _tts.speak(msg);
    }

    await Future.delayed(const Duration(milliseconds: 600));
    _setState(WakeWordState.idle);
    if (_active) _listenLoop();
  }

  /// Autocorrelation pitch algorithm
  double _calculateFundamentalFrequency(Uint8List bytes) {
    final buffer = bytes.buffer.asByteData();
    final samples = Int16List(bytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = buffer.getInt16(i * 2, Endian.little);
    }

    const int sampleRate = 16000;
    const int minFreq = 75;
    const int maxFreq = 300;
    const int minPeriod = sampleRate ~/ maxFreq;
    const int maxPeriod = sampleRate ~/ minFreq;

    int windowSize = 2000;
    if (samples.length < windowSize) {
      windowSize = samples.length;
    }

    int bestStartIndex = 0;
    double maxRms = 0.0;
    for (int i = 0; i < samples.length - windowSize; i += 500) {
      double sumSq = 0;
      for (int j = 0; j < windowSize; j++) {
        final s = samples[i + j].toDouble();
        sumSq += s * s;
      }
      final rms = double.parse((sumSq / windowSize).toString());
      if (rms > maxRms) {
        maxRms = rms;
        bestStartIndex = i;
      }
    }

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

  Uint8List _addWavHeader(Uint8List pcmBytes, int sampleRate) {
    final int fileSize = pcmBytes.length + 36;
    final int byteRate = sampleRate * 2;
    final header = ByteData(44);
    
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6d); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); //  
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // Mono
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

  Future<void> triggerManually() async {
    if (_state == WakeWordState.speaking || _state == WakeWordState.processing) return;
    if (_isSpeechListening) await _speech.stop();
    _processCommand(bypassVoiceVerification: true);
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
