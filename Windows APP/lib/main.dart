// lib/main.dart — MEKA Super Desktop Entry Point (Windows + Linux)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/settings_screen.dart';
import 'services/llm_service.dart';
import 'services/hub_profile_service.dart';
import 'services/iot_hub_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LlmService().loadSettings();

  // Load hub profiles (migrates legacy single-hub setting automatically)
  final hubSvc = HubProfileService();
  await hubSvc.load();

  // Sync active hub into IotHubService
  final activeHub = hubSvc.activeProfile;
  if (activeHub != null) {
    await IotHubService().saveHost(activeHub.url);
  }

  final prefs = await SharedPreferences.getInstance();
  final setupDone = prefs.getBool('setup_done') ?? false;

  runApp(MekaDesktopApp(
    setupDone: setupDone,
    hasHubs: hubSvc.profiles.isNotEmpty,
  ));
}

class MekaDesktopApp extends StatelessWidget {
  final bool setupDone;
  final bool hasHubs;
  const MekaDesktopApp({
    super.key,
    required this.setupDone,
    required this.hasHubs,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEKA — Desktop AI Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00F0FF),
          secondary: const Color(0xFF7C3AED),
          surface: const Color(0xFF030712),
          error: const Color(0xFFFF0055),
        ),
        fontFamily: 'Rajdhani',
        scaffoldBackgroundColor: const Color(0xFF030712),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF040A1A),
          foregroundColor: Color(0xFF00F0FF),
          elevation: 0,
        ),
      ),
      routes: {
        '/home': (_) => const HomeScreen(),
        '/setup': (_) => const SetupScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
      // Route priority: setup wizard first if not done, then home
      home: (!hasHubs || !setupDone)
          ? const SetupScreen()
          : const HomeScreen(),
    );
  }
}

