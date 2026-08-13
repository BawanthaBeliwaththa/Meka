import 'dart:io';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  Process? _currentProcess;
  void Function()? _onComplete;

  Future<void> speak(String text) async {
    await stop();

    try {
      // Use Linux native speech-dispatcher (spd-say)
      _currentProcess = await Process.start('spd-say', [text]);
      _currentProcess?.exitCode.then((_) {
        if (_onComplete != null) {
          _onComplete!();
        }
      });
    } catch (_) {
      // Fallback if spd-say is not installed
      try {
        _currentProcess = await Process.start('espeak', [text]);
        _currentProcess?.exitCode.then((_) {
          if (_onComplete != null) {
            _onComplete!();
          }
        });
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    if (_currentProcess != null) {
      _currentProcess?.kill();
      _currentProcess = null;
    }
    try {
      await Process.run('spd-say', ['-S']);
    } catch (_) {}
  }

  void onComplete(void Function() callback) {
    _onComplete = callback;
  }
}
