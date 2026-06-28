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
  final _nameController = TextEditingController();
  final _keyController = TextEditingController();
  bool _keyVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text = prefs.getString('user_name') ?? '';
    _keyController.text = prefs.getString('gemini_api_key') ?? '';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await LlmService().saveSettings(
      apiKey: _keyController.text.trim(),
      userName: _nameController.text.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_done', true);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settings saved!',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: const Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings',
          style: GoogleFonts.orbitron(
            color: Colors.white,
            fontSize: 18,
            letterSpacing: 3,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white.withOpacity(0.54)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _sectionHeader('Your Profile'),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _nameController,
            label: 'Your Name',
            hint: 'e.g. Bawantha',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 32),
          _sectionHeader('AI Brain — Gemini'),
          const SizedBox(height: 8),
          _infoCard(
            icon: Icons.info_outline,
            text:
                'Get a FREE Gemini API key at aistudio.google.com. Paste it below to give Meka her intelligence.',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _keyController,
            label: 'Gemini API Key',
            hint: 'AIzaSy...',
            icon: Icons.vpn_key_outlined,
            obscure: !_keyVisible,
            suffix: IconButton(
              icon: Icon(
                _keyVisible ? Icons.visibility_off : Icons.visibility,
                color: Colors.white.withOpacity(0.38),
                size: 20,
              ),
              onPressed: () => setState(() => _keyVisible = !_keyVisible),
            ),
          ),
          const SizedBox(height: 32),
          _sectionHeader('Wake Word'),
          const SizedBox(height: 8),
          _infoCard(
            icon: Icons.mic_none,
            text:
                'Say "Hey Meka", "Hi Meka", or just "Meka" to wake the assistant. Or tap the orb anytime.',
          ),
          const SizedBox(height: 32),
          _sectionHeader('Device Access'),
          const SizedBox(height: 8),
          _infoCard(
            icon: Icons.phone_android,
            text:
                'Meka can open apps, set alarms, send messages, control volume, and search the web on your behalf.',
          ),
          const SizedBox(height: 40),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.orbitron(
        fontSize: 11,
        color: const Color(0xFF6C63FF),
        letterSpacing: 3,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        color: Colors.white.withOpacity(0.04),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: GoogleFonts.inter(color: Colors.white.withOpacity(0.87), fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: Colors.white.withOpacity(0.24)),
          labelStyle: GoogleFonts.inter(color: Colors.white.withOpacity(0.38), fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.38), size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF6C63FF).withOpacity(0.08),
        border: Border.all(
            color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF6C63FF), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: Colors.white.withOpacity(0.60),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _saving ? null : _save,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: _saving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  'Save Settings',
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
    super.dispose();
  }
}
