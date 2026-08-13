// lib/screens/hub_select_screen.dart — MEKA Hub Profile Selector
// Premium cyberpunk screen for managing and switching between MEKA hubs.
// Each hub = one customer's home. Tap a card to activate. Swipe to delete.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/hub_profile_service.dart';
import '../services/iot_hub_service.dart';

class HubSelectScreen extends StatefulWidget {
  final bool isOnboarding; // true = first time, comes before HomeScreen
  const HubSelectScreen({super.key, this.isOnboarding = false});

  @override
  State<HubSelectScreen> createState() => _HubSelectScreenState();
}

class _HubSelectScreenState extends State<HubSelectScreen>
    with TickerProviderStateMixin {
  final _svc = HubProfileService();
  late AnimationController _bgCtrl;
  late AnimationController _pulseCtrl;
  bool _loading = true;

  static const _colors = [
    Color(0xFF00D4FF), // cyan
    Color(0xFF7C4DFF), // purple
    Color(0xFF00E676), // green
    Color(0xFFFF6D00), // orange
  ];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _load();
  }

  Future<void> _load() async {
    await _svc.load();
    await _svc.refreshOnlineStatus();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _activateHub(HubProfile p) async {
    await _svc.setActive(p.id);
    await IotHubService().saveHost(p.url);
    if (!mounted) return;
    if (widget.isOnboarding) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pop(context, p);
    }
  }

  Future<void> _deleteHub(HubProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF080C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF1744), width: 1),
        ),
        title: Text('REMOVE HUB',
            style: GoogleFonts.orbitron(color: const Color(0xFFFF1744), fontSize: 13, letterSpacing: 3)),
        content: Text('Remove "${p.name}" from your hub list?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('CANCEL', style: GoogleFonts.orbitron(color: Colors.white38, fontSize: 9, letterSpacing: 2))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('REMOVE', style: GoogleFonts.orbitron(color: const Color(0xFFFF1744), fontSize: 9, letterSpacing: 2))),
        ],
      ),
    );
    if (ok == true) {
      await _svc.deleteProfile(p.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF010409),
      body: Stack(
        children: [
          // ── Animated background ─────────────────────────────────────
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) => CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _BgPainter(_bgCtrl.value),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────
                _buildHeader(),
                const SizedBox(height: 8),

                // ── Hub Cards ─────────────────────────────────────────
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
                      : _svc.profiles.isEmpty
                          ? _buildEmptyState()
                          : _buildHubList(),
                ),
              ],
            ),
          ),

          // ── Add Hub FAB ──────────────────────────────────────────────
          Positioned(
            bottom: 32,
            right: 24,
            child: _AddHubFab(
              onAdd: (p) async {
                await _svc.addProfile(p);
                setState(() {});
              },
              svc: _svc,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          if (!widget.isOnboarding)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white38, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('M E K A', style: GoogleFonts.orbitron(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  color: const Color(0xFF00D4FF), letterSpacing: 6)),
              Text('SELECT YOUR HUB', style: GoogleFonts.orbitron(
                  fontSize: 9, color: Colors.white30, letterSpacing: 4)),
            ],
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF00D4FF).withOpacity(0.05 + _pulseCtrl.value * 0.05),
              ),
              child: Text('${_svc.profiles.length} HUB${_svc.profiles.length != 1 ? 'S' : ''}',
                  style: GoogleFonts.orbitron(
                      fontSize: 9, color: const Color(0xFF00D4FF), letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, color: Colors.white12, size: 80),
          const SizedBox(height: 24),
          Text('NO HUBS CONFIGURED',
              style: GoogleFonts.orbitron(color: Colors.white30, fontSize: 13, letterSpacing: 3)),
          const SizedBox(height: 12),
          Text('Tap the + button to add your MEKA Hub.',
              style: GoogleFonts.inter(color: Colors.white24, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildHubList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      itemCount: _svc.profiles.length,
      itemBuilder: (ctx, i) {
        final p = _svc.profiles[i];
        final isActive = p.id == _svc.activeProfile?.id;
        final color = _colors[p.colorIndex % _colors.length];
        return _HubCard(
          profile: p,
          isActive: isActive,
          accentColor: color,
          pulseCtrl: _pulseCtrl,
          onTap: () => _activateHub(p),
          onDelete: () => _deleteHub(p),
          onEdit: () async {
            final updated = await _showAddEditSheet(context, existing: p);
            if (updated != null) {
              await _svc.updateProfile(updated);
              setState(() {});
            }
          },
        );
      },
    );
  }

  Future<HubProfile?> _showAddEditSheet(BuildContext ctx, {HubProfile? existing}) {
    return showModalBottomSheet<HubProfile>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEditHubSheet(svc: _svc, existing: existing),
    );
  }
}

