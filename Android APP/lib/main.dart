import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/hub_select_screen.dart';
import 'services/hub_profile_service.dart';
import 'services/iot_hub_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final setupDone = prefs.getBool('setup_done') ?? false;

  // Load hub profiles (migrates legacy single-hub setting automatically)
  final hubSvc = HubProfileService();
  await hubSvc.load();

  // Sync active hub into IotHubService
  final activeHub = hubSvc.activeProfile;
  if (activeHub != null) {
    await IotHubService().saveHost(activeHub.url);
  }

  runApp(MekaApp(
    setupDone: setupDone,
    hasHubs: hubSvc.profiles.isNotEmpty,
  ));
}

class MekaApp extends StatelessWidget {
  final bool setupDone;
  final bool hasHubs;
  const MekaApp({super.key, required this.setupDone, required this.hasHubs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meka',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF010409),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF071520),
        ),
      ),
      routes: {
        '/home': (_) => const HomeScreen(),
        '/hub_select': (_) => const HubSelectScreen(isOnboarding: true),
        '/setup': (_) => const SetupScreen(),
      },
      // Route priority: no hubs → hub select → setup → home
      home: !hasHubs
          ? const HubSelectScreen(isOnboarding: true)
          : !setupDone
              ? const SetupScreen()
              : const HomeScreen(),
    );
  }
}

