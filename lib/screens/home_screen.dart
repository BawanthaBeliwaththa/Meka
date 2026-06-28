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

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final WakeWordService _wakeWord = WakeWordService();
  final LlmService _llm = LlmService();

  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _orbController;

  WakeWordState _state = WakeWordState.idle;
  String _transcript = '';
  String _lastResponse = '';
  final List<_ChatBubble> _bubbles = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _wakeWord.start();

    _wakeWord.stateStream.listen((state) {
      if (mounted) setState(() => _state = state);
      if (state == WakeWordState.listening) {
        _waveController.repeat(reverse: true);
      } else {
        _waveController.stop();
      }
    });

    _wakeWord.transcriptStream.listen((text) {
      if (mounted) setState(() => _transcript = text);
    });

    _wakeWord.responseStream.listen((text) {
      if (mounted) {
        setState(() {
          _lastResponse = text;
          _bubbles.add(_ChatBubble(text: text, isUser: false));
        });
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _wakeWord.stop();
    _pulseController.dispose();
    _waveController.dispose();
    _orbController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Color get _stateColor {
    switch (_state) {
      case WakeWordState.idle:
        return const Color(0xFF6C63FF);
      case WakeWordState.listening:
        return const Color(0xFF00D4FF);
      case WakeWordState.processing:
        return const Color(0xFFFFD600);
      case WakeWordState.speaking:
        return const Color(0xFF00E676);
      case WakeWordState.error:
        return const Color(0xFFFF5252);
    }
  }

  String get _stateLabel {
    switch (_state) {
      case WakeWordState.idle:
        return 'Say "Hey Meka"';
      case WakeWordState.listening:
        return 'Listening...';
      case WakeWordState.processing:
        return 'Thinking...';
      case WakeWordState.speaking:
        return 'Speaking...';
      case WakeWordState.error:
        return 'Error — Tap to retry';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // Animated gradient background
          _buildBackground(),

          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildOrbSection(),
                _buildStatusLabel(),
                const SizedBox(height: 8),
                _buildTranscript(),
                Expanded(child: _buildChatHistory()),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return AnimatedBuilder(
      animation: _orbController,
      builder: (_, __) {
        return CustomPaint(
          size: Size.infinite,
          painter: _BackgroundPainter(_orbController.value, _stateColor),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'MEKA',
            style: GoogleFonts.orbitron(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 6,
            ),
          ),
          Row(
            children: [
              // Clear history
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white.withOpacity(0.54)),
                onPressed: () {
                  setState(() {
                    _bubbles.clear();
                    _llm.clearHistory();
                  });
                },
              ),
              // Settings
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white.withOpacity(0.54)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrbSection() {
    return GestureDetector(
      onTap: () {
        if (_state == WakeWordState.idle || _state == WakeWordState.error) {
          _wakeWord.triggerManually();
        }
      },
      child: SizedBox(
        height: 200,
        child: Center(
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (_, child) {
              final scale = _state == WakeWordState.idle
                  ? 1.0 + _pulseController.value * 0.05
                  : _state == WakeWordState.listening
                      ? 1.0 + _pulseController.value * 0.15
                      : 1.0;
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _stateColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                ),
                // Middle ring
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _stateColor.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                ),
                // Core orb
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _stateColor.withOpacity(0.9),
                        _stateColor.withOpacity(0.4),
                        _stateColor.withOpacity(0.0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _stateColor.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    _state == WakeWordState.listening
                        ? Icons.mic
                        : _state == WakeWordState.processing
                            ? Icons.psychology_outlined
                            : _state == WakeWordState.speaking
                                ? Icons.volume_up_rounded
                                : Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusLabel() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        _stateLabel,
        key: ValueKey(_stateLabel),
        style: GoogleFonts.inter(
          fontSize: 14,
          color: _stateColor,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTranscript() {
    if (_transcript.isEmpty) return const SizedBox(height: 20);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Text(
        '"$_transcript"',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: Colors.white.withOpacity(0.38),
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildChatHistory() {
    if (_bubbles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.waving_hand, color: Colors.white.withOpacity(0.12), size: 48),
            const SizedBox(height: 12),
            Text(
              'Tap the orb or say\n"Hey Meka" to start',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withOpacity(0.24),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _bubbles.length,
      itemBuilder: (_, i) => _buildBubble(_bubbles[i]),
    );
  }

  Widget _buildBubble(_ChatBubble bubble) {
    return Align(
      alignment: bubble.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: bubble.isUser
              ? const Color(0xFF6C63FF).withOpacity(0.3)
              : Colors.white.withOpacity(0.07),
          border: Border.all(
            color: bubble.isUser
                ? const Color(0xFF6C63FF).withOpacity(0.4)
                : Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Text(
          bubble.text,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white.withOpacity(0.87),
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Manual mic button
          GestureDetector(
            onTap: () => _wakeWord.triggerManually(),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    _stateColor,
                    _stateColor.withOpacity(0.5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _stateColor.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble {
  final String text;
  final bool isUser;
  _ChatBubble({required this.text, required this.isUser});
}

class _BackgroundPainter extends CustomPainter {
  final double t;
  final Color color;
  _BackgroundPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw subtle moving blobs
    for (int i = 0; i < 3; i++) {
      final angle = (t + i / 3) * 2 * pi;
      final x = size.width / 2 + cos(angle) * size.width * 0.25;
      final y = size.height / 2 + sin(angle) * size.height * 0.2;
      paint.color = color.withOpacity(0.03 - i * 0.008);
      canvas.drawCircle(Offset(x, y), 200 - i * 30, paint);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.t != t || old.color != color;
}
