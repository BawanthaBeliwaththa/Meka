// lib/screens/home_screen.dart — MEKA Desktop Home (Windows & Linux)
// Cyberpunk command center with autonomous voice listening + mic button.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:math';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../services/wake_word_service.dart';
import 'settings_screen.dart';
import 'device_manager_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final LlmService _llm = LlmService();
  final TtsService _tts = TtsService();
  final WakeWordService _wakeWord = WakeWordService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late AnimationController _pulseCtrl;
  late AnimationController _micRingCtrl;
  late AnimationController _particleCtrl;

  final List<_Msg> _messages = [];
  bool _processing = false;
  String _status = 'MEKA READY';
  DateTime _now = DateTime.now();
  WakeWordState _voiceState = WakeWordState.idle;
  String _liveTranscript = '';
  bool _voiceAvailable = false;

  // Particle system for orb
  final List<_Particle> _particles = [];
  final _rand = Random();

  static const _cyan   = Color(0xFF00F0FF);
  static const _pink   = Color(0xFFFF0055);
  static const _purple = Color(0xFF7C3AED);
  static const _green  = Color(0xFF00FF66);
  static const _amber  = Color(0xFFFFB300);
  static const _bg     = Color(0xFF030712);
  static const _bgCard = Color(0xFF080C1E);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _micRingCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

    for (int i = 0; i < 30; i++) {
      _particles.add(_Particle.random(_rand));
    }

    _llm.loadSettings();

    // Clock update
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _messages.add(_Msg(
      text: 'M.E.K.A. DESKTOP v3.0 — ONLINE\nSay "Hey Meka" or type a command below.',
      isUser: false,
    ));

    // Start voice engine
    _initVoice();

    // Listen to voice state streams
    _wakeWord.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _voiceState = state;
        switch (state) {
          case WakeWordState.idle:      _status = 'MEKA READY — ALWAYS LISTENING'; break;
          case WakeWordState.listening: _status = 'LISTENING...'; break;
          case WakeWordState.processing:_status = 'PROCESSING...'; break;
          case WakeWordState.speaking:  _status = 'RESPONDING...'; break;
          case WakeWordState.error:     _status = 'VOICE ENGINE ERROR'; break;
        }
      });
    });

    _wakeWord.transcriptStream.listen((t) {
      if (!mounted) return;
      setState(() => _liveTranscript = t);
    });

    _wakeWord.responseStream.listen((r) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(text: r, isUser: false));
        _liveTranscript = '';
      });
      _scrollToBottom();
    });
  }

  Future<void> _initVoice() async {
    await _wakeWord.start();
    if (mounted) {
      setState(() => _voiceAvailable = _wakeWord.currentState != WakeWordState.error);
    }
  }

  @override
  void dispose() {
    _wakeWord.stop();
    _pulseCtrl.dispose();
    _micRingCtrl.dispose();
    _particleCtrl.dispose();
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
          _status = _voiceAvailable ? 'MEKA READY — ALWAYS LISTENING' : 'MEKA READY';
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

  Color get _micColor {
    switch (_voiceState) {
      case WakeWordState.idle:      return _cyan;
      case WakeWordState.listening: return _purple;
      case WakeWordState.processing:return _amber;
      case WakeWordState.speaking:  return _green;
      case WakeWordState.error:     return _pink;
    }
  }

  String _weekday(int d) => ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d - 1];
  String _month(int m)   => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: _bg,
      body: Row(children: [
        // ── Left Sidebar ───────────────────────────────────────────────────
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
            const SizedBox(height: 20),

            // ── Mic Orb / Voice Orb ─────────────────────────────────────
            GestureDetector(
              onTap: () => _wakeWord.triggerManually(),
              child: SizedBox(
                width: 110, height: 110,
                child: Stack(alignment: Alignment.center, children: [
                  // Particle field
                  AnimatedBuilder(
                    animation: _particleCtrl,
                    builder: (_, __) => CustomPaint(
                      size: const Size(110, 110),
                      painter: _OrbParticlePainter(_particles, _particleCtrl.value, _micColor),
                    ),
                  ),
                  // Rotating ring
                  if (_voiceState == WakeWordState.listening || _voiceState == WakeWordState.processing)
                    AnimatedBuilder(
                      animation: _micRingCtrl,
                      builder: (_, __) => CustomPaint(
                        size: const Size(110, 110),
                        painter: _MicRingPainter(_micRingCtrl.value, _micColor),
                      ),
                    ),
                  // Orb core
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, child) {
                      final scale = _voiceState == WakeWordState.listening
                          ? 1.0 + _pulseCtrl.value * 0.15
                          : 1.0 + _pulseCtrl.value * 0.04;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          _micColor.withOpacity(0.9),
                          _micColor.withOpacity(0.3),
                          Colors.transparent,
                        ], stops: const [0.0, 0.5, 1.0]),
                        boxShadow: [
                          BoxShadow(color: _micColor.withOpacity(0.6), blurRadius: 20, spreadRadius: 4),
                          BoxShadow(color: _micColor.withOpacity(0.2), blurRadius: 40, spreadRadius: 10),
                        ],
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            _voiceIcon,
                            key: ValueKey(_voiceState),
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 6),
            // Voice state label
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Text(
                _voiceAvailable ? _voiceStateLabel : 'VOICE UNAVAILABLE',
                style: GoogleFonts.orbitron(
                  fontSize: 7,
                  color: _micColor.withOpacity(0.5 + _pulseCtrl.value * 0.5),
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_liveTranscript.isNotEmpty && _liveTranscript.length < 40)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '"$_liveTranscript"',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            const Divider(color: Color(0xFF1E2A48), height: 24),

            // Clock
            Text('$h:$m', style: GoogleFonts.orbitron(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4)),
            Text(s, style: GoogleFonts.orbitron(fontSize: 12, color: _cyan, letterSpacing: 3)),
            const SizedBox(height: 4),
            Text(
              '${_weekday(_now.weekday)} ${_now.day} ${_month(_now.month)} ${_now.year}'.toUpperCase(),
              style: GoogleFonts.orbitron(fontSize: 7, color: Colors.white30, letterSpacing: 2),
            ),
            const Divider(color: Color(0xFF1E2A48), height: 24),

            // Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Row(children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _processing ? _pink : _micColor,
                      boxShadow: [BoxShadow(color: (_processing ? _pink : _micColor).withOpacity(0.5 + _pulseCtrl.value * 0.5), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(_status, style: GoogleFonts.orbitron(fontSize: 7, color: Colors.white54, letterSpacing: 1))),
                ]),
              ),
            ),

            const Divider(color: Color(0xFF1E2A48), height: 20),

            // Navigation
            _NavItem(icon: Icons.home_rounded, label: 'HOME', active: true, onTap: () {}),
            _NavItem(icon: Icons.devices_rounded, label: 'DEVICES', onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceManagerScreen()));
            }),
            _NavItem(icon: Icons.settings_rounded, label: 'SETTINGS', onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),

            const Spacer(),
            // System info card
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _bgCard,
                  border: Border.all(color: _purple.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SYSTEM STATUS', style: GoogleFonts.orbitron(fontSize: 7, color: _purple, letterSpacing: 2)),
                  const SizedBox(height: 6),
                  _SysRow('AI ENGINE', 'GEMINI', _green),
                  _SysRow('VOICE', _voiceAvailable ? 'ACTIVE' : 'OFF', _voiceAvailable ? _green : _pink),
                  _SysRow('PROTOCOL', 'REST/HTTP', _cyan),
                ]),
              ),
            ),
          ]),
        ),

        // ── Main content area ──────────────────────────────────────────────
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
                const SizedBox(width: 8),
                _HudTag(_voiceAvailable ? '🎤 VOICE ON' : '🎤 VOICE OFF', _voiceAvailable ? _green : _pink),
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

            // Live transcript bar (shows while voice is listening)
            if (_liveTranscript.isNotEmpty && _voiceState == WakeWordState.listening)
              Container(
                color: _purple.withOpacity(0.08),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(children: [
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Icon(Icons.mic, color: _purple.withOpacity(0.5 + _pulseCtrl.value * 0.5), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('"$_liveTranscript"',
                      style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic))),
                ]),
              ),

            // Input area
            Container(
              color: const Color(0xFF040A1A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Icon(Icons.chevron_right_rounded, color: _cyan, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Type a command or question...',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
                    ),
                    onSubmitted: _sendMessage,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                // Mic button — triggers voice command recording
                GestureDetector(
                  onTap: _processing ? null : () => _wakeWord.triggerManually(),
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_voiceState == WakeWordState.listening || _voiceState == WakeWordState.processing)
                            ? _micColor.withOpacity(0.25)
                            : _micColor.withOpacity(0.08),
                        border: Border.all(
                          color: _micColor.withOpacity(_voiceState != WakeWordState.idle
                              ? 0.5 + _pulseCtrl.value * 0.5
                              : 0.4),
                          width: 1.5,
                        ),
                        boxShadow: _voiceState != WakeWordState.idle
                            ? [BoxShadow(color: _micColor.withOpacity(0.4), blurRadius: 12)]
                            : null,
                      ),
                      child: Icon(_voiceIcon, color: _micColor, size: 18),
                    ),
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

  IconData get _voiceIcon {
    switch (_voiceState) {
      case WakeWordState.idle:      return Icons.graphic_eq_rounded;
      case WakeWordState.listening: return Icons.mic_rounded;
      case WakeWordState.processing:return Icons.memory_rounded;
      case WakeWordState.speaking:  return Icons.volume_up_rounded;
      case WakeWordState.error:     return Icons.mic_off_rounded;
    }
  }

  String get _voiceStateLabel {
    switch (_voiceState) {
      case WakeWordState.idle:      return 'SAY "HEY MEKA"';
      case WakeWordState.listening: return 'LISTENING...';
      case WakeWordState.processing:return 'PROCESSING...';
      case WakeWordState.speaking:  return 'RESPONDING...';
      case WakeWordState.error:     return 'VOICE ERROR';
    }
  }
}