// ── Hub Card ──────────────────────────────────────────────────────────────
class _HubCard extends StatelessWidget {
  final HubProfile profile;
  final bool isActive;
  final Color accentColor;
  final AnimationController pulseCtrl;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _HubCard({
    required this.profile,
    required this.isActive,
    required this.accentColor,
    required this.pulseCtrl,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulseCtrl,
        builder: (_, child) {
          final glow = isActive ? (0.3 + pulseCtrl.value * 0.3) : 0.0;
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF080C1E),
              border: Border.all(
                color: accentColor.withOpacity(isActive ? 0.7 : 0.2),
                width: isActive ? 1.5 : 1,
              ),
              boxShadow: isActive
                  ? [BoxShadow(color: accentColor.withOpacity(glow), blurRadius: 20, spreadRadius: 1)]
                  : [],
            ),
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Hub icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withOpacity(0.1),
                  border: Border.all(color: accentColor.withOpacity(0.4)),
                ),
                child: Icon(Icons.router_rounded, color: accentColor, size: 26),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(profile.name,
                            style: GoogleFonts.orbitron(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: Colors.white, letterSpacing: 1)),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: accentColor.withOpacity(0.5)),
                            ),
                            child: Text('ACTIVE',
                                style: GoogleFonts.orbitron(
                                    fontSize: 7, color: accentColor, letterSpacing: 2)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(profile.url,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.white38)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: profile.isOnline
                                ? const Color(0xFF00E676)
                                : const Color(0xFFFF1744),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(profile.isOnline ? 'ONLINE' : 'OFFLINE',
                            style: GoogleFonts.orbitron(
                                fontSize: 8,
                                color: profile.isOnline
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFFFF1744),
                                letterSpacing: 2)),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              Column(
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: accentColor.withOpacity(0.6), size: 18),
                    onPressed: onEdit,
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFFF1744), size: 18),
                    onPressed: onDelete,
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add Hub FAB ───────────────────────────────────────────────────────────
class _AddHubFab extends StatelessWidget {
  final Future<void> Function(HubProfile) onAdd;
  final HubProfileService svc;
  const _AddHubFab({required this.onAdd, required this.svc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<HubProfile>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AddEditHubSheet(svc: svc),
        );
        if (result != null) await onAdd(result);
      },
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF00D4FF).withOpacity(0.15),
          border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.4), blurRadius: 16),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Color(0xFF00D4FF), size: 28),
      ),
    );
  }
}

// ── Add/Edit Hub Bottom Sheet ─────────────────────────────────────────────
class _AddEditHubSheet extends StatefulWidget {
  final HubProfileService svc;
  final HubProfile? existing;
  const _AddEditHubSheet({required this.svc, this.existing});

  @override
  State<_AddEditHubSheet> createState() => _AddEditHubSheetState();
}

