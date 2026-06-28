import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Message {
  final String role;
  final String text;
  final DateTime timestamp;

  Message({required this.role, required this.text, DateTime? ts})
      : timestamp = ts ?? DateTime.now();

  Map<String, dynamic> toGemini() => {
        'role': role,
        'parts': [
          {'text': text}
        ]
      };
}

class LlmService {
  static final LlmService _instance = LlmService._internal();
  factory LlmService() => _instance;
  LlmService._internal();

  static const String _url =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  final List<Message> _history = [];
  String _apiKey = '';
  String _userName = 'Sir';

  List<Message> get history => List.unmodifiable(_history);

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('gemini_api_key') ?? '';
    _userName = prefs.getString('user_name') ?? 'Sir';
  }

  Future<void> saveSettings(
      {required String apiKey, required String userName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', apiKey);
    await prefs.setString('user_name', userName);
    _apiKey = apiKey;
    _userName = userName;
  }

  String get _systemPrompt {
    final now = DateTime.now();
    return '''You are MEKA — an advanced AI personal assistant, inspired by JARVIS from Iron Man. You serve exclusively ${_userName}.

PERSONALITY:
- Sophisticated, intelligent, slightly witty — like a trusted colleague who's also a genius
- Proactive, anticipatory, always one step ahead
- Occasionally brief with dry humor, never sarcastic in a harmful way
- Address the user as "$_userName" naturally, not every sentence
- Speak in short, confident, actionable sentences. Maximum 2-3 sentences unless more is needed.
- Never say "I'm just an AI" or "I cannot" — find creative ways to help or explain limitations naturally.

CAPABILITIES (use JSON commands for device actions):
- Open apps: {"action":"open_app","app":"youtube"}
- Set alarm: {"action":"set_alarm","hour":7,"minute":0,"label":"Morning"}
- Send SMS: {"action":"send_sms","to":"Mom","message":"I'll be late"}
- Call someone: {"action":"make_call","to":"John"}
- Set volume: {"action":"set_volume","level":50}
- Web search: {"action":"web_search","query":"weather in Colombo"}
- Take photo: {"action":"take_photo"}
- WiFi settings: {"action":"toggle_wifi"}
- Bluetooth: {"action":"toggle_bluetooth"}

When performing an action, put the JSON on its own line, then add a natural spoken confirmation.

Current time: ${now.hour}:${now.minute.toString().padLeft(2, '0')}
Current date: ${['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][now.weekday - 1]}, ${now.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][now.month - 1]} ${now.year}
''';
  }

  Future<String> chat(String userMessage) async {
    if (_apiKey.isEmpty) {
      return "I need my intelligence module configured, $_userName. Please add a Gemini API key in Settings.";
    }

    _history.add(Message(role: 'user', text: userMessage));
    if (_history.length > 40) _history.removeAt(0);

    final contents = [
      {
        'role': 'user',
        'parts': [
          {'text': _systemPrompt}
        ]
      },
      ..._history.map((m) => m.toGemini()),
    ];

    try {
      final response = await http
          .post(
            Uri.parse('$_url?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'contents': contents}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        _history.add(Message(role: 'model', text: reply));
        return reply;
      } else {
        final err = jsonDecode(response.body);
        return "I'm experiencing interference, $_userName. ${err['error']?['message'] ?? 'Please try again.'}";
      }
    } catch (e) {
      return "Connection lost, $_userName. Check your network and try again.";
    }
  }

  Future<String> chatWithAudio(Uint8List wavBytes) async {
    if (_apiKey.isEmpty) {
      return "I need my intelligence module configured, $_userName. Please add a Gemini API key in Settings.";
    }

    final base64Audio = base64Encode(wavBytes);

    final contents = [
      {
        'role': 'user',
        'parts': [
          {'text': _systemPrompt},
          {
            'inlineData': {
              'mimeType': 'audio/wav',
              'data': base64Audio
            }
          },
          {'text': 'Listen to the audio user command, transcribe it, and fulfill it.'}
        ]
      }
    ];

    try {
      final response = await http
          .post(
            Uri.parse('$_url?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'contents': contents}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        
        _history.add(Message(role: 'user', text: '[Spoken voice command]'));
        _history.add(Message(role: 'model', text: reply));
        if (_history.length > 40) _history.removeAt(0);
        
        return reply;
      } else {
        final err = jsonDecode(response.body);
        return "I'm experiencing interference, $_userName. ${err['error']?['message'] ?? 'Please try again.'}";
      }
    } catch (e) {
      return "Connection lost, $_userName. Check your network and try again.";
    }
  }

  void clearHistory() => _history.clear();
}
