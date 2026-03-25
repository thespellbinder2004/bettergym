import 'package:flutter/material.dart';
import '../main.dart';
import 'session_setup_page.dart';

class SessionSummaryPage extends StatelessWidget {
  final bool isCompleted;
  final int formBreaks;
  final int completedExercises;
  final int totalExercises;

  const SessionSummaryPage({
    super.key, 
    required this.isCompleted,
    required this.formBreaks,
    required this.completedExercises,
    required this.totalExercises,
  });

  String _calculateGrade() {
    if (completedExercises == 0) return "N/A";
    
    // Calculate an average of form breaks per exercise
    double breaksPerExercise = formBreaks / completedExercises;

    if (breaksPerExercise == 0) return "S"; // Flawless
    if (breaksPerExercise <= 1.0) return "A";
    if (breaksPerExercise <= 2.5) return "B";
    if (breaksPerExercise <= 4.0) return "C";
    return "D";
  }

  Color _getGradeColor(String grade) {
    switch (grade) {
      case "S": return Colors.purpleAccent;
      case "A": return mintGreen;
      case "B": return Colors.blueAccent;
      case "C": return Colors.orangeAccent;
      case "D": return neonRed;
      default: return Colors.grey;
    }
  }

  String _getFeedbackText(String grade) {
    if (!isCompleted) return "Session aborted early. Rest up and try again.";
    switch (grade) {
      case "S": return "Biomechanical perfection. Not a single form break.";
      case "A": return "Excellent session. Form was consistently solid.";
      case "B": return "Good work. A few form breaks, but overall strong.";
      case "C": return "You got it done, but form degraded. Lower the target next time.";
      case "D": return "Form was highly unstable. Focus on technique over volume.";
      default: return "Session complete.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final String grade = _calculateGrade();
    final Color gradeColor = _getGradeColor(grade);

    return Scaffold(
      backgroundColor: navyBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- HEADER ---
              Text(
                isCompleted ? "SESSION COMPLETE" : "SESSION ABORTED",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isCompleted ? mintGreen : neonRed,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 48),

              // --- THE GRADE BADGE ---
              Center(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: darkSlate,
                    border: Border.all(color: gradeColor, width: 6),
                    boxShadow: [
                      BoxShadow(color: gradeColor.withOpacity(0.3), blurRadius: 30, spreadRadius: 5),
                    ]
                  ),
                  child: Center(
                    child: Text(
                      grade,
                      style: TextStyle(
                        color: gradeColor,
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // --- DYNAMIC FEEDBACK ---
              Text(
                _getFeedbackText(grade),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 48),

              // --- TELEMETRY GRID ---
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: "PROGRESS",
                      value: "$completedExercises / $totalExercises",
                      icon: Icons.checklist,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      title: "FORM BREAKS",
                      value: formBreaks.toString(),
                      icon: Icons.warning_amber_rounded,
                      color: formBreaks == 0 ? mintGreen : neonRed,
                    ),
                  ),
                ],
              ),
              
              const Spacer(),

              // --- EXIT BUTTON ---
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: mintGreen,
                  foregroundColor: navyBlue,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.home, size: 28),
                label: const Text("RETURN TO SETUP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const SessionSetupPage()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}