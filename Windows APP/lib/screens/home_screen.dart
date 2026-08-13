// lib/screens/home_screen.dart — MEKA Desktop Home
// Cyberpunk command center for Windows/Linux desktop
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../services/adb_service.dart';
import 'settings_screen.dart';
import 'device_manager_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final LlmService _llm = LlmService();
  final TtsService _tts = TtsService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late AnimationController _pulseCtrl;
  final List<_Msg> _messages = [];
  bool _processing = false;
  String _status = 'MEKA READY';
  DateTime _now = DateTime.now();

  static const _cyan = Color(0xFF00F0FF);
  static const _pink = Color(0xFFFF0055);
  static const _purple = Color(0xFF7C3AED);
  static const _green = Color(0xFF00FF66);
  static const _bg = Color(0xFF030712);
  static const _bgCard = Color(0xFF080C1E);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _llm.loadSettings();
    // Clock update
    Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _now = DateTime.now()); });
    _messages.add(_Msg(
      text: 'M.E.K.A. SUPER EDITION — DESKTOP v3.0\nI\'m online. How can I assist you?',
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _inputCtrl.dispose();
    _scroll.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _processing) return;
    _inputCtrl.clear();
    setState(() {
      _messages.add(_Msg(text: text, isUser: true));
      _processing = true;
      _status = 'PROCESSING...';
    });
    _scrollToBottom();
    try {
      final response = await _llm.chat(text);
      if (mounted) {
        setState(() {
          _messages.add(_Msg(text: response, isUser: false));
          _processing = false;
          _status = 'MEKA READY';
        });
        _tts.speak(response);
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_Msg(text: 'Neural core error: $e', isUser: false, isError: true));
          _processing = false;
          _status = 'ERROR — CHECK SETTINGS';
        });
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: _bg,
      body: Row(children: [
        // ── Left Sidebar ─────────────────────────────────────────────────
        Container(
          width: 220,
          color: const Color(0xFF040A1A),
          child: Column(children: [
            const SizedBox(height: 24),
            // Logo + branding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                Text('M.E.K.A.', style: GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.w900, color: _cyan, letterSpacing: 4)),
                const SizedBox(height: 4),
                Text('SUPER DESKTOP', style: GoogleFonts.orbitron(fontSize: 7, color: Colors.white24, letterSpacing: 3)),
                const SizedBox(height: 4),
                Text('v3.0', style: GoogleFonts.orbitron(fontSize: 8, color: _purple, letterSpacing: 2)),
              ]),
            ),
            const SizedBox(height: 24),
            // Clock
            Text('$h:$m', style: GoogleFonts.orbitron(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4)),
            Text(s, style: GoogleFonts.orbitron(fontSize: 14, color: _cyan, letterSpacing: 3)),
            const SizedBox(height: 8),
            Text(
              '${_weekday(_now.weekday)} ${_now.day} ${_month(_now.month)} ${_now.year}'.toUpperCase(),
              style: GoogleFonts.orbitron(fontSize: 8, color: Colors.white30, letterSpacing: 2),
            ),
            const Divider(color: Color(0xFF1E2A48), height: 32),
            // Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _processing ? _pink : _cyan,
                      boxShadow: [BoxShadow(color: (_processing ? _pink : _cyan).withValues(alpha: 0.5), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status, style: GoogleFonts.orbitron(fontSize: 8, color: Colors.white54, letterSpacing: 1))),
                ]),
              ),
            ),
            const Divider(color: Color(0xFF1E2A48), height: 32),
            // Navigation items
            _NavItem(icon: Icons.home_rounded, label: 'HOME', active: true, onTap: () {}),
            _NavItem(icon: Icons.devices_rounded, label: 'DEVICES', onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceManagerScreen()));
            }),
            _NavItem(icon: Icons.settings_rounded, label: 'SETTINGS', onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
            const Spacer(),
            // System info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _bgCard,
                  border: Border.all(color: _purple.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SYSTEM STATUS', style: GoogleFonts.orbitron(fontSize: 7, color: _purple, letterSpacing: 2)),
                  const SizedBox(height: 6),
                  _SysRow('AI ENGINE', 'GEMINI', _green),
                  _SysRow('PROTOCOL', 'REST/HTTP', _cyan),
                  _SysRow('PLATFORM', 'DESKTOP', _cyan),
                ]),
              ),
            ),
          ]),
        ),
        // ── Main content ──────────────────────────────────────────────────
        Expanded(
          child: Column(children: [
            // Top bar
            Container(
              height: 52,
              color: const Color(0xFF040A1A),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text('NEURAL INTERFACE', style: GoogleFonts.orbitron(fontSize: 11, letterSpacing: 3, color: Colors.white54)),
                const Spacer(),
                _HudTag('⬡ IoT HUB', _cyan),
                const SizedBox(width: 8),
                _HudTag('⊡ AI CORE', _green),
              ]),
            ),
            const Divider(height: 1, color: Color(0xFF0A1628)),
            // Chat messages
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length + (_processing ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (_processing && i == _messages.length) {
                    return _TypingIndicator(color: _cyan);
                  }
                  return _MessageBubble(msg: _messages[i]);
                },
              ),
            ),
            // Input area
            Container(
              color: const Color(0xFF040A1A),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF00F0FF), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    style: const TextStyle(color: Colors.white, fontFamily: 'CourierNew', fontSize: 14),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Type a command or question...',
                      hintStyle: TextStyle(color: Colors.white24, fontFamily: 'Rajdhani', fontSize: 14),
                    ),
                    onSubmitted: _sendMessage,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                _CyberpunkButton(
                  label: _processing ? '...' : 'SEND',
                  color: _cyan,
                  onTap: () => _sendMessage(_inputCtrl.text),
                  disabled: _processing,
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  String _weekday(int d) => ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d - 1];
  String _month(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

// ── Supporting Widgets ─────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF00F0FF).withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: active ? Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.25)) : null,
      ),
      child: Row(children: [
        Icon(icon, color: active ? const Color(0xFF00F0FF) : Colors.white38, size: 18),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.orbitron(fontSize: 9, color: active ? const Color(0xFF00F0FF) : Colors.white38, letterSpacing: 2)),
      ]),
    ),
  );
}

