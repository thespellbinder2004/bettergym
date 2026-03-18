import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; // Inherit global colors

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _prepTime = 10;
  int _restTime = 30;
  bool _audioCues = true;
  bool _autoRecord = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prepTime = prefs.getInt('prep_time') ?? 10;
      _restTime = prefs.getInt('rest_time') ?? 30;
      _audioCues = prefs.getBool('audio_cues') ?? true;
      _autoRecord = prefs.getBool('auto_record') ?? false;
    });
  }

  Future<void> _updatePrepTime(int? newValue) async {
    if (newValue == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('prep_time', newValue);
    setState(() => _prepTime = newValue);
  }

  Future<void> _updateRestTime(int? newValue) async {
    if (newValue == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rest_time', newValue);
    setState(() => _restTime = newValue);
  }

  Future<void> _toggleBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    setState(() {
      if (key == 'audio_cues') _audioCues = value;
      if (key == 'auto_record') _autoRecord = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- TIMERS ---
          const Text('SESSION TIMERS', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timer, color: mintGreen),
                  title: const Text('Preparation Time', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Countdown before first exercise', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: DropdownButton<int>(
                    value: _prepTime,
                    dropdownColor: navyBlue,
                    style: const TextStyle(color: mintGreen, fontWeight: FontWeight.bold),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 sec')),
                      DropdownMenuItem(value: 10, child: Text('10 sec')),
                      DropdownMenuItem(value: 15, child: Text('15 sec')),
                    ],
                    onChanged: _updatePrepTime,
                  ),
                ),
                Divider(color: Colors.grey.withOpacity(0.2), height: 1),
                ListTile(
                  leading: const Icon(Icons.hourglass_bottom, color: mintGreen),
                  title: const Text('Rest Duration', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Break between exercises', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: DropdownButton<int>(
                    value: _restTime,
                    dropdownColor: navyBlue,
                    style: const TextStyle(color: mintGreen, fontWeight: FontWeight.bold),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 sec')),
                      DropdownMenuItem(value: 30, child: Text('30 sec')),
                      DropdownMenuItem(value: 45, child: Text('45 sec')),
                      DropdownMenuItem(value: 60, child: Text('60 sec')),
                    ],
                    onChanged: _updateRestTime,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          // --- PREFERENCES ---
          const Text('APP PREFERENCES', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  activeColor: mintGreen,
                  title: const Text('Audio Cues', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Voice feedback for form correction', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _audioCues,
                  onChanged: (val) => _toggleBool('audio_cues', val),
                ),
                Divider(color: Colors.grey.withOpacity(0.2), height: 1),
                SwitchListTile(
                  activeColor: mintGreen,
                  title: const Text('Auto-Record Sessions', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Save video to device for review', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _autoRecord,
                  onChanged: (val) => _toggleBool('auto_record', val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}