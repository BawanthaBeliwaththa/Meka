import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Communicates with the Meka IoT Hub Python service
class IotHubService {
  static final IotHubService _instance = IotHubService._internal();
  factory IotHubService() => _instance;
  IotHubService._internal();

  static const String _prefKey = 'iot_hub_host';
  static const Duration _timeout = Duration(seconds: 8);

  String _host = '';

  String get host => _host;
  bool get isConfigured => _host.isNotEmpty;

  /// Load saved hub host from preferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_prefKey) ?? '';
  }

  /// Save hub host to preferences
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

  // ── Hub Status ─────────────────────────────────────────────────

  /// Test connectivity to the IoT hub
  Future<bool> testConnection() async {
    if (!isConfigured) return false;
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get hub status overview
  Future<Map<String, dynamic>?> getStatus() async {
    return _get('/api/status');
  }

  // ── Device Management ──────────────────────────────────────────

  /// List all discovered devices
  Future<Map<String, dynamic>?> listDevices({
    String? type,
    String? capability,
    bool onlineOnly = false,
  }) async {
    String path = '/api/devices';
    final params = <String>[];
    if (type != null) params.add('type=$type');
    if (capability != null) params.add('capability=$capability');
    if (onlineOnly) params.add('online=true');
    if (params.isNotEmpty) path += '?${params.join('&')}';
    return _get(path);
  }

  /// Trigger a network scan
  Future<Map<String, dynamic>?> triggerScan() async {
    return _post('/api/devices/scan', {});
  }

  /// Grant permission to a device
  Future<Map<String, dynamic>?> permitDevice(String mac) async {
    return _post('/api/devices/$mac/permit', {});
  }

  /// Revoke permission from a device
  Future<Map<String, dynamic>?> revokeDevice(String mac) async {
    return _post('/api/devices/$mac/revoke', {});
  }

  /// Grant permission to all pending devices
  Future<Map<String, dynamic>?> grantAllPending() async {
    return _post('/api/permissions/grant-all', {});
  }

  /// Get permission summary
  Future<Map<String, dynamic>?> getPermissions() async {
    return _get('/api/permissions');
  }

  // ── Camera Operations ──────────────────────────────────────────

  /// List available cameras
  Future<Map<String, dynamic>?> listCameras() async {
    return _get('/api/cameras');
  }

  /// Start recording from a specific camera
  Future<Map<String, dynamic>?> startRecording(String mac, {
    String? streamUrl,
  }) async {
    final body = <String, dynamic>{};
    if (streamUrl != null) body['stream_url'] = streamUrl;
    return _post('/api/cameras/$mac/record/start', body);
  }

  /// Stop recording from a specific camera
  Future<Map<String, dynamic>?> stopRecording(String mac) async {
    return _post('/api/cameras/$mac/record/stop', {});
  }

  /// Start recording from ALL cameras
  Future<Map<String, dynamic>?> startRecordingAll() async {
    return _post('/api/cameras/record/start-all', {});
  }

  /// Stop ALL recordings
  Future<Map<String, dynamic>?> stopRecordingAll() async {
    return _post('/api/cameras/record/stop-all', {});
  }

  /// Get recording status
  Future<Map<String, dynamic>?> getRecordingStatus() async {
    return _get('/api/cameras/recording-status');
  }

  /// Get MJPEG stream URL for a camera
  String getCameraStreamUrl(String mac) {
    return '$_baseUrl/api/cameras/$mac/stream';
  }

  /// Get snapshot URL for a camera
  String getCameraSnapshotUrl(String mac) {
    return '$_baseUrl/api/cameras/$mac/snapshot';
  }

  // ── Recording History ──────────────────────────────────────────

  /// List all recordings
  Future<Map<String, dynamic>?> listRecordings({
    String? cameraMac,
    int limit = 50,
  }) async {
    String path = '/api/recordings?limit=$limit';
    if (cameraMac != null) path += '&camera=$cameraMac';
    return _get(path);
  }

  // ── Audio Routing ──────────────────────────────────────────────

  /// List available microphones
  Future<Map<String, dynamic>?> listMicrophones() async {
    return _get('/api/audio/microphones');
  }

  /// List available speakers
  Future<Map<String, dynamic>?> listSpeakers() async {
    return _get('/api/audio/speakers');
  }

  /// Select active microphone
  Future<Map<String, dynamic>?> selectMic(String mac) async {
    return _post('/api/audio/mic/select', {'mac': mac});
  }

  /// Select active speaker
  Future<Map<String, dynamic>?> selectSpeaker(String mac) async {
    return _post('/api/audio/speaker/select', {'mac': mac});
  }

  /// Get audio fallback status
  Future<Map<String, dynamic>?> getAudioFallback() async {
    return _get('/api/audio/fallback');
  }

  // ── Fallback Status ────────────────────────────────────────────

  /// Get comprehensive fallback status
  Future<Map<String, dynamic>?> getFallbackStatus() async {
    return _get('/api/fallback/status');
  }

  /// Get fallback event log
  Future<Map<String, dynamic>?> getFallbackEvents() async {
    return _get('/api/fallback/events');
  }

  // ── Bluetooth Management ───────────────────────────────────────

  /// Scan for nearby Bluetooth devices
  Future<Map<String, dynamic>?> scanBluetooth() async {
    return _get('/api/bluetooth/scan');
  }

  /// Connect to a Bluetooth device
  Future<Map<String, dynamic>?> connectBluetooth(String macOrId) async {
    return _post('/api/bluetooth/connect', {'mac': macOrId});
  }

  /// Get list of Bluetooth devices
  Future<Map<String, dynamic>?> getBluetoothDevices() async {
    return _get('/api/bluetooth/devices');
  }

  // ── Internal HTTP Helpers ──────────────────────────────────────

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

  Future<Map<String, dynamic>?> _post(
    String path, Map<String, dynamic> body,
  ) async {
    if (!isConfigured) return null;
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
