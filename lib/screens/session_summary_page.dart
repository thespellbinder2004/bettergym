import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart'; // Ensure you ran: flutter pub add uuid
import '../main.dart';
import 'session_setup_page.dart';
import 'main_layout.dart';
import 'progress_report_page.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';

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

class SessionSummaryPage extends StatefulWidget {
  final String sessionId;
  final bool isCompleted;
  final List<ExerciseTelemetry> telemetryData;
  final Duration totalDuration;
  final String? routineId;

  const SessionSummaryPage({
    super.key, 
    required this.sessionId,
    required this.isCompleted,
    required this.telemetryData,
    required this.totalDuration,
    this.routineId,
  });

  @override
  State<SessionSummaryPage> createState() => _SessionSummaryPageState();
}

class _SessionSummaryPageState extends State<SessionSummaryPage> {
  bool _isSaving = false;

  int _calculateGlobalScore() {
    if (widget.telemetryData.isEmpty) return 0;
    final attemptedSets = widget.telemetryData.where((t) => t.repScores.isNotEmpty).toList();
    if (attemptedSets.isEmpty) return 0;

    int totalScore = attemptedSets.fold(0, (sum, set) => sum + set.finalScore);
    return (totalScore / attemptedSets.length).round();
  }

  int _calculateTotalVolume() {
    return widget.telemetryData.fold(0, (sum, set) => sum + set.goodReps);
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

  Future<void> _processAndSaveData(VoidCallback navigateAction) async {
    setState(() => _isSaving = true);

    try {
      // 1. We just update the parent record we created in PoseCameraPage
      await LocalDBService.instance.updateSessionCompletion(
        widget.sessionId,
        widget.isCompleted ? 'COMPLETED' : 'ABORTED',
        _calculateGlobalScore(),
        widget.totalDuration.inSeconds,
      );

      // 2. Fire the Cloud Cannon (Does not await, runs in background)
      SyncService.pushUnsyncedData();

      // 3. Navigate away
      navigateAction();

    } catch (e) {
      debugPrint("Critical Save Error: $e");
      navigateAction(); 
    }
  }

  @override
  Widget build(BuildContext context) {
    final int globalScore = _calculateGlobalScore();
    final Color scoreColor = _getScoreColor(globalScore);
    
    final int totalSets = widget.telemetryData.length;
    final int attemptedSets = widget.telemetryData.where((t) => t.repScores.isNotEmpty).length;
    final int completedSets = widget.isCompleted ? totalSets : (attemptedSets > 0 ? attemptedSets - 1 : 0);

    return Scaffold(
      backgroundColor: navyBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0), // Reduced vertical padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- HEADER ---
              Text(
                widget.isCompleted ? "SESSION COMPLETE" : "SESSION ABORTED",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.isCompleted ? mintGreen : Colors.orangeAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 24), // Cut down from 48

              // --- THE GLOWING SCORE (Untouched) ---
              Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: navyBlue,
                    border: Border.all(color: scoreColor, width: 8),
                    boxShadow: [
                      BoxShadow(color: scoreColor.withOpacity(0.6), blurRadius: 40, spreadRadius: 10),
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
              const SizedBox(height: 32), // Cut down from 64

              // --- COMPACT TELEMETRY GRID ---
              Row(
                children: [
                  Expanded(child: _buildStatCard(title: "SETS", value: "$completedSets / $totalSets", icon: Icons.layers)),
                  const SizedBox(width: 12), // Tighter horizontal gap
                  Expanded(child: _buildStatCard(title: "TOTAL REPS", value: _calculateTotalVolume().toString(), icon: Icons.fitness_center)),
                ],
              ),
              const SizedBox(height: 12), // Tighter vertical gap
              _buildStatCard(title: "EXERCISE DURATION", value: _formatDuration(widget.totalDuration), icon: Icons.timer, isWide: true),
              
              const Spacer(), // This will now dynamically push the buttons to the bottom without overflowing

              // --- DYNAMIC DUAL NAVIGATION ---
              if (_isSaving)
                const Center(child: CircularProgressIndicator(color: mintGreen))
              else if (!widget.isCompleted) ...[
                // ABORTED STATE ROUTING
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen, foregroundColor: navyBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16), // Slightly tighter buttons
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _processAndSaveData(() {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const SessionSetupPage()), (route) => false);
                  }),
                  child: const Text("RETURN TO SETUP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: BorderSide(color: Colors.grey.shade700, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _processAndSaveData(() {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainLayout()), (route) => false);
                  }),
                  child: const Text("DASHBOARD", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
              ] else ...[
                // COMPLETED STATE ROUTING
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen, foregroundColor: navyBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _processAndSaveData(() {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ProgressReportPage(
                      telemetryData: widget.telemetryData,
                      globalScore: globalScore,
                      totalDuration: widget.totalDuration,
                    )));
                  }),
                  child: const Text("PROGRESS REPORT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: BorderSide(color: Colors.grey.shade700, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _processAndSaveData(() {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainLayout()), (route) => false);
                  }),
                  child: const Text("DASHBOARD", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, bool isWide = false}) {
    return Container(
      padding: const EdgeInsets.all(16), // Slashed padding for a tighter footprint
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(16), // Slightly tighter border radius
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: mintGreen, size: 18), // Shrunk icon slightly
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 8), // Tighter gap before the number
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)), // Shrunk font from 36 to 28
          ),
        ],
      ),
    );
  }
}