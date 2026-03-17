import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../main.dart'; // Inherit global colors
import 'dashboard_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'session_setup_page.dart';

class MainLayout extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MainLayout({super.key, required this.cameras});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 1; // Start on the Dashboard tab

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // All four tabs are now fully wired to their respective screens
    _pages = [
      const SettingsPage(),
      const DashboardPage(),
      const NotificationsPage(),
      ProfilePage(cameras: widget.cameras),
    ];
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _pages[_currentIndex],
      ),
      // --- The Camera Button (Frame 7 Trigger) ---
      floatingActionButton: FloatingActionButton(
        backgroundColor: mintGreen,
        onPressed: () {
          // Slide up the session setup page
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SessionSetupPage(cameras: widget.cameras),
              fullscreenDialog: true, // Makes it slide up from the bottom
            ),
          );
        },
        shape: const CircleBorder(),
        child: const Icon(Icons.camera_alt, color: navyBlue, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      
      // --- The Bottom Navigation Bar ---
      bottomNavigationBar: BottomAppBar(
        color: darkSlate,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Tab 0: Settings
              _buildTabItem(icon: Icons.settings, index: 0, label: 'Settings'),
              
              // Tab 1: Dashboard
              _buildTabItem(icon: Icons.dashboard, index: 1, label: 'Stats'),
              
              // Empty space for the docked FAB
              const SizedBox(width: 48), 
              
              // Tab 2: Notifications (With Red Warning Dot)
              Badge(
                isLabelVisible: true, // Controls the red dot visibility
                backgroundColor: neonRed,
                child: _buildTabItem(icon: Icons.notifications, index: 2, label: 'Alerts'),
              ),
              
              // Tab 3: Profile
              _buildTabItem(icon: Icons.person, index: 3, label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({required IconData icon, required int index, required String label}) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? mintGreen : Colors.grey.shade600;

    return InkWell(
      onTap: () => _onTabTapped(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color, 
              fontSize: 10, 
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}