import 'package:flutter/material.dart';

import '../main.dart'; 
import 'dashboard_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'session_setup_page.dart';
import 'settings_page.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 1; 

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      SettingsPage(),
      DashboardPage(), 
      NotificationsPage(),
      ProfilePage(),   
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _pages[_currentIndex],
      ),
      floatingActionButton: SizedBox(
        height: 72, 
        width: 72,  
        child: FloatingActionButton(
          backgroundColor: mintGreen,
          elevation: 12, 
          shape: CircleBorder(
            side: BorderSide(color: mintGreen.withOpacity(0.5), width: 2), 
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SessionSetupPage(),
                fullscreenDialog: true, 
              ),
            );
          },
          child: const Icon(Icons.camera_alt, color: navyBlue, size: 36), 
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      
      bottomNavigationBar: BottomAppBar(
        color: darkSlate,
        shape: const CircularNotchedRectangle(),
        notchMargin: 10.0, 
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabItem(icon: Icons.settings, index: 0, label: 'Settings'),
              _buildTabItem(icon: Icons.dashboard, index: 1, label: 'Stats'),
              const SizedBox(width: 60), 
              Badge(
                isLabelVisible: true, 
                backgroundColor: neonRed,
                child: _buildTabItem(icon: Icons.notifications, index: 2, label: 'Alerts'),
              ),
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