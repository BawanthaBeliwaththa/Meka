import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/wake_word_service.dart';
import '../services/llm_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final WakeWordService _wakeWord = WakeWordService();
  final LlmService _llm = LlmService();

  // Animations
  late AnimationController _ringCtrl;
  late AnimationController _particleCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _waveCtrl;

  WakeWordState _state = WakeWordState.idle;
  String _transcript = '';
  final List<_Msg> _messages = [];
  final ScrollController _scroll = ScrollController();
  bool _panelOpen = false;

  // Particle system
  final List<_Particle> _particles = [];
  final _rand = Random();

  @override
  void initState() {
    super.initState();

    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))..repeat();
    _particleCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))..repeat();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    // Initialize particles
    for (int i = 0; i < 60; i++) {
      _particles.add(_Particle.random(_rand));
    }

    _wakeWord.start();

    _wakeWord.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s == WakeWordState.listening) {
        _waveCtrl.repeat();
      } else {
        _waveCtrl.stop();
        _waveCtrl.reset();
      }
    });

    _wakeWord.transcriptStream.listen((t) {
      if (mounted) setState(() => _transcript = t);
    });

    _wakeWord.responseStream.listen((r) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(text: r, isUser: false));
        _panelOpen = true;
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _wakeWord.stop();
    _ringCtrl.dispose();
    _particleCtrl.dispose();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ─── Colors per state ────────────────────────────────────────────────────
  Color get _primaryColor {
    switch (_state) {
      case WakeWordState.idle: return const Color(0xFF00D4FF);
      case WakeWordState.listening: return const Color(0xFF7C4DFF);
      case WakeWordState.processing: return const Color(0xFFFF6D00);
      case WakeWordState.speaking: return const Color(0xFF00E676);
      case WakeWordState.error: return const Color(0xFFFF1744);
    }
  }

  String get _statusText {
    switch (_state) {
      case WakeWordState.idle: return 'STANDBY — SAY "HEY MEKA"';
      case WakeWordState.listening: return 'LISTENING';
      case WakeWordState.processing: return 'PROCESSING';
      case WakeWordState.speaking: return 'RESPONDING';
      case WakeWordState.error: return 'ERROR — TAP TO RETRY';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF010409),
      body: Stack(
        children: [
          // ── Starfield / Particle Background ─────────────────────────
          AnimatedBuilder(
            animation: _particleCtrl,
            builder: (_, __) => CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _StarfieldPainter(_particles, _particleCtrl.value, _primaryColor),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotating outer rings
                      _buildRings(),
                      // Central orb
                      _buildCoreOrb(),
                    ],
                  ),
                ),
                // Status + transcript
                _buildStatusBar(),
                // Slide-up conversation panel
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                  height: _panelOpen ? 260 : 60,
                  child: _buildConversationPanel(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Siri-style overlay at bottom
          if (_state == WakeWordState.listening)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 110,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _waveCtrl,
                  builder: (_, __) => CustomPaint(
                    size: const Size(double.infinity, 110),
                    painter: _SiriWavePainter(_waveCtrl.value, _primaryColor),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Top Bar ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'M E K A',
                style: GoogleFonts.orbitron(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _primaryColor,
                  letterSpacing: 8,
                ),
              ),
              Text(
                'PERSONAL INTELLIGENCE SYSTEM',
                style: GoogleFonts.orbitron(
                  fontSize: 7,
                  color: Colors.white.withOpacity(0.35),
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const Spacer(),
          // State indicator dot
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryColor
                    .withOpacity(0.4 + _pulseCtrl.value * 0.6),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.tune_rounded,
                color: Colors.white.withOpacity(0.5), size: 22),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }

  // ─── Rotating Rings ───────────────────────────────────────────────────────
  Widget _buildRings() {
    return AnimatedBuilder(
      animation: _ringCtrl,
      builder: (_, __) => CustomPaint(
        size: const Size(320, 320),
        painter: _RingsPainter(_ringCtrl.value, _primaryColor),
      ),
    );
  }

  // ─── Core Orb ────────────────────────────────────────────────────────────
  Widget _buildCoreOrb() {
    return GestureDetector(
      onTap: () {
        if (_state == WakeWordState.idle || _state == WakeWordState.error) {
          _wakeWord.triggerManually();
        }
      },
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, child) {
          final scale = _state == WakeWordState.listening
              ? 1.0 + _pulseCtrl.value * 0.12
              : _state == WakeWordState.processing
                  ? 0.95 + _pulseCtrl.value * 0.07
                  : 1.0 + _pulseCtrl.value * 0.03;
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _primaryColor.withOpacity(0.9),
                _primaryColor.withOpacity(0.3),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.6),
                blurRadius: 50,
                spreadRadius: 10,
              ),
              BoxShadow(
                color: _primaryColor.withOpacity(0.3),
                blurRadius: 100,
                spreadRadius: 30,
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                _stateIcon,
                key: ValueKey(_state),
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData get _stateIcon {
    switch (_state) {
      case WakeWordState.idle: return Icons.graphic_eq;
      case WakeWordState.listening: return Icons.mic;
      case WakeWordState.processing: return Icons.memory;
      case WakeWordState.speaking: return Icons.surround_sound;
      case WakeWordState.error: return Icons.error_outline;
    }
  }

  // ─── Status Bar ──────────────────────────────────────────────────────────
  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _statusText,
              key: ValueKey(_statusText),
              style: GoogleFonts.orbitron(
                fontSize: 11,
                color: _primaryColor,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_transcript.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"$_transcript"',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withOpacity(0.40),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // ─── Conversation Panel ───────────────────────────────────────────────────
  Widget _buildConversationPanel() {
    return GestureDetector(
      onTap: () => setState(() => _panelOpen = !_panelOpen),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: _primaryColor.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _panelOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: Colors.white.withOpacity(0.3),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DIALOGUE LOG',
                    style: GoogleFonts.orbitron(
                      fontSize: 9,
                      color: Colors.white.withOpacity(0.3),
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
            if (_panelOpen)
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No dialogue yet.\nTap the orb or say "Hey Meka".',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.25),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _buildBubble(_messages[i]),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(_Msg msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: msg.isUser
              ? _primaryColor.withOpacity(0.15)
              : Colors.white.withOpacity(0.06),
          border: Border.all(
            color: msg.isUser
                ? _primaryColor.withOpacity(0.4)
                : Colors.white.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Text(
          msg.text,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white.withOpacity(0.85),
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────
class _Msg {
  final String text;
  final bool isUser;
  _Msg({required this.text, required this.isUser});
}

class _Particle {
  double x, y, speed, size, opacity;
  _Particle({required this.x, required this.y,
      required this.speed, required this.size, required this.opacity});

  factory _Particle.random(Random r) => _Particle(
        x: r.nextDouble(),
        y: r.nextDouble(),
        speed: 0.0005 + r.nextDouble() * 0.001,
        size: 0.5 + r.nextDouble() * 1.5,
        opacity: 0.1 + r.nextDouble() * 0.5,
      );
}

// ─── Painters ─────────────────────────────────────────────────────────────
class _StarfieldPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final Color accent;
  _StarfieldPainter(this.particles, this.t, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final y = ((p.y + t * p.speed) % 1.0);
      paint.color = accent.withOpacity(p.opacity * 0.5);
      canvas.drawCircle(
          Offset(p.x * size.width, y * size.height), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => old.t != t || old.accent != accent;
}

class _RingsPainter extends CustomPainter {
  final double t;
  final Color color;
  _RingsPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Rings at different speeds and radii
    final rings = [
      (120.0, 1.0, 0.15, 0.0),
      (150.0, -0.7, 0.10, pi / 6),
      (180.0, 0.5, 0.07, pi / 3),
      (100.0, -1.2, 0.20, pi / 4),
    ];

    for (final (radius, speed, opacity, offset) in rings) {
      paint.color = color.withOpacity(opacity);
      final angle = t * 2 * pi * speed + offset;

      // Draw dashed-looking arc segments
      for (int i = 0; i < 8; i++) {
        final startAngle = angle + i * pi / 4;
        final sweepAngle = pi / 6;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
      }
    }

    // Scanning line
    final scanPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color.withOpacity(0.25);
    final scanAngle = t * 2 * pi;
    canvas.drawLine(
      center,
      Offset(center.dx + cos(scanAngle) * 190,
             center.dy + sin(scanAngle) * 190),
      scanPaint,
    );

    // Gradient sweep (scan glow)
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [Colors.transparent, color.withOpacity(0.08), Colors.transparent],
        stops: const [0.0, 0.05, 0.15],
        transform: GradientRotation(scanAngle),
      ).createShader(Rect.fromCircle(center: center, radius: 190));
    canvas.drawCircle(center, 190, sweepPaint);
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}

class _SiriWavePainter extends CustomPainter {
  final double animationValue;
  final Color color;
  _SiriWavePainter(this.animationValue, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final centerY = size.height / 2;
    final width = size.width;

    final waves = [
      (0.6, 2.8, 0.5, const Color(0xFF00D4FF)),
      (0.45, 4.0, 0.8, const Color(0xFF7C4DFF)),
      (0.5, 2.0, -0.4, const Color(0xFFFF007F)),
      (0.3, 4.8, 1.3, const Color(0xFF00E676)),
    ];

    for (final (amp, freq, speed, wColor) in waves) {
      final path = Path();
      path.moveTo(0, centerY);

      final phase = animationValue * 2 * pi * speed;
      for (double x = 0; x <= width; x += 4) {
        final double envelope = sin((x / width) * pi);
        final double y = centerY +
            sin(x * (freq / width) * 2 * pi + phase) *
                (size.height * 0.40 * amp) *
                envelope;
        path.lineTo(x, y);
      }

      path.lineTo(width, size.height);
      path.lineTo(0, size.height);
      path.close();

      paint.color = wColor.withOpacity(0.25);
      paint.blendMode = BlendMode.screen;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SiriWavePainter old) => old.animationValue != animationValue;
}
