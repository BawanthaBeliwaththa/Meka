import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/llm_service.dart';
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
  int _page = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
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
              padding: const EdgeInsets.all(28),
              child: _page == 0 ? _buildWelcome() : _buildApiSetup(),
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
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.5),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          'Hello,\nI\'m Meka.',
          style: GoogleFonts.orbitron(
            fontSize: 36,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your personal AI assistant.\nAlways listening. Always ready.\nJust for you.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.white54,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 48),
        Text(
          'What should I call you?',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
            color: Colors.white.withOpacity(0.05),
          ),
          child: TextField(
            controller: _nameController,
            autofocus: true,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Your name...',
              hintStyle: GoogleFonts.inter(color: Colors.white24),
              border: InputBorder.none,
              prefixIcon:
                  const Icon(Icons.person_outline, color: Colors.white38),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        const Spacer(),
        _buildNextButton('Continue', _nextPage),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildApiSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        const Icon(Icons.psychology_outlined,
            color: Color(0xFF6C63FF), size: 48),
        const SizedBox(height: 24),
        Text(
          'Connect\nMeka\'s Brain.',
          style: GoogleFonts.orbitron(
            fontSize: 32,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Meka uses Google Gemini AI to understand you. Get a free API key at:',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white54,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'aistudio.google.com',
            style: GoogleFonts.mono(
              fontSize: 13,
              color: const Color(0xFF00D4FF),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
            color: Colors.white.withOpacity(0.05),
          ),
          child: TextField(
            controller: _keyController,
            obscureText: !_keyVisible,
            style: GoogleFonts.mono(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Paste your Gemini API key here...',
              hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
              border: InputBorder.none,
              prefixIcon:
                  const Icon(Icons.vpn_key_outlined, color: Colors.white38),
              suffixIcon: IconButton(
                icon: Icon(
                  _keyVisible ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () => setState(() => _keyVisible = !_keyVisible),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No key? Tap "Skip" — you can add it later in Settings.',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.white30),
        ),
        const Spacer(),
        _buildNextButton(
          _loading ? 'Starting Meka...' : "Let's Go!",
          _loading ? null : _finish,
          primary: true,
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _finish,
            child: Text(
              'Skip for now',
              style: GoogleFonts.inter(color: Colors.white30, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton(String label, VoidCallback? onTap,
      {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: primary || onTap != null
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
                )
              : null,
          color: primary || onTap != null ? null : Colors.white12,
          boxShadow: primary || onTap != null
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
