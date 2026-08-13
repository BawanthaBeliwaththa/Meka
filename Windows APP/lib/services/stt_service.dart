import 'dart:async';

class SttService {
  bool _initialized = false;
  bool _listening = false;

  Future<bool> initialize() async {
    _initialized = true;
    return true;
  }

  Future<String> listenOnce({int timeoutSeconds = 8}) async {
    await initialize();
    return '';
  }

  Stream<String> listenStream() {
    final controller = StreamController<String>();
    return controller.stream;
  }

  void stop() {
    _listening = false;
  }

  bool get isListening => _listening;
}
