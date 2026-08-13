// lib/screens/device_manager_screen.dart — MEKA v3 Device Matrix
// Manages all ADB-connected Android devices + IoT network devices
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/adb_service.dart';
import '../services/iot_hub_service.dart';

class DeviceManagerScreen extends StatefulWidget {
  const DeviceManagerScreen({super.key});

  @override
  State<DeviceManagerScreen> createState() => _DeviceManagerScreenState();
}

class _DeviceManagerScreenState extends State<DeviceManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AdbDevice> _adbDevices = [];
  List<dynamic> _networkDevices = [];
  bool _loadingAdb = false;
  bool _loadingNet = false;
  String? _selectedSerial;
  final List<_ShellEntry> _shellLog = [];
  final TextEditingController _shellController = TextEditingController();
  bool _shellRunning = false;

  static const _cyan = Color(0xFF00F0FF);
  static const _pink = Color(0xFFFF0055);
  static const _purple = Color(0xFF7C3AED);
  static const _green = Color(0xFF00FF66);
  static const _yellow = Color(0xFFFCEE0A);
  static const _bg = Color(0xFF030712);
  static const _bgCard = Color(0xFF080C1E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _shellController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await AdbService().loadSettings();
    _loadAdb();
    _loadNetwork();
  }

  Future<void> _loadAdb() async {
    if (!mounted) return;
    setState(() => _loadingAdb = true);
    final devs = await AdbService().listDevices();
    if (mounted) setState(() { _adbDevices = devs; _loadingAdb = false; });
  }

  Future<void> _loadNetwork() async {
    if (!mounted) return;
    setState(() => _loadingNet = true);
    final result = await IotHubService().listDevices(onlineOnly: true);
    if (mounted) {
      setState(() {
        _networkDevices = (result?['devices'] as List?) ?? [];
        _loadingNet = false;
      });
    }
  }

  Future<void> _unlock(String serial, String displayName) async {
    // Security: require biometric confirmation
    try {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _cyan, width: 1)),
          title: const Text('Confirm Unlock', style: TextStyle(color: _cyan, fontFamily: 'Orbitron', fontSize: 14, letterSpacing: 2)),
          content: Text('Unlock $displayName?\n\nThis action requires your authorization.', style: const TextStyle(color: Colors.white70, fontSize: 14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white38))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _green.withValues(alpha: 0.2), side: const BorderSide(color: _green)),
              child: const Text('CONFIRM UNLOCK', style: TextStyle(color: _green, fontFamily: 'Orbitron', fontSize: 11)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } catch (_) {}

    _snack('🔓 Sending unlock command to $displayName...', _cyan);
    final r = await AdbService().unlockDevice(serial);
    if (mounted) {
      _snack(r.success ? '✅ $displayName unlocked!' : '❌ Unlock failed: ${r.message}', r.success ? _green : _pink);
    }
  }

  Future<void> _screenshot(String serial) async {
    _snack('📸 Capturing screenshot...', _yellow);
    final r = await AdbService().screenshot(serial);
    if (mounted) {
      if (r.success) {
        _snack('✅ Screenshot captured!', _green);
      } else {
        _snack('❌ Screenshot failed: ${r.message}', _pink);
      }
    }
  }

  Future<void> _mirror(String serial) async {
    _snack('🖥️ Starting screen mirror...', _purple);
    final r = await AdbService().startMirror(serial);
    if (mounted) {
      _snack(r.success ? '✅ Mirror started! Check your browser.' : '❌ Mirror failed: ${r.message}',
          r.success ? _green : _pink);
    }
  }

  Future<void> _runShell(String serial) async {
    final cmd = _shellController.text.trim();
    if (cmd.isEmpty || _shellRunning) return;
    _shellController.clear();
    setState(() {
      _shellLog.add(_ShellEntry(type: 'input', text: '$ $cmd'));
      _shellRunning = true;
    });
    final r = await AdbService().runShell(serial, cmd);
    if (mounted) {
      setState(() {
        _shellLog.add(_ShellEntry(
          type: r.success ? 'output' : 'error',
          text: r.success ? (r.data?['output'] ?? '(no output)') : 'ERR: ${r.message}',
        ));
        _shellRunning = false;
      });
    }
  }

  Future<void> _connectWifi() async {
    final ctrl = TextEditingController(text: '192.168.1.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _cyan)),
        title: const Text('ADB WiFi Connect', style: TextStyle(color: _cyan, fontFamily: 'Orbitron', fontSize: 13, letterSpacing: 2)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter device IP:PORT\ne.g. 192.168.1.100:5555', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white, fontFamily: 'Courier'),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderSide: BorderSide(color: _cyan.withValues(alpha: 0.4))),
              filled: true, fillColor: Colors.black38,
              hintText: 'IP:PORT', hintStyle: const TextStyle(color: Colors.white24),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _cyan.withValues(alpha: 0.15), side: const BorderSide(color: _cyan)),
            child: const Text('CONNECT', style: TextStyle(color: _cyan, fontFamily: 'Orbitron', fontSize: 11)),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      _snack('⏳ Connecting to ${ctrl.text}...', _cyan);
      final r = await AdbService().connectWifi(ctrl.text.trim());
      if (mounted) {
        _snack(r.success ? '✅ Connected!' : '❌ Failed: ${r.message}', r.success ? _green : _pink);
        if (r.success) _loadAdb();
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Courier')),
      backgroundColor: color.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF040A1A),
        foregroundColor: _cyan,
        title: const Text('DEVICE MATRIX', style: TextStyle(fontFamily: 'Orbitron', fontSize: 14, letterSpacing: 3, color: _cyan)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: _cyan), onPressed: _loadAll),
          IconButton(icon: const Icon(Icons.wifi_tethering, color: _cyan), onPressed: _connectWifi, tooltip: 'Connect via ADB WiFi'),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _cyan,
          labelColor: _cyan,
          unselectedLabelColor: Colors.white30,
          labelStyle: const TextStyle(fontFamily: 'Orbitron', fontSize: 10, letterSpacing: 1.5),
          tabs: const [Tab(text: 'ADB'), Tab(text: 'NETWORK'), Tab(text: 'SHELL')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAdbTab(),
          _buildNetworkTab(),
          _buildShellTab(),
        ],
      ),
    );
  }

  Widget _buildAdbTab() {
    if (_loadingAdb) return _loading('SCANNING ADB DEVICES...');
    if (_adbDevices.isEmpty) {
      return _empty('📱', 'NO ADB DEVICES', 'Enable Wireless Debugging on your Android device\n(Settings → Developer Options → Wireless Debugging)\nthen tap Connect via ADB WiFi above.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _adbDevices.length,
      itemBuilder: (ctx, i) {
        final d = _adbDevices[i];
        return _DeviceCard(
          icon: '📱',
          title: d.displayName,
          subtitle: d.serial,
          tag: d.status,
          tagColor: d.connected ? _green : _pink,
          isSelected: _selectedSerial == d.serial,
          onTap: () => setState(() => _selectedSerial = d.serial),
          actions: [
            _ActionButton(label: '🔓 UNLOCK', color: _green, onTap: d.connected ? () => _unlock(d.serial, d.displayName) : null),
            _ActionButton(label: '📸 SNAP', color: _yellow, onTap: d.connected ? () => _screenshot(d.serial) : null),
            _ActionButton(label: '🖥️ MIRROR', color: _purple, onTap: d.connected ? () => _mirror(d.serial) : null),
            _ActionButton(
              label: '💻 SHELL',
              color: _cyan,
              onTap: d.connected ? () {
                setState(() {
                  _selectedSerial = d.serial;
                  _shellLog.add(_ShellEntry(type: 'sys', text: '> Connected to ${d.displayName} (${d.serial})'));
                });
                _tabController.animateTo(2);
              } : null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildNetworkTab() {
    if (_loadingNet) return _loading('SCANNING NETWORK...');
    if (_networkDevices.isEmpty) {
      return _empty('⬡', 'NO NETWORK DEVICES', 'Run a network scan from Settings\nor tap the IoT Hub to discover devices.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _networkDevices.length,
      itemBuilder: (ctx, i) {
        final d = _networkDevices[i] as Map<String, dynamic>;
        final name = d['friendly_name'] ?? d['vendor'] ?? 'Unknown';
        final ip = d['ip'] ?? '';
        final type = d['device_type'] ?? 'unknown';
        final online = d['online'] == true;
        return _DeviceCard(
          icon: _typeIcon(type),
          title: name,
          subtitle: '$ip · $type',
          tag: online ? 'ONLINE' : 'OFFLINE',
          tagColor: online ? _green : Colors.white24,
          actions: [
            if (!(d['permitted'] as bool? ?? false))
              _ActionButton(label: '🔑 PERMIT', color: _cyan, onTap: () async {
                final mac = d['mac'] as String?;
                if (mac != null) {
                  await IotHubService().permitDevice(mac);
                  _loadNetwork();
                }
              }),
          ],
        );
      },
    );
  }

  Widget _buildShellTab() {
    if (_selectedSerial == null) {
      return _empty('💻', 'NO DEVICE SELECTED', 'Select an ADB device from the ADB tab to open a shell.');
    }
    return Column(children: [
      Container(
        color: const Color(0xFF040A1A),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.terminal, color: _cyan, size: 14),
          const SizedBox(width: 8),
          Text('ADB SHELL · $_selectedSerial', style: const TextStyle(color: _cyan, fontFamily: 'Courier', fontSize: 11, letterSpacing: 1)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() { _shellLog.clear(); }),
            child: const Text('CLEAR', style: TextStyle(color: Colors.white24, fontFamily: 'Orbitron', fontSize: 9, letterSpacing: 2)),
          ),
        ]),
      ),
      Expanded(
        child: Container(
          color: const Color(0xFF010614),
          padding: const EdgeInsets.all(10),
          child: ListView.builder(
            reverse: false,
            itemCount: _shellLog.length + (_shellRunning ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (_shellRunning && i == _shellLog.length) {
                return const Text('> EXECUTING...', style: TextStyle(color: Colors.white38, fontFamily: 'Courier', fontSize: 12));
              }
              final entry = _shellLog[i];
              final color = entry.type == 'input' ? _cyan : entry.type == 'error' ? _pink : Colors.white70;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(entry.text, style: TextStyle(color: color, fontFamily: 'Courier', fontSize: 12)),
              );
            },
          ),
        ),
      ),
      Container(
        color: const Color(0xFF040A1A),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: [
          const Text('\$', style: TextStyle(color: _cyan, fontFamily: 'Courier', fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _shellController,
              style: const TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 13),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'enter shell command...',
                hintStyle: TextStyle(color: Colors.white12, fontFamily: 'Courier'),
              ),
              onSubmitted: (_) => _runShell(_selectedSerial!),
              textInputAction: TextInputAction.send,
            ),
          ),
          GestureDetector(
            onTap: () => _runShell(_selectedSerial!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: 0.12),
                border: Border.all(color: _cyan.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('RUN', style: TextStyle(color: _cyan, fontFamily: 'Orbitron', fontSize: 10, letterSpacing: 2)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _loading(String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const CircularProgressIndicator(color: _cyan),
    const SizedBox(height: 16),
    Text(msg, style: const TextStyle(color: _cyan, fontFamily: 'Orbitron', fontSize: 11, letterSpacing: 3)),
  ]));

  Widget _empty(String icon, String title, String body) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(icon, style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: _cyan, fontFamily: 'Orbitron', fontSize: 13, letterSpacing: 3)),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
      ]),
    ),
  );

  String _typeIcon(String type) {
    switch (type) {
      case 'camera': return '📷';
      case 'android': return '📱';
      case 'computer': return '💻';
      case 'speaker': return '🔊';
      default: return '⬡';
    }
  }
}

class _DeviceCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final String tag;
  final Color tagColor;
  final bool isSelected;
  final VoidCallback? onTap;
  final List<Widget> actions;

  const _DeviceCard({
    required this.icon, required this.title, required this.subtitle,
    required this.tag, required this.tagColor, required this.actions,
    this.isSelected = false, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF06091C),
          border: Border.all(color: isSelected ? const Color(0xFF00F0FF) : const Color(0xFF1E2A48), width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected ? [const BoxShadow(color: Color(0x3300F0FF), blurRadius: 14)] : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Courier')),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(border: Border.all(color: tagColor.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(4), color: tagColor.withValues(alpha: 0.08)),
                child: Text(tag, style: TextStyle(color: tagColor, fontFamily: 'Orbitron', fontSize: 9, letterSpacing: 1)),
              ),
            ]),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionButton({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null ? 1.0 : 0.3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: TextStyle(color: color, fontFamily: 'Orbitron', fontSize: 10, letterSpacing: 1)),
        ),
      ),
    );
  }
}

class _ShellEntry {
  final String type; // sys, input, output, error
  final String text;
  _ShellEntry({required this.type, required this.text});
}