class _HudTag extends StatelessWidget {
  final String label;
  final Color color;
  const _HudTag(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(4), color: color.withValues(alpha: 0.07)),
    child: Text(label, style: TextStyle(color: color, fontFamily: 'Orbitron', fontSize: 8, letterSpacing: 1)),
  );
}

class _SysRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SysRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$label  ', style: TextStyle(color: Colors.white24, fontSize: 8, fontFamily: 'Orbitron', letterSpacing: 1)),
      Expanded(child: Text(value, style: TextStyle(color: color, fontSize: 8, fontFamily: 'Orbitron', letterSpacing: 1), textAlign: TextAlign.right)),
    ]),
  );
}

class _CyberpunkButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;
  const _CyberpunkButton({required this.label, required this.color, required this.onTap, this.disabled = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: disabled ? null : onTap,
    child: Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(color: color, fontFamily: 'Orbitron', fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
      ),
    ),
  );
}

class _TypingIndicator extends StatefulWidget {
  final Color color;
  const _TypingIndicator({required this.color});
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}
class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      AnimatedBuilder(animation: _ctrl, builder: (_, __) => Opacity(opacity: _ctrl.value, child: Text('⠿ PROCESSING NEURAL QUERY...', style: TextStyle(color: widget.color, fontFamily: 'Orbitron', fontSize: 9, letterSpacing: 2)))),
    ]),
  );
}

class _MessageBubble extends StatelessWidget {
  final _Msg msg;
  const _MessageBubble({required this.msg});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: 12,
      left: msg.isUser ? 60 : 0,
      right: msg.isUser ? 0 : 60,
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: msg.isUser ? const Color(0xFF0D1B35) : const Color(0xFF060C1E),
        border: Border.all(color: msg.isError ? const Color(0xFFFF0055) : msg.isUser ? const Color(0xFF00F0FF).withValues(alpha: 0.3) : const Color(0xFF7C3AED).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(msg.isUser ? 'YOU' : 'M.E.K.A.',
            style: TextStyle(color: msg.isUser ? const Color(0xFF00F0FF) : const Color(0xFF7C3AED), fontFamily: 'Orbitron', fontSize: 8, letterSpacing: 2)),
        const SizedBox(height: 6),
        Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
      ]),
    ),
  );
}

class _Msg {
  final String text;
  final bool isUser;
  final bool isError;
  _Msg({required this.text, required this.isUser, this.isError = false});
}
