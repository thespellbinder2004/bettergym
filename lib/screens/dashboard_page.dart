import 'package:flutter/material.dart';
import '../main.dart'; // Inherit global colors

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Mock Data
  final double _averageFormScore = 0.88; // 88%
  final String _focusMuscle = "Quadriceps";
  final int _weeklySessions = 4;

  // Mock heatmap data (0 = no activity, 1 = light, 2 = heavy)
  final List<int> _weeklyHeatmap = [0, 2, 1, 0, 2, 0, 0]; 
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

  Widget _buildHeatmapDay(String day, int intensity) {
    Color blockColor;
    if (intensity == 0) blockColor = navyBlue;
    else if (intensity == 1) blockColor = mintGreen.withOpacity(0.4);
    else blockColor = mintGreen;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: blockColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: intensity == 0 ? Colors.grey.withOpacity(0.2) : Colors.transparent),
          ),
        ),
        const SizedBox(height: 8),
        Text(day, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              // TODO: Trigger API fetch to refresh dashboard data
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing biomechanical data...'), backgroundColor: darkSlate),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- HERO STAT: Average Form Score ---
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
                        '${(_averageFormScore * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: mintGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('+2% this week', style: TextStyle(color: mintGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 100,
                    width: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: _averageFormScore,
                          strokeWidth: 8,
                          backgroundColor: navyBlue,
                          color: mintGreen,
                        ),
                        const Center(
                          child: Icon(Icons.analytics, color: mintGreen, size: 40),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- WEEKLY HEATMAP ---
            _buildGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Weekly Consistency', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('$_weeklySessions Sessions', style: const TextStyle(color: mintGreen, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (index) => _buildHeatmapDay(_days[index], _weeklyHeatmap[index])),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- RECENT SESSION SUMMARY ---
            const Text(
              'LATEST SESSION',
              style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            _buildGlassCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: navyBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fitness_center, color: Colors.white),
                ),
                title: const Text('Lower Body Power', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Primary Focus: $_focusMuscle\n45 mins • 3 PRA Warnings', style: const TextStyle(color: Colors.grey, height: 1.4)),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  // TODO: Navigate to Frame 9 (Progress Report) for this specific session
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}