import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _prepTime = 10;
  int _restTime = 30;
  bool _isLoading = true;

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
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Widget _buildSliderSetting({
    required String title,
    required String keyName,
    required int currentValue,
    required int maxLimit,
    required Function(int) onChanged,
  }) {
    TextEditingController controller = TextEditingController(text: currentValue.toString());
    double sliderValue = currentValue.toDouble().clamp(1.0, maxLimit.toDouble());

    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: darkSlate,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: mintGreen,
                        inactiveTrackColor: Colors.grey.shade800,
                        thumbColor: Colors.white,
                        overlayColor: mintGreen.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: sliderValue,
                        min: 1,
                        max: maxLimit.toDouble(),
                        divisions: maxLimit - 1,
                        onChanged: (val) {
                          setInnerState(() {
                            sliderValue = val;
                            controller.text = val.toInt().toString();
                          });
                          onChanged(val.toInt());
                          _saveSetting(keyName, val.toInt());
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: mintGreen)),
                      ),
                      onChanged: (val) {
                        int? parsed = int.tryParse(val);
                        if (parsed != null) {
                          setInnerState(() {
                            sliderValue = parsed.toDouble().clamp(1.0, maxLimit.toDouble());
                          });
                          onChanged(parsed);
                          _saveSetting(keyName, parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text("sec", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
        );
      }
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
        backgroundColor: navyBlue,
        title: const Text('SETTINGS', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSliderSetting(
            title: "Preparation Time",
            keyName: "prep_time",
            currentValue: _prepTime,
            maxLimit: 60, // Max 60 seconds prep
            onChanged: (val) => _prepTime = val,
          ),
          const SizedBox(height: 16),
          _buildSliderSetting(
            title: "Rest Time Between Sets",
            keyName: "rest_time",
            currentValue: _restTime,
            maxLimit: 180, // Max 3 minutes rest
            onChanged: (val) => _restTime = val,
          ),
        ],
      ),
    );
  }
}