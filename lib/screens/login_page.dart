import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; 
import '../services/api_services.dart';
import 'main_layout.dart';
import 'register_page.dart';
import 'dart:async';
import '../services/local_db_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _message = '';
  String _loadingText = ''; 
  bool _isPasswordVisible = false;

  // --- SECURITY: WIPE OLD DATA ON LOGIN ---
  Future<void> _saveLogin(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if a different user was logged in previously. If so, nuke the local DB.
    int? previousUserId = prefs.getInt('user_id');
    if (previousUserId != null && previousUserId != userData['id']) {
        debugPrint("New user detected. Wiping local SQLite database.");
        // We will add clearAllLocalData() to local_db_service later, just printing for now.
    }

    await prefs.setBool('logged_in', true);
    await prefs.setString('username', userData['username']);
    await prefs.setInt('user_id', userData['id']);
    await prefs.setString('auth_token', userData['auth_token']);
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _message = 'Enter username and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
      _loadingText = 'Authenticating...';
    });

    try {
      final response = await ApiService.login(
        username: username,
        password: password,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response['status'] == 'success') {
        await _saveLogin(response['user']);

        // --- NEW: PULL CLOUD SETTINGS ON LOGIN ---
        setState(() => _loadingText = 'Loading preferences...');
        final cloudSettings = await ApiService.pullSettings();
        
        if (cloudSettings != null && cloudSettings['status'] == 'success') {
          final prefs = await SharedPreferences.getInstance();
          final data = cloudSettings['data'];
          
          await prefs.setInt('prep_time', int.tryParse(data['prep_time'].toString()) ?? 30);
          await prefs.setInt('rest_time', int.tryParse(data['rest_time'].toString()) ?? 30);
          await prefs.setBool('voice_enabled', data['voice_enabled'].toString() == '1');
          await prefs.setDouble('feedback_volume', double.tryParse(data['feedback_volume'].toString()) ?? 1.0);
          await prefs.setDouble('beeps_volume', double.tryParse(data['beeps_volume'].toString()) ?? 1.0);
          debugPrint("CLOUD SETTINGS: Successfully applied to local device.");
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainLayout()),
        );
      } else {
        setState(() => _message = response['message'] ?? 'Login failed. Check credentials.');
      }
    } on TimeoutException {
      setState(() => _message = 'Connection timed out. Server is unreachable.');
    } catch (e) {
      setState(() => _message = 'Server returned invalid data. Check console.');
      debugPrint('CRITICAL LOGIN ERROR: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _customInputDecoration(String label, IconData icon, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade400),
      prefixIcon: Icon(icon, color: mintGreen),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: darkSlate,
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: mintGreen, width: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.fitness_center, size: 64, color: mintGreen),
                  const SizedBox(height: 16),
                  const Text('Better-GYM', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text('AI-Powered Workout Assistant', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                  const SizedBox(height: 48),

                  TextField(controller: _usernameController, style: const TextStyle(color: Colors.white), decoration: _customInputDecoration('Username', Icons.person)),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _passwordController, obscureText: !_isPasswordVisible, style: const TextStyle(color: Colors.white),
                    decoration: _customInputDecoration('Password', Icons.lock, suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: navyBlue)), const SizedBox(width: 12), Text(_loadingText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: navyBlue))])
                          : const Text('LOGIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                    child: RichText(text: const TextSpan(text: "Don't have an account? ", style: TextStyle(color: Colors.grey), children: [TextSpan(text: 'Sign up', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold))])),
                  ),

                  // --- DEV BYPASS ---
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayout())),
                    child: const Text('SKIP LOGIN (DEV ONLY)', style: TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12)),
                  ),

                  if (_message.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: neonRed.withOpacity(0.1), border: Border.all(color: neonRed.withOpacity(0.5)), borderRadius: BorderRadius.circular(8)), child: Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: neonRed))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}