import 'package:flutter/material.dart';
import '../main.dart';
import 'session_setup_page.dart';
import 'main_layout.dart';
import 'progress_report_page.dart'; // Import the new dummy page

// --- THE TELEMETRY DATA MODEL ---
class ExerciseTelemetry {
  final String name;
  final bool isDuration;
  final int target;
  int goodReps = 0;
  int badReps = 0;
  List<double> repScores = []; 

  ExerciseTelemetry({required this.name, required this.isDuration, required this.target});

  int get finalScore {
    if (repScores.isEmpty) return 0;
    double sum = repScores.fold(0, (p, c) => p + c);
    return ((sum / repScores.length) * 100).round();
  }
}

class SessionSummaryPage extends StatelessWidget {
  final bool isCompleted;
  final List<ExerciseTelemetry> telemetryData;
  final Duration totalDuration;

  const SessionSummaryPage({
    super.key, 
    required this.isCompleted,
    required this.telemetryData,
    required this.totalDuration,
  });

  int _calculateGlobalScore() {
    if (telemetryData.isEmpty) return 0;
    final attemptedSets = telemetryData.where((t) => t.repScores.isNotEmpty).toList();
    if (attemptedSets.isEmpty) return 0;

    int totalScore = attemptedSets.fold(0, (sum, set) => sum + set.finalScore);
    return (totalScore / attemptedSets.length).round();
  }

  int _calculateTotalVolume() {
    return telemetryData.fold(0, (sum, set) => sum + set.goodReps);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) return "${d.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Color _getScoreColor(int score) {
    if (score > 75) return mintGreen;
    if (score > 50) return Colors.orangeAccent;
    return neonRed;
  }

  @override
  Widget build(BuildContext context) {
    final int globalScore = _calculateGlobalScore();
    final Color scoreColor = _getScoreColor(globalScore);
    
    final int totalSets = telemetryData.length;
    final int attemptedSets = telemetryData.where((t) => t.repScores.isNotEmpty).length;
    final int completedSets = isCompleted ? totalSets : (attemptedSets > 0 ? attemptedSets - 1 : 0);

    return Scaffold(
      backgroundColor: navyBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- HEADER ---
              Text(
                isCompleted ? "SESSION COMPLETE" : "SESSION ABORTED",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isCompleted ? mintGreen : Colors.orangeAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 48),

              Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: navyBlue, 
                    border: Border.all(color: scoreColor, width: 8),
                    boxShadow: [
                      BoxShadow(
                        color: scoreColor.withOpacity(0.6), 
                        blurRadius: 40, 
                        spreadRadius: 10
                      ),
                    ]
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          globalScore.toString(),
                          style: TextStyle(
                            color: scoreColor,
                            fontSize: 80,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            shadows: [Shadow(color: scoreColor.withOpacity(0.5), blurRadius: 20)]
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text("SCORE", style: TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 3.0, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 64),

              // --- TELEMETRY GRID (Spaced & Scaled properly) ---
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: "SETS",
                      value: "$completedSets / $totalSets",
                      icon: Icons.layers,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      title: "VOLUME",
                      value: _calculateTotalVolume().toString(),
                      icon: Icons.fitness_center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                title: "TOTAL DURATION",
                value: _formatDuration(totalDuration),
                icon: Icons.timer,
                isWide: true,
              ),
              
              const Spacer(),

              // --- DYNAMIC DUAL NAVIGATION ---
              if (!isCompleted) ...[
                // ABORTED STATE ROUTING
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen,
                    foregroundColor: navyBlue,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const SessionSetupPage()), (route) => false);
                  },
                  child: const Text("RETURN TO SETUP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade700, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainLayout()), (route) => false);
                  },
                  child: const Text("DASHBOARD", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
              ] else ...[
                // COMPLETED STATE ROUTING
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen,
                    foregroundColor: navyBlue,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgressReportPage()));
                  },
                  child: const Text("PROGRESS REPORT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade700, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainLayout()), (route) => false);
                  },
                  child: const Text("DASHBOARD", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  // Adjusted Stat Card to prevent text clipping
  Widget _buildStatCard({required String title, required String value, required IconData icon, bool isWide = false}) {
    return Container(
      padding: EdgeInsets.all(isWide ? 24 : 20),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: mintGreen, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 12),
          // FittedBox ensures the numbers automatically shrink instead of overflowing the container
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}