import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';

import '../main.dart'; // Inherit global colors
import 'login_page.dart';

class ProfilePage extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const ProfilePage({super.key, required this.cameras});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logged_in');
    await prefs.remove('username');

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoginPage(cameras: cameras),
      ),
      (route) => false,
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // In a real app, you'd fetch this from SharedPreferences or your API
    const String username = "S"; 

    return Scaffold(
      appBar: AppBar(
        title: const Text('Athlete Profile'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: neonRed),
            onPressed: () => _logout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Identity Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: darkSlate,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: mintGreen.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: navyBlue,
                  child: Icon(Icons.person, size: 40, color: mintGreen),
                ),
                const SizedBox(height: 16),
                const Text(
                  username,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatPill('Sessions', '34', Colors.white),
                    _buildStatPill('Avg Form', '88%', mintGreen),
                    _buildStatPill('Risk Tier', 'Low', mintGreen),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // PRA Warning History
          const Text(
            'PREDICTIVE RISK ASSESSMENT',
            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: darkSlate,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: neonRed),
              title: const Text('Knee Valgus Detected', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Last seen: 2 days ago during Squats', style: TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                // Show modal with detailed biomechanical breakdown
              },
            ),
          ),

          const SizedBox(height: 24),

          // Utility Actions
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: navyBlue,
              foregroundColor: Colors.white,
              side: const BorderSide(color: mintGreen),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.download),
            label: const Text('Export Biomechanical Data (CSV)'),
            onPressed: () {
              // Trigger export logic
            },
          ),
        ],
      ),
    );
  }
}