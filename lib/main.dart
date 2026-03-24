import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW: Required for memory reading

import 'screens/login_page.dart';
import 'screens/main_layout.dart'; // NEW: Your actual home wrapper
import 'services/hardware_service.dart';

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
  final bool isLoggedIn = prefs.getBool('logged_in') ?? false; // Matches your login page key

  // Boot the app and pass the state
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn; // State variable to catch memory

  const MyApp({super.key, required this.isLoggedIn});

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
      // THE ROUTER: Skip login if memory says true
      home: isLoggedIn ? const MainLayout() : const LoginPage(), 
    );
  }
}