class _AddEditHubSheetState extends State<_AddEditHubSheet> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl  = TextEditingController();
  int _colorIdx = 0;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  static const _colors = [
    Color(0xFF00D4FF), Color(0xFF7C4DFF), Color(0xFF00E676), Color(0xFFFF6D00),
  ];
  static const _colorNames = ['CYAN', 'VIOLET', 'GREEN', 'ORANGE'];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _urlCtrl.text  = widget.existing!.url;
      _colorIdx      = widget.existing!.colorIndex;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; });
    HapticFeedback.lightImpact();
    final result = await widget.svc.testHub(_urlCtrl.text.trim());
    setState(() {
      _testing = false;
      _testOk = result != null;
      if (result != null) {
        final v = result['version'] ?? '?';
        final devices = (result['stats'] as Map?)?.containsKey('total') == true
            ? result['stats']['total']
            : '?';
        _testResult = 'CONNECTED ✓  Hub v$v · $devices devices';
      } else {
        _testResult = 'CANNOT REACH HUB — check URL and network';
      }
    });
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty || _urlCtrl.text.trim().isEmpty) return;
    final p = HubProfile(
      id: widget.existing?.id ?? widget.svc.generateId(),
      name: _nameCtrl.text.trim(),
      url: _urlCtrl.text.trim(),
      colorIndex: _colorIdx,
    );
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final color = _colors[_colorIdx];
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF080C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 3,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(widget.existing != null ? 'EDIT HUB' : 'ADD NEW HUB',
                style: GoogleFonts.orbitron(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    color: color, letterSpacing: 4)),
            const SizedBox(height: 20),

            // Name field
            _CyberField(
              controller: _nameCtrl,
              label: 'HUB NAME',
              hint: 'e.g. My Home, Office Hub',
              color: color,
            ),
            const SizedBox(height: 12),

            // URL field
            _CyberField(
              controller: _urlCtrl,
              label: 'HUB URL / IP',
              hint: 'e.g. 192.168.1.100:5000',
              color: color,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),

            // Test connection
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _testing ? null : _testConnection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: color.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                        color: color.withOpacity(0.07),
                      ),
                      child: Center(
                        child: _testing
                            ? SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: color),
                              )
                            : Text('TEST CONNECTION',
                                style: GoogleFonts.orbitron(
                                    fontSize: 10, color: color, letterSpacing: 2)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(_testResult!,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _testOk ? const Color(0xFF00E676) : const Color(0xFFFF1744))),
            ],
            const SizedBox(height: 16),

            // Color selector
            Text('ACCENT COLOR',
                style: GoogleFonts.orbitron(fontSize: 8, color: Colors.white30, letterSpacing: 3)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(_colors.length, (i) {
                final c = _colors[i];
                final selected = _colorIdx == i;
                return GestureDetector(
                  onTap: () => setState(() => _colorIdx = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.withOpacity(0.2),
                      border: Border.all(
                          color: c, width: selected ? 2 : 0.5),
                    ),
                    child: selected
                        ? Icon(Icons.check_rounded, color: c, size: 18)
                        : null,
                  ),
                );
              }),
              ...[
                const SizedBox(width: 8),
                Text(_colorNames[_colorIdx],
                    style: GoogleFonts.orbitron(fontSize: 8, color: color, letterSpacing: 2)),
              ],
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.7), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.3), blurRadius: 20),
                    ],
                  ),
                  child: Center(
                    child: Text(widget.existing != null ? 'SAVE CHANGES' : 'ADD HUB',
                        style: GoogleFonts.orbitron(
                            fontSize: 13, color: color,
                            fontWeight: FontWeight.w700, letterSpacing: 3)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CyberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final Color color;
  final TextInputType? keyboardType;

  const _CyberField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.color,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.orbitron(fontSize: 8, color: Colors.white38, letterSpacing: 3)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.8), width: 1.5),
            ),
            filled: true,
            fillColor: color.withOpacity(0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ── Background Painter ─────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rand = Random(42);
    for (int i = 0; i < 80; i++) {
      final x = rand.nextDouble() * size.width;
      final baseY = rand.nextDouble() * size.height;
      final speed = 0.0003 + rand.nextDouble() * 0.0008;
      final y = (baseY + t * speed * size.height) % size.height;
      paint.color = const Color(0xFF00D4FF).withOpacity(0.05 + rand.nextDouble() * 0.12);
      canvas.drawCircle(Offset(x, y), 0.5 + rand.nextDouble() * 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t;
}
