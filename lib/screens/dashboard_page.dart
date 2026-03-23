import 'package:flutter/material.dart';
import '../main.dart'; 
import 'session_setup_page.dart'; 

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key}); // CLEANED

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final int _weeklySessions = 0; 
  final double _averageFormScore = 0.0; 
  final String _focusMuscle = "Quadriceps";

  final List<int> _weeklyHeatmap = [0, 0, 0, 0, 0, 0, 0]; 
  final List<String> _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Widget _buildGlassCard({required Widget child, double? height, EdgeInsetsGeometry? padding}) {
    return Container(
      height: height,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mintGreen.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHeatmapDay(String day, int intensity, bool isDayZero) {
    Color blockColor;
    if (isDayZero) {
      blockColor = Colors.grey.withOpacity(0.1); 
    } else if (intensity == 0) {
      blockColor = navyBlue;
    } else if (intensity == 1) {
      blockColor = mintGreen.withOpacity(0.4);
    } else {
      blockColor = mintGreen;
    }

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: blockColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: intensity == 0 && !isDayZero ? Colors.grey.withOpacity(0.2) : Colors.transparent),
          ),
        ),
        const SizedBox(height: 8),
        Text(day, style: TextStyle(color: isDayZero ? Colors.grey.withOpacity(0.5) : Colors.grey, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDayZero = _weeklySessions == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics'), centerTitle: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGlassCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Avg Form Score', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        isDayZero ? '--%' : '${(_averageFormScore * 100).toInt()}%',
                        style: TextStyle(color: isDayZero ? Colors.grey : Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: isDayZero ? Colors.grey.withOpacity(0.1) : mintGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          isDayZero ? 'Awaiting Data' : '+2% this week', 
                          style: TextStyle(color: isDayZero ? Colors.grey : mintGreen, fontSize: 12, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 100, width: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: isDayZero ? 1.0 : _averageFormScore,
                          strokeWidth: 8, backgroundColor: navyBlue, color: isDayZero ? Colors.grey.withOpacity(0.2) : mintGreen,
                        ),
                        Center(child: Icon(isDayZero ? Icons.query_stats : Icons.analytics, color: isDayZero ? Colors.grey.withOpacity(0.5) : mintGreen, size: 40)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Weekly Consistency', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('$_weeklySessions Sessions', style: TextStyle(color: isDayZero ? Colors.grey : mintGreen, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (index) => _buildHeatmapDay(_days[index], _weeklyHeatmap[index], isDayZero)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (isDayZero) ...[
              _buildGlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: mintGreen.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.power_settings_new, size: 48, color: mintGreen),
                    ),
                    const SizedBox(height: 16),
                    const Text('No Data Found', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Your biometric tracking is offline. Start a session to calibrate the AI and begin logging your form data.', 
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.4)
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: mintGreen, foregroundColor: navyBlue, minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 8,
                      ),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionSetupPage())); // CLEANED
                      },
                      child: const Text('INITIATE FIRST SESSION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Text('LATEST SESSION', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              _buildGlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: navyBlue, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.fitness_center, color: Colors.white),
                  ),
                  title: const Text('Lower Body Power', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('Primary Focus: $_focusMuscle\n45 mins • 3 PRA Warnings', style: const TextStyle(color: Colors.grey, height: 1.4)),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {},
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}