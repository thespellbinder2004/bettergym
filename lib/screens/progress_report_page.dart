import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import 'main_layout.dart';
import 'session_summary_page.dart'; // To access ExerciseTelemetry

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
          // --- MACRO STATS ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMacroStat("SCORE", globalScore.toString(), globalScore > 75 ? mintGreen : Colors.orange),
                _buildMacroStat("TIME", _formatDuration(totalDuration), Colors.white),
                _buildMacroStat("SLOP", _calculateTotalBadReps().toString(), neonRed),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          
          // --- MICRO STATS (The Expandable Cards) ---
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: attemptedSets.length,
              itemBuilder: (context, index) {
                return _buildExerciseCard(attemptedSets[index]);
              },
            ),
          ),

          // --- FOOTER NAVIGATION ---
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

  Widget _buildExerciseCard(ExerciseTelemetry ex) {
    final int totalReps = ex.goodReps + ex.badReps;
    
    // Find the exact point of failure (score drops below 0.6)
    int? failurePoint;
    if (!ex.isDuration) {
      for (int i = 0; i < ex.repScores.length; i++) {
        if (ex.repScores[i] < 0.6) {
          failurePoint = i + 1; // 1-indexed for the user
          break;
        }
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
        // Hides the ugly default dividers of ExpansionTile
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: mintGreen,
          collapsedIconColor: Colors.grey,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          
          // --- COLLAPSED VIEW (Header) ---
          title: Text(ex.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          subtitle: Text("Avg Score: ${ex.finalScore}", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          trailing: SizedBox(
            width: 60,
            height: 60,
            child: ex.isDuration 
                ? _buildDurationRing(ex) 
                : CustomPaint(
                    painter: RatioRingPainter(good: ex.goodReps, bad: ex.badReps),
                    child: Center(
                      child: Text(
                        "${ex.goodReps}/$totalReps",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
          ),
          
          // --- EXPANDED VIEW (Graph & Failure Point) ---
          children: [
            if (ex.isDuration)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Fatigue tracking is not applied to static holds.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
              )
            else if (ex.repScores.length > 1) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16.0, bottom: 8.0, left: 16.0, right: 32.0),
                child: SizedBox(
                  height: 120,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1)),
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)))),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Hide Y axis numbers to stay clean
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 1, maxX: ex.repScores.length.toDouble(),
                      minY: 0, maxY: 1.0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: ex.repScores.asMap().entries.map((e) => FlSpot((e.key + 1).toDouble(), e.value)).toList(),
                          isCurved: true,
                          color: mintGreen,
                          barWidth: 3,
                          isStrokeCapRound: true,
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
                      Text("Form breakdown detected at Rep $failurePoint", style: const TextStyle(color: neonRed, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else 
                const Padding(
                  padding: EdgeInsets.only(bottom: 16.0),
                  child: Text("Form maintained throughout set.", style: TextStyle(color: mintGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ] else ...[
               const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Not enough reps to generate fatigue curve.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
              )
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDurationRing(ExerciseTelemetry ex) {
    // For planks, we just show a solid green ring if they completed it
    return CustomPaint(
      painter: RatioRingPainter(good: 1, bad: 0), // Full green
      child: const Center(
        child: Icon(Icons.timer, color: Colors.white, size: 20),
      ),
    );
  }
}

// --- CUSTOM PAINTER FOR THE RED/GREEN RING ---
class RatioRingPainter extends CustomPainter {
  final int good;
  final int bad;

  RatioRingPainter({required this.good, required this.bad});

  @override
  void paint(Canvas canvas, Size size) {
    int total = good + bad;
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 4; // 4px padding
    final strokeWidth = 6.0;

    final rect = Rect.fromCircle(center: center, radius: radius);
    
    // Start drawing from the top (-pi / 2)
    const startAngle = -pi / 2;
    final greenSweep = (good / total) * 2 * pi;
    final redSweep = (bad / total) * 2 * pi;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw Red Arc First (Underneath/Background)
    if (bad > 0) {
      paint.color = neonRed;
      canvas.drawArc(rect, startAngle + greenSweep, redSweep, false, paint);
    }

    // Draw Green Arc Second
    if (good > 0) {
      paint.color = mintGreen;
      canvas.drawArc(rect, startAngle, greenSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}