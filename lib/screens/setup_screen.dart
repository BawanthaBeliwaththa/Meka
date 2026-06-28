import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/llm_service.dart';
import '../services/voice_auth_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _keyController = TextEditingController();
  bool _keyVisible = false;
  bool _loading = false;
  int _page = 0; // 0=welcome, 1=api key, 2=voice enroll

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Voice enrollment state
  final VoiceAuthService _voiceAuth = VoiceAuthService();
  int _enrollStep = 0; // 0=ready, 1=recording, 2=done
  final List<int> _voiceDurations = [];
  bool _isRecording = false;
  String _enrollStatus = 'Press the button and say "Hey Meka" clearly';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();
  }

  void _nextPage() {
    _animController.reverse().then((_) {
      setState(() => _page++);
      _animController.forward();
    });
  }

  Future<void> _finish() async {
    setState(() => _loading = true);
    await LlmService().saveSettings(
      apiKey: _keyController.text.trim(),
      userName: _nameController.text.trim().isEmpty
          ? 'Boss'
          : _nameController.text.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_done', true);
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  Future<void> _recordVoiceSample() async {
    if (_isRecording) return;
    setState(() {
      _isRecording = true;
      _enrollStep = 1;
      _enrollStatus =
          'Recording... say "Hey Meka" clearly (${_voiceDurations.length + 1}/${_voiceAuth.requiredSamples})';
    });

    final duration = await _voiceAuth.recordSample(_voiceDurations.length);
    _voiceDurations.add(duration);

    if (_voiceDurations.length >= _voiceAuth.requiredSamples) {
      await _voiceAuth.completeEnrollment(_voiceDurations);
      setState(() {
        _isRecording = false;
        _enrollStep = 2;
        _enrollStatus = '✓ Voice enrolled successfully!';
      });
    } else {
      setState(() {
        _isRecording = false;
        _enrollStep = 0;
        _enrollStatus =
            'Good! ${_voiceAuth.requiredSamples - _voiceDurations.length} more sample(s) needed. Press again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.5,
            colors: [Color(0xFF1A1040), Color(0xFF0A0A0F)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _page == 0
                  ? _buildWelcome()
                  : _page == 1
                      ? _buildApiSetup()
                      : _buildVoiceEnroll(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Center(
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.5),
                  blurRadius: 50,
                  spreadRadius: 15,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 52),
          ),
        ),
        const SizedBox(height: 48),
        Text(
          'Hello,\nI\'m Meka.',
          style: GoogleFonts.orbitron(
            fontSize: 38,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Your personal AI assistant.\nAlways listening. Always ready.\nOnly for you.',
          style: GoogleFonts.inter(
              fontSize: 16,
              color: Colors.white.withOpacity(0.54),
              height: 1.7),
        ),
        const SizedBox(height: 48),
        Text('What should I call you?',
            style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withOpacity(0.38),
                letterSpacing: 1)),
        const SizedBox(height: 12),
        _inputField(
          controller: _nameController,
          hint: 'Your name...',
          icon: Icons.person_outline,
          autofocus: true,
        ),
        const Spacer(),
        _gradientButton('Continue →', _nextPage),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildApiSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        const Icon(Icons.psychology_outlined, color: Color(0xFF6C63FF), size: 52),
        const SizedBox(height: 28),
        Text(
          'Connect\nMeka\'s Brain.',
          style: GoogleFonts.orbitron(
              fontSize: 32,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              height: 1.3),
        ),
        const SizedBox(height: 16),
        Text(
          'Meka uses Google Gemini AI. Get your FREE key at:',
          style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withOpacity(0.54),
              height: 1.6),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'aistudio.google.com',
            style: GoogleFonts.robotoMono(
                fontSize: 13, color: const Color(0xFF00D4FF)),
          ),
        ),
        const SizedBox(height: 24),
        _inputField(
          controller: _keyController,
          hint: 'Paste your Gemini API key...',
          icon: Icons.vpn_key_outlined,
          obscure: !_keyVisible,
          suffix: IconButton(
            icon: Icon(
                _keyVisible ? Icons.visibility_off : Icons.visibility,
                color: Colors.white.withOpacity(0.38),
                size: 20),
            onPressed: () => setState(() => _keyVisible = !_keyVisible),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'No key? You can add it later in Settings.',
          style: GoogleFonts.inter(
              fontSize: 12, color: Colors.white.withOpacity(0.30)),
        ),
        const Spacer(),
        _gradientButton('Next →', _nextPage),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _nextPage,
            child: Text('Skip for now',
                style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.30), fontSize: 13)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildVoiceEnroll() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Icon(
          _enrollStep == 2 ? Icons.verified_user : Icons.record_voice_over,
          color: _enrollStep == 2
              ? const Color(0xFF00E676)
              : const Color(0xFF6C63FF),
          size: 52,
        ),
        const SizedBox(height: 28),
        Text(
          'Teach Meka\nYour Voice.',
          style: GoogleFonts.orbitron(
              fontSize: 32,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              height: 1.3),
        ),
        const SizedBox(height: 16),
        Text(
          'Record ${_voiceAuth.requiredSamples} samples of "Hey Meka" so Meka only wakes up for YOU.',
          style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withOpacity(0.54),
              height: 1.6),
        ),
        const SizedBox(height: 36),

        // Progress dots
        Row(
          children: List.generate(
            _voiceAuth.requiredSamples,
            (i) => Container(
              margin: const EdgeInsets.only(right: 10),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _voiceDurations.length
                    ? const Color(0xFF00E676)
                    : i == _voiceDurations.length && _isRecording
                        ? const Color(0xFF6C63FF)
                        : Colors.white.withOpacity(0.1),
                border: Border.all(
                  color: i == _voiceDurations.length
                      ? const Color(0xFF6C63FF)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: i < _voiceDurations.length
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : _isRecording && i == _voiceDurations.length
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text('${i + 1}',
                            style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.54),
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // Status text
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _enrollStep == 2
                ? const Color(0xFF00E676).withOpacity(0.1)
                : const Color(0xFF6C63FF).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _enrollStep == 2
                  ? const Color(0xFF00E676).withOpacity(0.3)
                  : const Color(0xFF6C63FF).withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isRecording ? Icons.mic : Icons.info_outline,
                color: _isRecording
                    ? Colors.red
                    : const Color(0xFF6C63FF),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _enrollStatus,
                  style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 13,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        if (_enrollStep < 2)
          GestureDetector(
            onTap: _isRecording ? null : _recordVoiceSample,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: _isRecording
                      ? [Colors.red.shade700, Colors.red.shade400]
                      : [const Color(0xFF6C63FF), const Color(0xFF00D4FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? Colors.red : const Color(0xFF6C63FF))
                        .withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        _isRecording ? Icons.stop_circle : Icons.mic,
                        color: Colors.white,
                        size: 26),
                    const SizedBox(width: 10),
                    Text(
                      _isRecording
                          ? 'Recording...'
                          : 'Tap & Say "Hey Meka"',
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (_enrollStep == 2) ...[
          _gradientButton('Start Using Meka!', _loading ? null : _finish,
              color: const Color(0xFF00E676)),
        ],

        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _finish,
            child: Text(
              _enrollStep == 2 ? '' : 'Skip voice enrollment',
              style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.30), fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool autofocus = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        color: Colors.white.withOpacity(0.05),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              GoogleFonts.inter(color: Colors.white.withOpacity(0.24)),
          border: InputBorder.none,
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.38)),
          suffixIcon: suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _gradientButton(String label, VoidCallback? onTap,
      {Color color = const Color(0xFF6C63FF)}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: onTap != null
              ? LinearGradient(
                  colors: [color, color.withOpacity(0.6)],
                )
              : null,
          color: onTap == null ? Colors.white.withOpacity(0.12) : null,
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    _animController.dispose();
    super.dispose();
  }
}
