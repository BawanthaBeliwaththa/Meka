// lib/screens/setup_screen.dart — MEKA Desktop Setup Wizard
// 3-step onboarding: Welcome → Hub Connection → AI Configuration

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/llm_service.dart';
import '../services/hub_profile_service.dart';
import '../services/iot_hub_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with TickerProviderStateMixin {
  int _step = 0; // 0=Welcome, 1=Hub, 2=AI Config
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  // Hub step
  final _hubUrlCtrl  = TextEditingController();
  final _hubNameCtrl = TextEditingController(text: 'My Home Hub');
  bool _testingHub   = false;
  bool _hubOk        = false;
  String? _hubResult;

  // AI step
  final _nameCtrl   = TextEditingController(text: 'Sir');
  final _keyCtrl    = TextEditingController();
  bool _keyVisible  = false;
  bool _finishing   = false;

  static const _cyan   = Color(0xFF00F0FF);
  static const _purple = Color(0xFF7C3AED);
  static const _green  = Color(0xFF00FF66);
  static const _bg     = Color(0xFF030712);
  static const _bgCard = Color(0xFF080C1E);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _hubUrlCtrl.dispose();
    _hubNameCtrl.dispose();
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    _fadeCtrl.reverse().then((_) {
      setState(() => _step++);
      _fadeCtrl.forward();
    });
  }

  Future<void> _testHub() async {
    setState(() { _testingHub = true; _hubResult = null; _hubOk = false; });
    final svc = HubProfileService();
    final result = await svc.testHub(_hubUrlCtrl.text.trim());
    setState(() {
      _testingHub = false;
      _hubOk = result != null;
      if (result != null) {
        final v = result['version'] ?? '?';
        final ip = result['local_ip'] ?? '?';
        _hubResult = '✓  CONNECTED  ·  Hub v$v  ·  IP: $ip';
      } else {
        _hubResult = '✗  CANNOT REACH HUB  —  check URL and make sure the hub is running';
      }
    });
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    // Save hub profile
    final hubSvc = HubProfileService();
    await hubSvc.load();
    final profile = HubProfile(
      id: hubSvc.generateId(),
      name: _hubNameCtrl.text.trim().isEmpty ? 'My Home Hub' : _hubNameCtrl.text.trim(),
      url: _hubUrlCtrl.text.trim(),
      colorIndex: 0,
    );
    await hubSvc.addProfile(profile);
    await IotHubService().saveHost(profile.url);

    // Save AI settings
    await LlmService().saveSettings(
      apiKey: _keyCtrl.text.trim(),
      userName: _nameCtrl.text.trim().isEmpty ? 'Sir' : _nameCtrl.text.trim(),
    );

    // Mark setup complete
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
      backgroundColor: _bg,
      body: Row(
        children: [
          // ── Left accent bar ───────────────────────────────────────────────
          Container(
            width: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_cyan, _purple, _green],
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _fade,
              child: Center(
                child: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Logo ───────────────────────────────────────────────
                      Text('M.E.K.A.',
                          style: GoogleFonts.orbitron(
                              fontSize: 42, fontWeight: FontWeight.w900,
                              color: _cyan, letterSpacing: 10)),
                      const SizedBox(height: 4),
                      Text('MASTER ELECTRONIC KINETIC ASSISTANT',
                          style: GoogleFonts.orbitron(
                              fontSize: 9, color: Colors.white24, letterSpacing: 4)),
                      Text('SUPER EDITION  ·  DESKTOP v3.0',
                          style: GoogleFonts.orbitron(
                              fontSize: 9, color: _purple, letterSpacing: 3)),
                      const SizedBox(height: 40),

                      // ── Step indicator ────────────────────────────────────
                      _StepIndicator(step: _step),
                      const SizedBox(height: 36),

                      // ── Step content ──────────────────────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _step == 0
                            ? _buildWelcome()
                            : _step == 1
                                ? _buildHubStep()
                                : _buildAiStep(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 0: Welcome ────────────────────────────────────────────────────────
  Widget _buildWelcome() {
    return Column(
      key: const ValueKey(0),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cyan.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(Icons.smart_toy_outlined, color: _cyan, size: 52),
              const SizedBox(height: 16),
              Text('WELCOME TO MEKA',
                  style: GoogleFonts.orbitron(
                      fontSize: 16, color: Colors.white,
                      fontWeight: FontWeight.w700, letterSpacing: 4)),
              const SizedBox(height: 12),
              Text(
                'Your personal AI assistant & smart home controller.\n'
                'We\'ll get you set up in just 2 quick steps.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 14, color: Colors.white54, height: 1.6),
              ),
              const SizedBox(height: 24),
              _WizardButton(
                  label: 'GET STARTED', color: _cyan, onTap: _nextStep),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 1: Hub Connection ─────────────────────────────────────────────────
  Widget _buildHubStep() {
    return Column(
      key: const ValueKey(1),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _purple.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hub_outlined, color: _purple, size: 24),
                  const SizedBox(width: 10),
                  Text('CONNECT YOUR HUB',
                      style: GoogleFonts.orbitron(
                          fontSize: 14, color: _purple, letterSpacing: 3,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the IP address or URL of your MEKA IoT Hub.\n'
                'The hub should be running on your local network.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white38, height: 1.5),
              ),
              const SizedBox(height: 20),

              _WizardField(
                  controller: _hubNameCtrl,
                  label: 'HUB NAME',
                  hint: 'e.g. My Home, Office',
                  color: _purple),
              const SizedBox(height: 12),
              _WizardField(
                  controller: _hubUrlCtrl,
                  label: 'HUB URL / IP',
                  hint: 'e.g. 192.168.1.100:5000 or http://meka.local:5000',
                  color: _purple),
              const SizedBox(height: 16),

              // Test connection button
              SizedBox(
                width: double.infinity,
                child: _WizardButton(
                  label: _testingHub ? 'TESTING...' : 'TEST CONNECTION',
                  color: _purple,
                  onTap: _testingHub ? null : _testHub,
                  outlined: true,
                ),
              ),

              if (_hubResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_hubOk ? _green : const Color(0xFFFF0055)).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: (_hubOk ? _green : const Color(0xFFFF0055)).withOpacity(0.4)),
                  ),
                  child: Text(_hubResult!,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _hubOk ? _green : const Color(0xFFFF0055))),
                ),
              ],
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _fadeCtrl.reverse().then((_) {
                      setState(() => _step = 0);
                      _fadeCtrl.forward();
                    }),
                    child: Text('← BACK',
                        style: GoogleFonts.orbitron(
                            fontSize: 9, color: Colors.white38, letterSpacing: 2)),
                  ),
                  _WizardButton(
                    label: _hubUrlCtrl.text.isEmpty ? 'SKIP' : 'NEXT →',
                    color: _purple,
                    onTap: _nextStep,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: AI Config ──────────────────────────────────────────────────────
  Widget _buildAiStep() {
    return Column(
      key: const ValueKey(2),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _green.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_outlined, color: _green, size: 24),
                  const SizedBox(width: 10),
                  Text('AI CONFIGURATION',
                      style: GoogleFonts.orbitron(
                          fontSize: 14, color: _green, letterSpacing: 3,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Configure your AI assistant name and API key.\n'
                'Get a free Gemini API key at aistudio.google.com',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white38, height: 1.5),
              ),
              const SizedBox(height: 20),

              _WizardField(
                  controller: _nameCtrl,
                  label: 'YOUR NAME / CALL SIGN',
                  hint: 'e.g. Sir, Alex, Captain',
                  color: _green),
              const SizedBox(height: 12),
              _WizardField(
                  controller: _keyCtrl,
                  label: 'GEMINI API KEY',
                  hint: 'AIza...',
                  color: _green,
                  obscureText: !_keyVisible,
                  suffix: IconButton(
                    icon: Icon(
                        _keyVisible ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38, size: 18),
                    onPressed: () => setState(() => _keyVisible = !_keyVisible),
                  )),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _fadeCtrl.reverse().then((_) {
                      setState(() => _step = 1);
                      _fadeCtrl.forward();
                    }),
                    child: Text('← BACK',
                        style: GoogleFonts.orbitron(
                            fontSize: 9, color: Colors.white38, letterSpacing: 2)),
                  ),
                  _WizardButton(
                    label: _finishing ? 'LAUNCHING...' : 'LAUNCH MEKA ✦',
                    color: _green,
                    onTap: _finishing ? null : _finish,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Supporting Widgets ─────────────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final int step;
  const _StepIndicator({required this.step});

  static const _colors = [Color(0xFF00F0FF), Color(0xFF7C3AED), Color(0xFF00FF66)];
  static const _labels = ['WELCOME', 'HUB', 'AI'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i <= step;
        final c = _colors[i];
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 32 : 24,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: active ? c.withOpacity(0.2) : Colors.white.withOpacity(0.04),
                border: Border.all(
                    color: active ? c : Colors.white.withOpacity(0.1),
                    width: active ? 1.5 : 1),
              ),
              child: Center(
                child: Text(_labels[i],
                    style: TextStyle(
                        color: active ? c : Colors.white24,
                        fontSize: 7, fontFamily: 'Orbitron', letterSpacing: 1)),
              ),
            ),
            if (i < 2)
              Container(
                width: 40, height: 1,
                color: step > i ? _colors[i] : Colors.white12,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
        );
      }),
    );
  }
}

class _WizardButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool outlined;
  const _WizardButton(
      {required this.label,
      required this.color,
      this.onTap,
      this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: outlined ? Colors.transparent : color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.6), width: 1.5),
            boxShadow: outlined
                ? []
                : [BoxShadow(color: color.withOpacity(0.25), blurRadius: 16)],
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontFamily: 'Orbitron',
                  fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ),
      ),
    );
  }
}

class _WizardField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final Color color;
  final bool obscureText;
  final Widget? suffix;

  const _WizardField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.color,
    this.obscureText = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 8, fontFamily: 'Orbitron', letterSpacing: 3)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            suffixIcon: suffix,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.7), width: 1.5),
            ),
            filled: true,
            fillColor: color.withOpacity(0.04),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
