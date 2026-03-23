import 'package:flutter/material.dart';

import 'screens/login_page.dart';
import 'services/hardware_service.dart'; // NEW

// --- GLOBAL COLORS ---
const Color mintGreen = Color(0xFF00FFCC);
const Color navyBlue = Color(0xFF0A192F);
const Color darkSlate = Color(0xFF112240);
const Color neonRed = Color(0xFFFF3366);

Future<void> main() async {
  // Ensure the engine is running before talking to native hardware
  WidgetsFlutterBinding.ensureInitialized();
  
  // NEW: Boot the hardware service globally
  await HardwareService.instance.init(); 

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  // NEW: Removed the camera requirements from the constructor
  const MyApp({super.key});

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
      // NEW: Removed cameras parameter
      home: const LoginPage(), 
    );
  }
}