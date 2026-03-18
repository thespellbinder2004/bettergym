import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';

import '../main.dart'; // Inherit global colors
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const ProfilePage({super.key, required this.cameras});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _username = "Loading...";

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? "User";
    });
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: darkSlate,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Logout', style: TextStyle(color: Colors.white)),
          content: const Text('Are you sure you want to end your session?', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL', style: TextStyle(color: mintGreen)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: neonRed,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('LOGOUT'),
            ),
          ],
        );
      },
    );

    if (confirm == true && context.mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('logged_in');
      await prefs.remove('username');

      if (!context.mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginPage(cameras: widget.cameras),
        ),
        (route) => false,
      );
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        centerTitle: false,
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
                Text(
                  _username, // Dynamically loaded
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
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
              onTap: () {},
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
            onPressed: () {},
          ),

          const SizedBox(height: 24),

          // Massive Logout Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: neonRed.withOpacity(0.1),
              foregroundColor: neonRed,
              side: const BorderSide(color: neonRed),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}