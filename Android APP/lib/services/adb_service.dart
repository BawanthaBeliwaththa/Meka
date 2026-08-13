// lib/services/adb_service.dart — MEKA ADB over WiFi Service
// Communicates with the IoT Hub's /api/adb/* endpoints to control
// connected Android devices remotely.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdbDevice {
  final String serial;
  final String status;
  final String? model;
  final String? androidVersion;
  final bool connected;

  AdbDevice({
    required this.serial,
    required this.status,
    this.model,
    this.androidVersion,
    required this.connected,
  });

  factory AdbDevice.fromJson(Map<String, dynamic> j) => AdbDevice(
        serial: j['serial'] ?? '',
        status: j['status'] ?? 'unknown',
        model: j['model'],
        androidVersion: j['android_version'],
        connected: (j['status'] ?? '') == 'device',
      );

  String get displayName => model ?? serial;
}

class AdbResult {
  final bool success;
  final String message;
  final dynamic data;

  AdbResult({required this.success, required this.message, this.data});
}

class AdbService {
  static final AdbService _instance = AdbService._internal();
  factory AdbService() => _instance;
  AdbService._internal();

  String _hubUrl = 'http://localhost:5000';

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _hubUrl = prefs.getString('iot_hub_url') ?? 'http://localhost:5000';
  }

  Future<AdbResult> _hubGet(String path) async {
    try {
      final r = await http.get(Uri.parse('$_hubUrl$path')).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        return AdbResult(success: true, message: 'OK', data: jsonDecode(r.body));
      }
      return AdbResult(success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return AdbResult(success: false, message: 'Connection error: $e');
    }
  }

  Future<AdbResult> _hubPost(String path, {Map<String, dynamic>? body}) async {
    try {
      final r = await http
          .post(
            Uri.parse('$_hubUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: body != null ? jsonEncode(body) : '{}',
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 || r.statusCode == 201) {
        return AdbResult(success: true, message: 'OK', data: jsonDecode(r.body));
      }
      return AdbResult(success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return AdbResult(success: false, message: 'Connection error: $e');
    }
  }

  /// List all ADB-connected devices
  Future<List<AdbDevice>> listDevices() async {
    final r = await _hubGet('/api/adb/devices');
    if (r.success && r.data != null) {
      final list = (r.data['devices'] as List?) ?? [];
      return list.map((d) => AdbDevice.fromJson(d as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// Unlock device screen via ADB (swipe up + optional pin)
  /// The Hub handles pin delivery via ADB input text
  Future<AdbResult> unlockDevice(String serial, {String? pin}) async {
    return _hubPost('/api/adb/${Uri.encodeComponent(serial)}/unlock', body: {
      if (pin != null) 'pin': pin,
    });
  }

  /// Execute arbitrary ADB shell command
  Future<AdbResult> runShell(String serial, String command) async {
    return _hubPost('/api/adb/${Uri.encodeComponent(serial)}/shell', body: {
      'command': command,
    });
  }

  /// Take screenshot via ADB and return base64 PNG
  Future<AdbResult> screenshot(String serial) async {
    return _hubGet('/api/adb/${Uri.encodeComponent(serial)}/screenshot');
  }

  /// Start scrcpy mirror session
  Future<AdbResult> startMirror(String serial) async {
    return _hubPost('/api/adb/${Uri.encodeComponent(serial)}/mirror/start');
  }

  /// Stop scrcpy mirror session
  Future<AdbResult> stopMirror(String serial) async {
    return _hubPost('/api/adb/${Uri.encodeComponent(serial)}/mirror/stop');
  }

  /// Connect a new ADB over WiFi device (e.g. 192.168.1.100:5555)
  Future<AdbResult> connectWifi(String hostAndPort) async {
    return _hubPost('/api/adb/connect', body: {'host': hostAndPort});
  }

  /// Disconnect ADB device
  Future<AdbResult> disconnect(String serial) async {
    return _hubPost('/api/adb/${Uri.encodeComponent(serial)}/disconnect');
  }

  /// Install APK on device
  Future<AdbResult> installApk(String serial, String apkPath) async {
    return _hubPost('/api/adb/${Uri.encodeComponent(serial)}/install', body: {
      'apk_path': apkPath,
    });
  }

  /// Get device info (battery, model, android version)
  Future<AdbResult> getDeviceInfo(String serial) async {
    return _hubGet('/api/adb/${Uri.encodeComponent(serial)}/info');
  }
}
