import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/background_service.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MekaBackgroundService.initialize();
  final prefs = await SharedPreferences.getInstance();
  final setupDone = prefs.getBool('setup_done') ?? false;
  runApp(MekaApp(setupDone: setupDone));
}

class MekaApp extends StatelessWidget {
  final bool setupDone;
  const MekaApp({super.key, required this.setupDone});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meka',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00D4FF),
          surface: Color(0xFF12121A),
        ),
      ),
      home: setupDone ? const HomeScreen() : const SetupScreen(),
      routes: {
        '/home': (_) => const HomeScreen(),
        '/setup': (_) => const SetupScreen(),
      },
    );
  }
}
