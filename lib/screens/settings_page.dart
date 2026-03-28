import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/api_services.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _prepTime = 30;
  int _restTime = 30;
  bool _voiceEnabled = true;
  double _feedbackVolume = 1.0;
  double _beepsVolume = 1.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prepTime = prefs.getInt('prep_time') ?? 30;
      _restTime = prefs.getInt('rest_time') ?? 30;
      _voiceEnabled = prefs.getBool('voice_enabled') ?? true;
      _feedbackVolume = prefs.getDouble('feedback_volume') ?? 1.0;
      _beepsVolume = prefs.getDouble('beeps_volume') ?? 1.0;
      _isLoading = false;
    });
  }

  Future<void> _saveIntSetting(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);   // 1. Saves to the phone
    _syncSettingsToCloud();           // 2. Trips the wire to tell XAMPP
  }

  Future<void> _saveBoolSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);  // 1. Saves to the phone
    _syncSettingsToCloud();           // 2. Trips the wire to tell XAMPP
  }

  Future<void> _saveDoubleSetting(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value); // 1. Saves to the phone
    _syncSettingsToCloud();            // 2. Trips the wire to tell XAMPP
  }

  String _formatTime(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  // --- DUAL-COLUMN TUMBLER FOR MM:SS ---
  void _showDualColumnPicker({
    required String title,
    required int currentSeconds,
    required Function(int) onSelected,
  }) {
    int tempMinutes = currentSeconds ~/ 60;
    int tempSeconds = currentSeconds % 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: darkSlate,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SizedBox(
          height: 320, // Increased height to accommodate headers and bigger spinners
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
                    ),
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    TextButton(
                      onPressed: () {
                        int finalSeconds = (tempMinutes * 60) + tempSeconds;
                        if (title == "REST TIME" && finalSeconds == 0) finalSeconds = 1; 
                        onSelected(finalSeconds);
                        Navigator.pop(context);
                      },
                      child: const Text("SAVE", style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              
              // NEW: Clean, anchored column headers
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(child: Text("MINUTES", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                    SizedBox(width: 24), // Spacer for the colon
                    Expanded(child: Text("SECONDS", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(pickerTextStyle: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)), // Increased font size
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: tempMinutes),
                          itemExtent: 60, // Increased touch target height
                          onSelectedItemChanged: (idx) => tempMinutes = idx,
                          children: List.generate(10, (idx) => Center(child: Text(idx.toString().padLeft(2, '0')))), // Numbers only
                        ),
                      ),
                      const Text(":", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: tempSeconds),
                          itemExtent: 60, // Increased touch target height
                          onSelectedItemChanged: (idx) => tempSeconds = idx,
                          children: List.generate(60, (idx) => Center(child: Text(idx.toString().padLeft(2, '0')))), // Numbers only
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: navyBlue, body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    return Scaffold(
      backgroundColor: navyBlue,
      appBar: AppBar(
        automaticallyImplyLeading: false, // REMOVES THE BACK BUTTON
        backgroundColor: navyBlue,
        title: const Text('SETTINGS', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- AUDIO CONTROLS (SPLIT MIXER) ---
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8, top: 8),
            child: Text("AUDIO", style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
          Container(
            decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Voice Feedback", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text("AI form corrections and cadence", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  activeThumbColor: mintGreen,
                  value: _voiceEnabled,
                  onChanged: (val) {
                    setState(() => _voiceEnabled = val);
                    _saveBoolSetting('voice_enabled', val);
                  },
                ),
                const Divider(color: Colors.grey, height: 1),
                ListTile(
                  title: const Text("Feedback Volume", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: mintGreen, inactiveTrackColor: Colors.grey.shade800, thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _feedbackVolume, min: 0.0, max: 1.0,
                      onChanged: (val) => setState(() => _feedbackVolume = val),
                      onChangeEnd: (val) => _saveDoubleSetting('feedback_volume', val),
                    ),
                  ),
                  trailing: Icon(_feedbackVolume == 0 ? Icons.volume_off : Icons.record_voice_over, color: mintGreen, size: 20),
                ),
                const Divider(color: Colors.grey, height: 1),
                ListTile(
                  title: const Text("Beeps Volume", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.blueAccent, inactiveTrackColor: Colors.grey.shade800, thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _beepsVolume, min: 0.0, max: 1.0,
                      onChanged: (val) => setState(() => _beepsVolume = val),
                      onChangeEnd: (val) => _saveDoubleSetting('beeps_volume', val),
                    ),
                  ),
                  trailing: Icon(_beepsVolume == 0 ? Icons.notifications_off : Icons.notifications_active, color: Colors.blueAccent, size: 20),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // --- TIMER CONTROLS (MM:SS) ---
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Text("TIMERS", style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
          Container(
            decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  title: const Text("Preparation Time", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Countdown before exercise starts", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Text(_formatTime(_prepTime), style: const TextStyle(color: mintGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                  onTap: () {
                    _showDualColumnPicker(
                      title: "PREP TIME",
                      currentSeconds: _prepTime,
                      onSelected: (val) {
                        setState(() => _prepTime = val);
                        _saveIntSetting('prep_time', val);
                      }
                    );
                  },
                ),
                const Divider(color: Colors.grey, height: 1),
                ListTile(
                  title: const Text("Rest Time", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Cooldown between sets", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Text(_formatTime(_restTime), style: const TextStyle(color: mintGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                  onTap: () {
                    _showDualColumnPicker(
                      title: "REST TIME",
                      currentSeconds: _restTime,
                      onSelected: (val) {
                        setState(() => _restTime = val);
                        _saveIntSetting('rest_time', val);
                      }
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- CLOUD SYNC TRIGGER ---
  void _syncSettingsToCloud() {
    ApiService.pushSettings(
      prepTime: _prepTime,
      restTime: _restTime,
      voiceEnabled: _voiceEnabled,
      feedbackVolume: _feedbackVolume,
      beepsVolume: _beepsVolume,
    );
  }
  
}