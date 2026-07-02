import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Result from an ESP32 HTTP command
class Esp32Result {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  Esp32Result({required this.success, required this.message, this.data});
}

/// Status snapshot from the ESP32 board
class Esp32Status {
  final String device;
  final String firmware;
  final int uptimeSeconds;
  final String ip;
  final int rssi;
  final List<bool> relays;
  final int servoAngle;

  Esp32Status({
    required this.device,
    required this.firmware,
    required this.uptimeSeconds,
    required this.ip,
    required this.rssi,
    required this.relays,
    required this.servoAngle,
  });

  factory Esp32Status.fromJson(Map<String, dynamic> json) {
    return Esp32Status(
      device: json['device'] ?? 'meka',
      firmware: json['firmware'] ?? '?',
      uptimeSeconds: json['uptime_s'] ?? 0,
      ip: json['ip'] ?? '',
      rssi: json['rssi'] ?? 0,
      relays: (json['relays'] as List<dynamic>? ?? [])
          .map((e) => e as bool)
          .toList(),
      servoAngle: json['servo_angle'] ?? 0,
    );
  }
}

class Esp32Service {
  static final Esp32Service _instance = Esp32Service._internal();
  factory Esp32Service() => _instance;
  Esp32Service._internal();

  static const String _prefKey = 'esp32_host';
  static const Duration _timeout = Duration(seconds: 5);

  String _host = '';

  String get host => _host;
  bool get isConfigured => _host.isNotEmpty;

  /// Load saved host from preferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_prefKey) ?? '';
  }

  /// Save host to preferences
  Future<void> saveHost(String host) async {
    _host = host.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _host);
  }

  String get _baseUrl {
    if (_host.isEmpty) return '';
    final h = _host.startsWith('http') ? _host : 'http://$_host';
    return h.endsWith('/') ? h.substring(0, h.length - 1) : h;
  }

  /// Test connectivity — returns true if board responds
  Future<bool> testConnection() async {
    if (!isConfigured) return false;
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/status'))
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get full board status
  Future<Esp32Status?> getStatus() async {
    if (!isConfigured) return null;
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/status'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return Esp32Status.fromJson(jsonDecode(resp.body));
      }
    } catch (_) {}
    return null;
  }

  /// Control a relay channel (1-indexed, state: "on" | "off" | "toggle")
  Future<Esp32Result> setRelay(int channel, String state) async {
    return _post('/relay', {'channel': channel, 'state': state},
        'Relay $channel → $state');
  }

  /// Set raw GPIO pin state
  Future<Esp32Result> setPin(int pin, String state) async {
    return _post('/pin', {'pin': pin, 'state': state},
        'Pin $pin → $state');
  }

  /// Set PWM duty cycle (0-255)
  Future<Esp32Result> setPwm(int pin, int duty) async {
    return _post('/pwm', {'pin': pin, 'duty': duty},
        'PWM pin $pin → duty $duty');
  }

  /// Move servo to angle (0-180)
  Future<Esp32Result> setServo(int angle) async {
    return _post('/servo', {'angle': angle},
        'Servo → $angle°');
  }

  /// Set NeoPixel LED colour
  Future<Esp32Result> setLed({int r = 0, int g = 0, int b = 0, int? brightness}) async {
    final body = brightness != null
        ? {'brightness': brightness}
        : {'r': r, 'g': g, 'b': b};
    return _post('/led', body, 'LED set');
  }

  /// Trigger buzzer for given duration
  Future<Esp32Result> buzz(int durationMs) async {
    return _post('/buzzer', {'duration_ms': durationMs}, 'Buzzer');
  }

  /// Read DHT22 temperature & humidity
  Future<Map<String, dynamic>?> readDht() async {
    return _get('/sensor/dht');
  }

  /// Read analog pin voltage
  Future<Map<String, dynamic>?> readAnalog() async {
    return _get('/sensor/analog');
  }

  /// Reset all outputs to defaults
  Future<Esp32Result> resetAll() async {
    return _post('/reset', {}, 'All outputs reset');
  }

  // ── Internal helpers ──────────────────────────────────────────────────

  Future<Esp32Result> _post(
      String path, Map<String, dynamic> body, String label) async {
    if (!isConfigured) {
      return Esp32Result(
          success: false,
          message: 'ESP32 not configured. Add IP in Settings.');
    }
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return Esp32Result(success: true, message: label, data: data);
      } else {
        return Esp32Result(
            success: false,
            message: 'ESP32 error ${resp.statusCode}');
      }
    } on Exception catch (e) {
      return Esp32Result(
          success: false,
          message: 'Could not reach ESP32: $e');
    }
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    if (!isConfigured) return null;
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl$path'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Parse a colour name into RGB values
  static Map<String, int> colorNameToRgb(String name) {
    final map = {
      'red':     {'r': 255, 'g': 0,   'b': 0},
      'green':   {'r': 0,   'g': 255, 'b': 0},
      'blue':    {'r': 0,   'g': 0,   'b': 255},
      'white':   {'r': 255, 'g': 255, 'b': 255},
      'yellow':  {'r': 255, 'g': 200, 'b': 0},
      'orange':  {'r': 255, 'g': 80,  'b': 0},
      'purple':  {'r': 128, 'g': 0,   'b': 255},
      'cyan':    {'r': 0,   'g': 212, 'b': 255},
      'magenta': {'r': 255, 'g': 0,   'b': 128},
      'pink':    {'r': 255, 'g': 105, 'b': 180},
      'off':     {'r': 0,   'g': 0,   'b': 0},
    };
    return map[name.toLowerCase()] ?? {'r': 255, 'g': 255, 'b': 255};
  }
}
