import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../main.dart'; 
import 'main_layout.dart';

class ProgressReportPage extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  final int totalScore = 88;
  final int totalDurationMins = 42;
  final int praWarnings = 1;

  const ProgressReportPage({super.key, required this.cameras});

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.0)),
        ],
      ),
    );
  }

  Widget _buildExerciseBreakdown(String name, int total, int correct, int faulty) {
    double correctRatio = total > 0 ? correct / total : 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text('$total Reps', style: const TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$correct Correct', style: const TextStyle(color: mintGreen, fontWeight: FontWeight.bold)),
              Text('$faulty Faulty', style: TextStyle(color: faulty > 0 ? neonRed : Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: correctRatio,
              backgroundColor: neonRed.withOpacity(0.3),
              color: mintGreen,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Analysis'), // Updated
        automaticallyImplyLeading: false, 
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 160,
                        width: 160,
                        child: CircularProgressIndicator(
                          value: totalScore / 100,
                          strokeWidth: 12,
                          backgroundColor: navyBlue,
                          color: totalScore > 80 ? mintGreen : neonRed,
                        ),
                      ),
                      Column(
                        children: [
                          Text('$totalScore%', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                          const Text('FORM SCORE', style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(child: _buildStatCard('DURATION', '${totalDurationMins}m', Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard('WARNINGS', '$praWarnings', praWarnings > 0 ? neonRed : mintGreen)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard('VOLUME', '120', Colors.white)),
                  ],
                ),
                const SizedBox(height: 32),
                if (praWarnings > 0) ...[
                  const Text('PREDICTIVE RISK ASSESSMENT', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: neonRed.withOpacity(0.1),
                      border: Border.all(color: neonRed.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_rounded, color: neonRed),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Knee Valgus Detected', style: TextStyle(color: neonRed, fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text('Form broke down during the last 3 reps of Squats. High risk of patellofemoral strain if this continues.', style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                const Text('EXERCISE BREAKDOWN', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildExerciseBreakdown('Squats', 15, 12, 3),
                _buildExerciseBreakdown('Pushups', 20, 20, 0),
                _buildExerciseBreakdown('Lunges', 24, 18, 6),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: darkSlate,
              border: Border(top: BorderSide(color: mintGreen.withOpacity(0.2))),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: mintGreen,
                foregroundColor: navyBlue,
                minimumSize: const Size.fromHeight(60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => MainLayout(cameras: cameras)),
                  (route) => false, 
                );
              },
              child: const Text('LOG SESSION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)), // Updated
            ),
          ),
        ],
      ),
    );
  }
}