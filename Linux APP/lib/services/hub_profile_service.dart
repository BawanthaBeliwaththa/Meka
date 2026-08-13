// lib/services/hub_profile_service.dart — MEKA Multi-Hub Profile Manager
// Allows users to store and switch between multiple MEKA IoT Hub instances.
// Designed for the MEKA product model: each customer has their own hub.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ──────────────────────────────────────────────────────────────
class HubProfile {
  final String id;
  final String name;
  final String url;       // e.g. "http://192.168.1.100:5000"
  final int colorIndex;   // 0=cyan, 1=purple, 2=green, 3=orange
  bool isOnline;

  HubProfile({
    required this.id,
    required this.name,
    required this.url,
    this.colorIndex = 0,
    this.isOnline = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'colorIndex': colorIndex,
      };

  factory HubProfile.fromJson(Map<String, dynamic> j) => HubProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        colorIndex: (j['colorIndex'] as int?) ?? 0,
      );

  String get baseUrl {
    final u = url.trim();
    final h = u.startsWith('http') ? u : 'http://$u';
    return h.endsWith('/') ? h.substring(0, h.length - 1) : h;
  }

  @override
  String toString() => 'HubProfile($name @ $url)';
}

// ── Service ────────────────────────────────────────────────────────────
class HubProfileService {
  static final HubProfileService _instance = HubProfileService._internal();
  factory HubProfileService() => _instance;
  HubProfileService._internal();

  static const _profilesKey = 'hub_profiles';
  static const _activeIdKey  = 'hub_active_id';
  static const _timeout = Duration(seconds: 6);

  List<HubProfile> _profiles = [];
  String? _activeId;

  List<HubProfile> get profiles => List.unmodifiable(_profiles);

  HubProfile? get activeProfile {
    if (_activeId == null) return _profiles.isEmpty ? null : _profiles.first;
    try {
      return _profiles.firstWhere((p) => p.id == _activeId);
    } catch (_) {
      return _profiles.isEmpty ? null : _profiles.first;
    }
  }

  // ── Persistence ──────────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _activeId = prefs.getString(_activeIdKey);
    final raw = prefs.getString(_profilesKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _profiles = list.map((e) => HubProfile.fromJson(e as Map<String, dynamic>)).toList();
    }

    // Migrate legacy single-hub setting
    if (_profiles.isEmpty) {
      final legacyUrl = prefs.getString('iot_hub_host') ?? '';
      if (legacyUrl.isNotEmpty) {
        final legacy = HubProfile(
          id: 'hub_default',
          name: 'My Home Hub',
          url: legacyUrl,
          colorIndex: 0,
        );
        _profiles.add(legacy);
        _activeId = legacy.id;
        await _save(prefs);
      }
    }
  }

  Future<void> _save([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(
      _profilesKey,
      jsonEncode(_profiles.map((e) => e.toJson()).toList()),
    );
    if (_activeId != null) await p.setString(_activeIdKey, _activeId!);
    // Keep legacy key in sync so IotHubService still works
    final active = activeProfile;
    if (active != null) await p.setString('iot_hub_host', active.url);
  }

  // ── CRUD ─────────────────────────────────────────────────────────
  Future<void> addProfile(HubProfile profile) async {
    _profiles.add(profile);
    _activeId ??= profile.id;
    await _save();
  }

  Future<void> updateProfile(HubProfile profile) async {
    final idx = _profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      _profiles[idx] = profile;
      await _save();
    }
  }

  Future<void> deleteProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) {
      _activeId = _profiles.isEmpty ? null : _profiles.first.id;
    }
    await _save();
  }

  Future<void> setActive(String id) async {
    _activeId = id;
    await _save();
  }

  // ── Connectivity ─────────────────────────────────────────────────
  /// Ping a hub URL and return its status info. Returns null if unreachable.
  Future<Map<String, dynamic>?> testHub(String url) async {
    final u = url.trim().startsWith('http') ? url.trim() : 'http://${url.trim()}';
    final base = u.endsWith('/') ? u.substring(0, u.length - 1) : u;
    try {
      final resp = await http
          .get(Uri.parse('$base/api/status'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Check online status of all profiles and update their isOnline flag.
  Future<void> refreshOnlineStatus() async {
    await Future.wait(_profiles.map((p) async {
      final result = await testHub(p.url);
      p.isOnline = result != null;
    }));
  }

  /// Generate a unique ID for a new profile.
  String generateId() =>
      'hub_${DateTime.now().millisecondsSinceEpoch}';
}
