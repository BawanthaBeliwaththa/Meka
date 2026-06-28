import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFF010409),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF071520),
        ),
      ),
      home: setupDone ? const HomeScreen() : const SetupScreen(),
    );
  }
}
