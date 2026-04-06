import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Pulls in your global colors
import 'login_page.dart';
import 'main_layout.dart';

class OnboardingScreen extends StatefulWidget {
  final bool isLoggedIn;
  
  const OnboardingScreen({super.key, required this.isLoggedIn});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // This function seals the onboarding screen forever
  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true); // Lock it out

    if (!mounted) return;
    
    // Route to the correct destination based on memory
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => widget.isLoggedIn ? const MainLayout() : const LoginPage(),
      ),
    );
  }

  Widget _buildPage(String title, String description, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 100, color: mintGreen),
          const SizedBox(height: 40),
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            description,
            style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navyBlue,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            children: [
              _buildPage("Welcome to Better-GYM", "Your AI-powered biomechanics coach.", Icons.fitness_center),
              _buildPage("Disclaimer", "This app uses your camera to analyze form. AI is not a substitute for medical advice.", Icons.warning_amber_rounded),
              _buildPage("Get Ready", "Ensure your whole body is in the frame for optimal tracking.", Icons.camera_alt),
            ],
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Indicators
                Row(
                  children: List.generate(3, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index ? mintGreen : Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                // Next / Start Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue),
                  onPressed: () {
                    if (_currentPage == 2) {
                      _completeOnboarding();
                    } else {
                      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                    }
                  },
                  child: Text(_currentPage == 2 ? "START" : "NEXT", style: const TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}