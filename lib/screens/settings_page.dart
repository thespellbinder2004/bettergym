import 'package:flutter/material.dart';
import '../main.dart'; // Inherit global colors

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Mock states for the UI
  bool _voiceFeedback = true;
  bool _metricUnits = true;
  String _cameraResolution = 'Medium (720p)';
  final TextEditingController _ipController = TextEditingController(text: '192.168.100.14');

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: mintGreen.withOpacity(0.8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Preferences'),
          _buildCard(
            children: [
              SwitchListTile(
                title: const Text('Voice Feedback', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Real-time form correction audio', style: TextStyle(color: Colors.grey, fontSize: 12)),
                activeColor: mintGreen,
                value: _voiceFeedback,
                onChanged: (val) => setState(() => _voiceFeedback = val),
              ),
              const Divider(color: navyBlue, height: 1),
              SwitchListTile(
                title: const Text('Use Metric Units', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Toggle between kg/cm and lbs/in', style: TextStyle(color: Colors.grey, fontSize: 12)),
                activeColor: mintGreen,
                value: _metricUnits,
                onChanged: (val) => setState(() => _metricUnits = val),
              ),
            ],
          ),

          _buildSectionHeader('Hardware & ML Kit'),
          _buildCard(
            children: [
              ListTile(
                title: const Text('Camera Resolution', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Lower resolution saves battery and reduces thermal throttling.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: DropdownButton<String>(
                  dropdownColor: navyBlue,
                  value: _cameraResolution,
                  style: const TextStyle(color: mintGreen),
                  underline: const SizedBox(),
                  items: ['Low (480p)', 'Medium (720p)', 'High (1080p)']
                      .map((res) => DropdownMenuItem(value: res, child: Text(res)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _cameraResolution = val);
                  },
                ),
              ),
            ],
          ),

          _buildSectionHeader('Server Routing (Dev)'),
          _buildCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _ipController,
                  style: const TextStyle(color: mintGreen, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'Local API IP Address',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    icon: Icon(Icons.router, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}