import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/llm_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _keyVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _nameCtrl.text = prefs.getString('user_name') ?? '';
    _keyCtrl.text = prefs.getString('gemini_api_key') ?? '';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await LlmService().saveSettings(
        apiKey: _keyCtrl.text.trim(), userName: _nameCtrl.text.trim());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_done', true);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Settings saved', style: GoogleFonts.inter()),
        backgroundColor: const Color(0xFF00D4FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF010409),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: Colors.white.withOpacity(0.5), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('SYSTEM CONFIG',
            style: GoogleFonts.orbitron(
                color: const Color(0xFF00D4FF),
                fontSize: 14,
                letterSpacing: 4)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _label('IDENTITY'),
          const SizedBox(height: 12),
          _field(ctrl: _nameCtrl, label: 'Your Name', icon: Icons.person_outline,
              hint: 'e.g. Bawantha'),
          const SizedBox(height: 32),
          _label('AI CORE — GEMINI'),
          const SizedBox(height: 8),
          _infoCard(
              'Get your FREE Gemini API key at aistudio.google.com\nThis powers Meka\'s intelligence.'),
          const SizedBox(height: 12),
          _field(
            ctrl: _keyCtrl,
            label: 'Gemini API Key',
            icon: Icons.vpn_key_outlined,
            hint: 'AIzaSy...',
            obscure: !_keyVisible,
            suffix: IconButton(
              icon: Icon(
                  _keyVisible ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white.withOpacity(0.38),
                  size: 18),
              onPressed: () => setState(() => _keyVisible = !_keyVisible),
            ),
          ),
          const SizedBox(height: 32),
          _label('WAKE WORD'),
          const SizedBox(height: 8),
          _infoCard(
              'Say "Hey Meka", "Hi Meka" or just "Meka".\nOr tap the orb to activate instantly.'),
          const SizedBox(height: 32),
          _label('DEVICE CONTROL'),
          const SizedBox(height: 8),
          _infoCard(
              'Meka can open apps, set alarms, send messages,\ncontrol volume, search the web, and more.'),
          const SizedBox(height: 48),
          _saveBtn(),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: GoogleFonts.orbitron(
          fontSize: 10,
          color: const Color(0xFF00D4FF),
          letterSpacing: 4,
          fontWeight: FontWeight.w600));

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String hint = '',
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
          style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white.withOpacity(0.20)),
            labelStyle:
                GoogleFonts.inter(color: Colors.white.withOpacity(0.35), fontSize: 12),
            prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.35), size: 20),
            suffixIcon: suffix,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      );

  Widget _infoCard(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF00D4FF).withOpacity(0.05),
          border:
              Border.all(color: const Color(0xFF00D4FF).withOpacity(0.15)),
        ),
        child: Text(text,
            style: GoogleFonts.inter(
                color: Colors.white.withOpacity(0.50),
                fontSize: 12,
                height: 1.6)),
      );

  Widget _saveBtn() => GestureDetector(
        onTap: _saving ? null : _save,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF7C4DFF)]),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF00D4FF).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Center(
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text('SAVE CONFIGURATION',
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
    super.dispose();
  }
}
