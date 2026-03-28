import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import 'main_layout.dart';
import 'session_summary_page.dart';

class ProgressReportPage extends StatelessWidget {
  final List<ExerciseTelemetry> telemetryData;
  final int globalScore;
  final Duration totalDuration;

  const ProgressReportPage({
    super.key,
    required this.telemetryData,
    required this.globalScore,
    required this.totalDuration,
  });

  int _calculateTotalBadReps() {
    return telemetryData.fold(0, (sum, set) => sum + set.badReps);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  String _formatTimeString(int totalSeconds) {
    if (totalSeconds == 0) return "0s";
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    if (m > 0 && s > 0) return "${m}m ${s}s";
    if (m > 0) return "${m}m";
    return "${s}s";
  }

  @override
  Widget build(BuildContext context) {
    final attemptedSets = telemetryData.where((t) => t.repScores.isNotEmpty || (t.isDuration && t.goodReps > 0)).toList();

    return Scaffold(
      backgroundColor: navyBlue,
      appBar: AppBar(
        backgroundColor: navyBlue,
        elevation: 0,
        title: const Text('SESSION DEBRIEF', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMacroStat("SCORE", globalScore.toString(), globalScore > 75 ? mintGreen : Colors.orange),
                _buildMacroStat("TIME", _formatDuration(totalDuration), Colors.white),
                _buildMacroStat("BAD REPS", _calculateTotalBadReps().toString(), neonRed),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: attemptedSets.length,
              itemBuilder: (context, index) {
                return _buildExerciseCard(attemptedSets[index]);
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: mintGreen,
                foregroundColor: navyBlue,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.dashboard),
              label: const Text("RETURN TO DASHBOARD", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              onPressed: () {
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainLayout()), (route) => false);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMicroStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildExerciseCard(ExerciseTelemetry ex) {
    final int totalVolume = ex.goodReps + ex.badReps;
    
    // --- 1. LOGIC FOR SUGGESTION #2: GOLDEN REP ---
    int goldenRepIndex = -1;
    double maxScore = -1.0;
    if (!ex.isDuration && ex.repScores.isNotEmpty) {
      for (int i = 0; i < ex.repScores.length; i++) {
        if (ex.repScores[i] > maxScore) {
          maxScore = ex.repScores[i];
          goldenRepIndex = i + 1;
        }
      }
    }

    // --- 2. LOGIC FOR SUGGESTION #5: DYNAMIC FAULT SUMMARY ---
    String faultAnalysis = "Form was stable. Maintain this intensity.";
    if (ex.badReps > 0) {
      final name = ex.name.toLowerCase();
      if (name.contains("push")) faultAnalysis = "Primary issue: Hip sagging or incomplete lockout.";
      else if (name.contains("squat")) faultAnalysis = "Primary issue: Insufficient depth or knee cave.";
      else if (name.contains("plank")) faultAnalysis = "Primary issue: Core instability or pelvic tilt.";
      else faultAnalysis = "Primary issue: Momentum usage or limited range of motion.";
    }

    int? failurePoint;
    for (int i = 0; i < ex.repScores.length; i++) {
      if (ex.repScores[i] < 0.6) {
        failurePoint = i + 1;
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: mintGreen,
          collapsedIconColor: Colors.grey,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Text(ex.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          subtitle: Text("Avg Score: ${ex.finalScore}%", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          trailing: SizedBox(
            width: 60,
            height: 60,
            child: CustomPaint(
              painter: RatioRingPainter(good: ex.goodReps, bad: ex.badReps),
              child: Center(
                child: Text(
                  ex.isDuration ? _formatTimeString(totalVolume) : "${ex.goodReps}/$totalVolume",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ),
          children: [
            // Micro Stats Row
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 16.0, left: 16.0, right: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMicroStat(ex.isDuration ? "TOTAL TIME" : "TOTAL REPS", ex.isDuration ? _formatTimeString(totalVolume) : totalVolume.toString(), Colors.white),
                  _buildMicroStat(ex.isDuration ? "GOOD FORM" : "CLEAN REPS", ex.isDuration ? _formatTimeString(ex.goodReps) : ex.goodReps.toString(), mintGreen),
                  _buildMicroStat(ex.isDuration ? "BAD FORM" : "BAD REPS", ex.isDuration ? _formatTimeString(ex.badReps) : ex.badReps.toString(), neonRed),
                ],
              ),
            ),

            // --- NEW: AI ANALYSIS SECTION ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined, color: mintGreen, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(faultAnalysis, style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic))),
                      ],
                    ),
                    if (goldenRepIndex != -1 && maxScore > 0.8) ...[
                      const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(color: Colors.white10)),
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
                          const SizedBox(width: 8),
                          Text("Golden Rep: #$goldenRepIndex (${(maxScore * 100).toInt()}%)", style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
            ),

            // Graph Section
            if (ex.repScores.length > 1) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 32.0),
                child: SizedBox(
                  height: 120,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1)),
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)))),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 1, maxX: ex.repScores.length.toDouble(),
                      minY: 0, maxY: 1.0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: ex.repScores.asMap().entries.map((e) => FlSpot((e.key + 1).toDouble(), e.value)).toList(),
                          isCurved: true, color: mintGreen, barWidth: 3, isStrokeCapRound: true,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(show: true, color: mintGreen.withOpacity(0.1)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              if (failurePoint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: neonRed, size: 16),
                      const SizedBox(width: 8),
                      Text("Form breakdown detected at ${ex.isDuration ? 'Second' : 'Rep'} $failurePoint", style: const TextStyle(color: neonRed, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else 
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text("Form maintained throughout ${ex.isDuration ? 'duration' : 'set'}.", style: const TextStyle(color: mintGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ] else ...[
               const Padding(
                padding: EdgeInsets.only(bottom: 16.0),
                child: Text("Not enough data to generate fatigue curve.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
              )
            ],
          ],
        ),
      ),
    );
  }
}

class RatioRingPainter extends CustomPainter {
  final int good;
  final int bad;

  RatioRingPainter({required this.good, required this.bad});

  @override
  void paint(Canvas canvas, Size size) {
    int total = good + bad;
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 4; 
    final strokeWidth = 6.0;

    final rect = Rect.fromCircle(center: center, radius: radius);
    
    const startAngle = -pi / 2;
    final greenSweep = (good / total) * 2 * pi;
    final redSweep = (bad / total) * 2 * pi;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (bad > 0) {
      paint.color = neonRed;
      canvas.drawArc(rect, startAngle + greenSweep, redSweep, false, paint);
    }

    if (good > 0) {
      paint.color = mintGreen;
      canvas.drawArc(rect, startAngle, greenSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}