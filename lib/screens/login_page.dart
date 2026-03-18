import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; // Imports your global colors
import '../services/api_services.dart';
import 'main_layout.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _message = '';

  Future<void> _saveLogin({required String username}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged_in', true);
    await prefs.setString('username', username);
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _message = 'Enter username and password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      final response = await ApiService.login(
        username: username,
        password: password,
      );

      if (!mounted) return;

      if (response['status'] == 'success') {
        final savedUsername = response['user']['username'] ?? username;

        await _saveLogin(username: savedUsername);

        if (!mounted) return;

        // --- UPDATED ROUTING: Sends user to the new MainLayout ---
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainLayout(cameras: widget.cameras),
          ),
        );
      } else {
        setState(() {
          _message = response['message'] ?? 'Login failed.';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error communicating with server. Check your connection.';
        debugPrint('Login Error: $e');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- CUSTOM UI STYLING FOR INPUTS ---
  InputDecoration _customInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade400),
      prefixIcon: Icon(icon, color: mintGreen),
      filled: true,
      fillColor: darkSlate,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: mintGreen, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Inherit the background color from main.dart's theme
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
                  // App Logo / Title
                  const Icon(Icons.fitness_center, size: 64, color: mintGreen),
                  const SizedBox(height: 16),
                  const Text(
                    'Better-GYM',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI-Powered Workout Assistant',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Input Fields
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _customInputDecoration('Username', Icons.person),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _customInputDecoration('Password', Icons.lock),
                  ),
                  const SizedBox(height: 24),

                  // Login Button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: mintGreen,
                        foregroundColor: navyBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: navyBlue,
                              ),
                            )
                          : const Text(
                              'LOGIN',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Register Link
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RegisterPage(cameras: widget.cameras),
                              ),
                            );
                          },
                    child: RichText(
                      text: const TextSpan(
                        text: "Don't have an account? ",
                        style: TextStyle(color: Colors.grey),
                        children: [
                          TextSpan(
                            text: 'Sign up',
                            style: TextStyle(
                              color: mintGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Error Message Display
                  if (_message.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: neonRed.withOpacity(0.1),
                        border: Border.all(color: neonRed.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: neonRed),
                      ),
                    ),
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