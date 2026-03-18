import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_page.dart';
import 'screens/main_layout.dart';

late List<CameraDescription> cameras;

// --- GLOBAL THEME COLORS ---
const Color navyBlue = Color(0xFF0B132B);
const Color darkSlate = Color(0xFF1C2541);
const Color mintGreen = Color(0xFF48E5C2);
const Color neonRed = Color(0xFFFF4D4D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BetterGym',
      theme: ThemeData(
        scaffoldBackgroundColor: navyBlue,
        primaryColor: mintGreen,
        colorScheme: const ColorScheme.dark(
          primary: mintGreen,
          secondary: mintGreen,
          surface: darkSlate,
          error: neonRed,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: navyBlue,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: HomeEntry(cameras: cameras),
    );
  }
}

class HomeEntry extends StatelessWidget {
  const HomeEntry({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  Future<bool> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('logged_in') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // This checks auth status before rendering the first screen
    return FutureBuilder<bool>(
      future: _checkLoginStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Splash/Loading screen while checking auth
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: mintGreen),
            ),
          );
        }

        final isLoggedIn = snapshot.data ?? false;

        if (isLoggedIn) {
          return MainLayout(cameras: cameras); // Bypass Login
        } else {
          return LoginPage(cameras: cameras);
        }
      },
    );
  }
}