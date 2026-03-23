import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; 
import '../services/audio_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _prepTime = 10;
  int _restTime = 30;
  bool _autoRecord = false;
  
  bool _masterSound = true;
  bool _leadInBeeps = true;
  bool _repChime = true;     // NEW
  bool _metronome = true;    // NEW
  double _volume = 0.5;

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
      _autoRecord = prefs.getBool('auto_record') ?? false;
      
      _masterSound = prefs.getBool('master_sound') ?? true;
      _leadInBeeps = prefs.getBool('leadin_beeps') ?? true;
      _repChime = prefs.getBool('rep_chime') ?? true;       // NEW
      _metronome = prefs.getBool('metronome') ?? true;      // NEW
      _volume = prefs.getDouble('audio_volume') ?? 0.5;
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

          // --- AUDIO SETTINGS ---
          const Text('AUDIO SETTINGS', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  activeColor: mintGreen,
                  title: const Text('Master Audio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Enable all app sounds', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _masterSound,
                  onChanged: (val) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('master_sound', val);
                    setState(() => _masterSound = val);
                    await AudioService.instance.loadSettings();
                  },
                ),
                Divider(color: Colors.grey.withOpacity(0.2), height: 1),
                SwitchListTile(
                  activeColor: mintGreen,
                  title: const Text('Rep Completion Chime', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Plays when a rep is successfully counted', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _repChime,
                  onChanged: !_masterSound ? null : (val) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('rep_chime', val);
                    setState(() => _repChime = val);
                    await AudioService.instance.loadSettings();
                  },
                ),
                Divider(color: Colors.grey.withOpacity(0.2), height: 1),
                SwitchListTile(
                  activeColor: mintGreen,
                  title: const Text('Duration Metronome', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Ticks every second during timed holds', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _metronome,
                  onChanged: !_masterSound ? null : (val) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('metronome', val);
                    setState(() => _metronome = val);
                    await AudioService.instance.loadSettings();
                  },
                ),
                Divider(color: Colors.grey.withOpacity(0.2), height: 1),
                SwitchListTile(
                  activeColor: mintGreen,
                  title: const Text('Lead-In Beeps', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('3-second countdown before a set begins', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _leadInBeeps,
                  onChanged: !_masterSound ? null : (val) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('leadin_beeps', val);
                    setState(() => _leadInBeeps = val);
                    await AudioService.instance.loadSettings();
                  },
                ),
                Divider(color: Colors.grey.withOpacity(0.2), height: 1),
                ListTile(
                  enabled: _masterSound,
                  leading: const Icon(Icons.volume_up, color: mintGreen),
                  title: const Text('App Volume', style: TextStyle(color: Colors.white)),
                  subtitle: Slider(
                    activeColor: mintGreen,
                    inactiveColor: navyBlue,
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    onChanged: !_masterSound ? null : (val) {
                      setState(() => _volume = val);
                    },
                    onChangeEnd: (val) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setDouble('audio_volume', val);
                      await AudioService.instance.loadSettings();
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // --- APP PREFERENCES ---
          const Text('APP PREFERENCES', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
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