// ── Particle System ─────────────────────────────────────────────────────────
class _Particle {
  double x, y, speed, size, opacity;
  _Particle({required this.x, required this.y, required this.speed, required this.size, required this.opacity});
  factory _Particle.random(Random r) => _Particle(
    x: r.nextDouble(), y: r.nextDouble(),
    speed: 0.001 + r.nextDouble() * 0.002,
    size: 0.5 + r.nextDouble() * 1.5,
    opacity: 0.1 + r.nextDouble() * 0.4,
  );
}

class _OrbParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final Color color;
  _OrbParticlePainter(this.particles, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();
    for (final p in particles) {
      final angle = (p.x * 2 * pi) + t * 2 * pi * p.speed * 100;
      final radius = 38 + p.y * 16;
      final px = center.dx + cos(angle) * radius;
      final py = center.dy + sin(angle) * radius;
      paint.color = color.withOpacity(p.opacity * 0.6);
      canvas.drawCircle(Offset(px, py), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbParticlePainter old) => old.t != t || old.color != color;
}

class _MicRingPainter extends CustomPainter {
  final double t;
  final Color color;
  _MicRingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final rings = [(42.0, 1.0, 0.20), (50.0, -0.6, 0.12), (54.0, 0.4, 0.08)];
    for (final (r, speed, opacity) in rings) {
      paint.color = color.withOpacity(opacity);
      final angle = t * 2 * pi * speed;
      for (int i = 0; i < 6; i++) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          angle + i * pi / 3, pi / 5, false, paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MicRingPainter old) => old.t != t || old.color != color;
}

// ── Supporting Widgets ───────────────────────────────────────────────────────
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
        color: active ? const Color(0xFF00F0FF).withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: active ? Border.all(color: const Color(0xFF00F0FF).withOpacity(0.25)) : null,
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
    decoration: BoxDecoration(
      border: Border.all(color: color.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(4),
      color: color.withOpacity(0.07),
    ),
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
      Text('$label  ', style: const TextStyle(color: Colors.white24, fontSize: 8, letterSpacing: 1)),
      Expanded(child: Text(value, style: TextStyle(color: color, fontSize: 8, letterSpacing: 1), textAlign: TextAlign.right)),
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
          color: color.withOpacity(0.12),
          border: Border.all(color: color.withOpacity(0.5)),
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
      AnimatedBuilder(animation: _ctrl, builder: (_, __) => Opacity(
        opacity: _ctrl.value,
        child: Text('⠿ PROCESSING NEURAL QUERY...', style: TextStyle(color: widget.color, fontFamily: 'Orbitron', fontSize: 9, letterSpacing: 2)),
      )),
    ]),
  );
}

class _MessageBubble extends StatelessWidget {
  final _Msg msg;
  const _MessageBubble({required this.msg});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12, left: msg.isUser ? 60 : 0, right: msg.isUser ? 0 : 60),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: msg.isUser ? const Color(0xFF0D1B35) : const Color(0xFF060C1E),
        border: Border.all(color: msg.isError
            ? const Color(0xFFFF0055)
            : msg.isUser ? const Color(0xFF00F0FF).withOpacity(0.3) : const Color(0xFF7C3AED).withOpacity(0.3)),
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
