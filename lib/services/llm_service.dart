import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Message {
  final String role; // 'user' or 'model'
  final String text;
  final DateTime timestamp;

  Message({required this.role, required this.text, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toGeminiPart() => {
        'role': role,
        'parts': [
          {'text': text}
        ]
      };

  Map<String, String> toJson() =>
      {'role': role, 'text': text, 'timestamp': timestamp.toIso8601String()};
}

class LlmService {
  static final LlmService _instance = LlmService._internal();
  factory LlmService() => _instance;
  LlmService._internal();

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent';
  static const int _maxHistory = 20;

  final List<Message> _history = [];
  String _apiKey = '';
  String _userName = 'Bawantha';

  List<Message> get history => List.unmodifiable(_history);

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('gemini_api_key') ?? '';
    _userName = prefs.getString('user_name') ?? 'Bawantha';
  }

  Future<void> saveSettings(
      {required String apiKey, required String userName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', apiKey);
    await prefs.setString('user_name', userName);
    _apiKey = apiKey;
    _userName = userName;
  }

  String get _systemPrompt => '''You are Meka, the personal AI assistant of $_userName.
You are always listening and always ready to help.
You have access to the user's device and can perform actions on their behalf.
Respond in a natural, concise, friendly way — like Siri or Google Assistant.
Keep responses short unless the user asks for detail.
Current date and time: ${DateTime.now().toString()}
Always address the user by their name occasionally to make it personal.
If asked to do a device action (call, alarm, open app, etc), respond with a JSON command like:
{"action": "open_app", "app": "youtube"}
{"action": "set_alarm", "hour": 7, "minute": 0, "label": "Morning"}
{"action": "send_sms", "to": "Mom", "message": "I'll be late"}
{"action": "web_search", "query": "weather today"}
{"action": "set_volume", "level": 50}
Otherwise respond with plain natural language.''';

  Future<String> chat(String userMessage) async {
    if (_apiKey.isEmpty) {
      return "I don't have a Gemini API key yet. Please go to Settings and add your key.";
    }

    _history.add(Message(role: 'user', text: userMessage));

    // Keep history bounded
    while (_history.length > _maxHistory * 2) {
      _history.removeAt(0);
    }

    final contents = [
      {
        'role': 'user',
        'parts': [
          {'text': _systemPrompt}
        ]
      },
      ..._history.map((m) => m.toGeminiPart()),
    ];

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'contents': contents}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        _history.add(Message(role: 'model', text: reply));
        return reply;
      } else {
        final err = jsonDecode(response.body);
        return "Hmm, I had trouble connecting. ${err['error']?['message'] ?? 'Please try again.'}";
      }
    } catch (e) {
      return "I'm having trouble connecting right now. Please check your internet connection.";
    }
  }

  void clearHistory() => _history.clear();
}
