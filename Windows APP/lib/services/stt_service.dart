import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: (status) {},
      onError: (error) {},
    );
    return _initialized;
  }

  /// Listen once and return the transcribed text
  Future<String> listenOnce({int timeoutSeconds = 8}) async {
    await initialize();
    final completer = Completer<String>();
    String result = '';

    await _speech.listen(
      onResult: (val) {
        if (val.finalResult) {
          result = val.recognizedWords;
          if (!completer.isCompleted) completer.complete(result);
        }
      },
      listenFor: Duration(seconds: timeoutSeconds),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );

    // Timeout fallback
    Future.delayed(Duration(seconds: timeoutSeconds + 2), () {
      if (!completer.isCompleted) completer.complete(result);
    });

    return completer.future;
  }

  /// Stream of partial words while listening
  Stream<String> listenStream() {
    final controller = StreamController<String>();
    initialize().then((_) {
      _speech.listen(
        onResult: (val) => controller.add(val.recognizedWords),
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: 'en_US',
      );
    });
    return controller.stream;
  }

  void stop() => _speech.stop();
  bool get isListening => _speech.isListening;
}
