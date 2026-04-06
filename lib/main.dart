import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW: Required for memory reading
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/login_page.dart';
import 'screens/main_layout.dart'; // NEW: Your actual home wrapper
import 'services/hardware_service.dart';
import 'screens/onboarding_screen.dart';
// --- GLOBAL COLORS ---
const Color mintGreen = Color(0xFF00FFCC);
const Color navyBlue = Color(0xFF0A192F);
const Color darkSlate = Color(0xFF112240);
const Color neonRed = Color(0xFFFF3366);

Future<void> main() async {
  // Ensure the engine is running before talking to native hardware
  WidgetsFlutterBinding.ensureInitialized();
  
  // Boot the hardware service globally
  await HardwareService.instance.init(); 

  // CHECK PERSISTENT MEMORY
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('logged_in') ?? false;
  final bool hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false; // <-- ADD THIS

  // Boot the app and pass the state
  runApp(
    ProviderScope(
      child: MyApp(
        isLoggedIn: isLoggedIn,
        hasSeenOnboarding: hasSeenOnboarding, // <-- ADD THIS
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn; 
  final bool hasSeenOnboarding;

  // The single, correct constructor
  const MyApp({super.key, required this.isLoggedIn, required this.hasSeenOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Better-GYM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: navyBlue,
        colorScheme: const ColorScheme.dark(
          primary: mintGreen,
          surface: darkSlate,
        ),
        fontFamily: 'Roboto', 
      ),
      // THE ROUTER: First check onboarding, then check login
      home: !hasSeenOnboarding 
          ? OnboardingScreen(isLoggedIn: isLoggedIn) 
          : (isLoggedIn ? const MainLayout() : const LoginPage()),
    );
  }
}