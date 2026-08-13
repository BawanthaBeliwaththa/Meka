import 'dart:async';

class WakeWordService {
  bool _isListening = false;
  final StreamController<String> _transcriptController = StreamController<String>.broadcast();

  Stream<String> get transcriptStream => _transcriptController.stream;

  Future<bool> initialize() async {
    return true;
  }

  void startListening(Function(String) onWakeWordDetected) {
    _isListening = true;
  }

  void stopListening() {
    _isListening = false;
  }

  bool get isListening => _isListening;
}
