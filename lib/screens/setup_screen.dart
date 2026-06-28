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
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _keyVisible = false;
  bool _loading = false;
  int _page = 0;

  late AnimationController _anim;
  late Animation<double> _fade;

  final VoiceAuthService _voice = VoiceAuthService();
  final List<double> _pitches = [];
  bool _isRecording = false;
  String _voiceStatus = 'Press the button and say "Hey Meka" clearly';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _anim.forward();
  }

  void _next() {
    _anim.reverse().then((_) {
      setState(() => _page++);
      _anim.forward();
    });
  }

  Future<void> _finish() async {
    setState(() => _loading = true);
    await LlmService().saveSettings(
      apiKey: _keyCtrl.text.trim(),
      userName: _nameCtrl.text.trim().isEmpty ? 'Sir' : _nameCtrl.text.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_done', true);
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  Future<void> _record() async {
    if (_isRecording) return;
    setState(() {
      _isRecording = true;
      _voiceStatus = 'Listening... Speak "Hey Meka" now.';
    });

    try {
      final sampleIndex = _pitches.length;
      await _voice.startRecording(sampleIndex);
      
      // Let the user speak for 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      
      final pitch = await _voice.stopAndAnalyze(sampleIndex);

      if (pitch <= 50.0 || pitch >= 350.0) {
        setState(() {
          _isRecording = false;
          _voiceStatus = 'No voice detected or too much noise. Please try again.';
        });
        return;
      }

      _pitches.add(pitch);

      if (_pitches.length >= _voice.requiredSamples) {
        await _voice.completeEnrollment(_pitches);
        setState(() {
          _isRecording = false;
          _voiceStatus = 'Voice calibration complete. Pitch analyzed at ${pitch.toStringAsFixed(0)} Hz.';
        });
      } else {
        setState(() {
          _isRecording = false;
          _voiceStatus = 'Sample ${_pitches.length} recorded (${pitch.toStringAsFixed(0)} Hz). ${_voice.requiredSamples - _pitches.length} more needed.';
        });
      }
    } catch (_) {
      setState(() {
        _isRecording = false;
        _voiceStatus = 'An error occurred. Please try again.';
      });
    }
  }

  bool get _voiceDone => _pitches.length >= _voice.requiredSamples;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF010409),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.2,
            colors: [Color(0xFF071520), Color(0xFF010409)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _page == 0
                  ? _welcome()
                  : _page == 1
                      ? _apiPage()
                      : _voicePage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                        colors: [Color(0xFF00D4FF), Color(0xFF7C4DFF)]),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF00D4FF).withOpacity(0.5),
                          blurRadius: 60,
                          spreadRadius: 10)
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 44),
                ),
                const SizedBox(height: 32),
                Text('M E K A',
                    style: GoogleFonts.orbitron(
                        fontSize: 32,
                        color: const Color(0xFF00D4FF),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10)),
                const SizedBox(height: 8),
                Text('PERSONAL INTELLIGENCE SYSTEM',
                    style: GoogleFonts.orbitron(
                        fontSize: 9,
                        color: Colors.white.withOpacity(0.35),
                        letterSpacing: 4)),
              ],
            ),
          ),
          const SizedBox(height: 48),
          Text('IDENTIFICATION',
              style: GoogleFonts.orbitron(
                  fontSize: 10,
                  color: const Color(0xFF00D4FF),
                  letterSpacing: 4)),
          const SizedBox(height: 12),
          Text('What shall I call you?',
              style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.50), fontSize: 14)),
          const SizedBox(height: 14),
          _field(ctrl: _nameCtrl, hint: 'Your name...', icon: Icons.person_outline),
          const Spacer(),
          _btn('INITIALIZE', _next),
          const SizedBox(height: 20),
        ],
      );

  Widget _apiPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          const Icon(Icons.psychology_outlined,
              color: Color(0xFF00D4FF), size: 44),
          const SizedBox(height: 24),
          Text('NEURAL\nCORE LINK',
              style: GoogleFonts.orbitron(
                  fontSize: 30,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  height: 1.3)),
          const SizedBox(height: 14),
          Text(
              'Connect Gemini AI as Meka\'s brain.\nGet your free key at:',
              style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.50), fontSize: 14, height: 1.6)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF00D4FF).withOpacity(0.2)),
            ),
            child: Text('aistudio.google.com',
                style: GoogleFonts.robotoMono(
                    fontSize: 13, color: const Color(0xFF00D4FF))),
          ),
          const SizedBox(height: 22),
          _field(
            ctrl: _keyCtrl,
            hint: 'Paste API key...',
            icon: Icons.vpn_key_outlined,
            obscure: !_keyVisible,
            suffix: IconButton(
              icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white.withOpacity(0.35), size: 18),
              onPressed: () => setState(() => _keyVisible = !_keyVisible),
            ),
          ),
          const Spacer(),
          _btn('NEXT', _next),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _next,
              child: Text('Skip for now',
                  style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.28), fontSize: 13)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );

  Widget _voicePage() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Icon(_voiceDone ? Icons.verified_user_outlined : Icons.record_voice_over_outlined,
              color: _voiceDone ? const Color(0xFF00E676) : const Color(0xFF00D4FF),
              size: 44),
          const SizedBox(height: 24),
          Text('VOICE\nCALIBRATION',
              style: GoogleFonts.orbitron(
                  fontSize: 30,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  height: 1.3)),
          const SizedBox(height: 14),
          Text(
              'Record ${_voice.requiredSamples} voice samples so Meka recognises only you.',
              style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.50), fontSize: 14, height: 1.6)),
          const SizedBox(height: 28),
          // Sample dots
          Row(
            children: List.generate(
              _voice.requiredSamples,
              (i) => Container(
                margin: const EdgeInsets.only(right: 12),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pitches.length
                      ? const Color(0xFF00E676).withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
                  border: Border.all(
                    color: i < _pitches.length
                        ? const Color(0xFF00E676)
                        : i == _pitches.length && _isRecording
                            ? const Color(0xFF00D4FF)
                            : Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: i < _pitches.length
                      ? const Icon(Icons.check, color: Color(0xFF00E676), size: 18)
                      : _isRecording && i == _pitches.length
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  color: Color(0xFF00D4FF), strokeWidth: 2))
                          : Text('${i + 1}',
                              style: GoogleFonts.orbitron(
                                  color: Colors.white.withOpacity(0.40),
                                  fontSize: 13)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: (_voiceDone ? const Color(0xFF00E676) : const Color(0xFF00D4FF))
                  .withOpacity(0.05),
              border: Border.all(
                  color: (_voiceDone ? const Color(0xFF00E676) : const Color(0xFF00D4FF))
                      .withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(
                    _isRecording ? Icons.mic : Icons.info_outline,
                    color: _isRecording ? Colors.red : const Color(0xFF00D4FF),
                    size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_voiceStatus,
                      style: GoogleFonts.inter(
                          color: Colors.white.withOpacity(0.60),
                          fontSize: 12, height: 1.5)),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!_voiceDone)
            GestureDetector(
              onTap: _isRecording ? null : _record,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: _isRecording
                        ? [Colors.red.shade700, Colors.red.shade400]
                        : [const Color(0xFF00D4FF), const Color(0xFF7C4DFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: (_isRecording ? Colors.red : const Color(0xFF00D4FF))
                            .withOpacity(0.4),
                        blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                          _isRecording ? 'Recording...' : 'Say "Hey Meka"',
                          style: GoogleFonts.orbitron(
                              color: Colors.white,
                              fontSize: 13, letterSpacing: 1,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          if (_voiceDone) _btn('LAUNCH MEKA', _loading ? null : _finish,
              color: const Color(0xFF00E676)),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loading ? null : _finish,
              child: Text(_voiceDone ? '' : 'Skip voice calibration',
                  style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.28), fontSize: 13)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      );

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) =>
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          color: Colors.white.withOpacity(0.03),
        ),
        child: TextField(
          controller: ctrl,
          obscureText: obscure,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white.withOpacity(0.22)),
            border: InputBorder.none,
            prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.35), size: 20),
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      );

  Widget _btn(String label, VoidCallback? onTap,
      {Color color = const Color(0xFF00D4FF)}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: onTap != null
                ? LinearGradient(colors: [color, color.withOpacity(0.5)])
                : null,
            color: onTap == null ? Colors.white.withOpacity(0.08) : null,
            boxShadow: onTap != null
                ? [
                    BoxShadow(
                        color: color.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8))
                  ]
                : null,
          ),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(label,
                    style: GoogleFonts.orbitron(
                        color: Colors.white,
                        fontSize: 13,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }
}
