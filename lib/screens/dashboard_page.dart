import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart'; 
import 'session_setup_page.dart'; 
import '../services/local_db_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  
  // 1. BASE DATA STATE
  Map<String, dynamic> _volumeData = {};
  List<Map<String, dynamic>> _diagnosticsData = [];
  List<Map<String, dynamic>> _timelineData = [];
  
  // 2. CONSISTENCY & MASTER SCORE STATE
  int _weeklySessions = 0; 
  double _averageFormScore = 0.0; 
  List<int> _weeklyHeatmap = [0, 0, 0, 0, 0, 0, 0]; 
  final List<String> _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  // 3. PREMIUM ANALYTICS STATE
  Map<String, double> _radarData = {'Push': 0, 'Pull': 0, 'Legs': 0, 'Core': 0, 'Mobility': 0};
  Map<String, List<double>> _fatigueCurves = {};
  String? _selectedFatigueExercise;
  Map<String, int> _muscleVolume = {'Arms/Chest': 0, 'Core': 0, 'Legs': 0};

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final aggregates = await LocalDBService.instance.getDashboardAggregates();
      
      final diagnostics = List<Map<String, dynamic>>.from(aggregates['diagnostics'] ?? []);
      final rawTelemetry = List<Map<String, dynamic>>.from(aggregates['raw_telemetry'] ?? []);
      final allSessions = List<Map<String, dynamic>>.from(aggregates['timeline'] ?? []);
      
      _processRadarData(diagnostics);
      _processFatigueAndHeatmap(rawTelemetry);
      _processWeeklyConsistencyAndScore(allSessions);

      if (mounted) {
        setState(() {
          _volumeData = aggregates['volume'] ?? {'total_time': 0, 'total_reps': 0};
          _diagnosticsData = diagnostics;
          _timelineData = allSessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Dashboard Hydration Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- THE MATH ENGINES ---

  void _processWeeklyConsistencyAndScore(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return;

    int totalScore = 0;
    int currentWeekCount = 0;
    List<int> generatedHeatmap = [0, 0, 0, 0, 0, 0, 0];

    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    for (var s in sessions) {
      final date = DateTime.parse(s['created_at']).toLocal();
      final score = s['global_score'] as int;
      
      totalScore += score;

      if (date.isAfter(startOfWeek.subtract(const Duration(seconds: 1)))) {
        currentWeekCount++;
        int dayIndex = date.weekday - 1; 
        generatedHeatmap[dayIndex] = score > 75 ? 2 : 1; 
      }
    }

    _weeklySessions = currentWeekCount;
    _averageFormScore = (totalScore / sessions.length) / 100.0;
    _weeklyHeatmap = generatedHeatmap;
  }

  void _processRadarData(List<Map<String, dynamic>> diagnostics) {
    Map<String, List<double>> groupedScores = {'Push': [], 'Pull': [], 'Legs': [], 'Core': [], 'Mobility': []};
    
    for (var ex in diagnostics) {
      String name = ex['exercise_name'].toString().toLowerCase();
      double score = (ex['avg_score'] as num).toDouble() / 100.0; 
      
      if (name.contains('push') || name.contains('dip')) groupedScores['Push']!.add(score);
      else if (name.contains('curl') || name.contains('pull')) groupedScores['Pull']!.add(score);
      else if (name.contains('squat') || name.contains('lunge')) groupedScores['Legs']!.add(score);
      else if (name.contains('plank')) groupedScores['Core']!.add(score);
    }

    groupedScores.forEach((key, scores) {
      if (scores.isNotEmpty) {
        _radarData[key] = scores.reduce((a, b) => a + b) / scores.length;
      }
    });
    
    _radarData['Mobility'] = (_radarData['Legs']! + _radarData['Core']!) / 2;
  }

  void _processFatigueAndHeatmap(List<Map<String, dynamic>> telemetry) {
    Map<String, List<List<double>>> rawArrays = {};
    Map<String, int> heatmaps = {'Arms/Chest': 0, 'Core': 0, 'Legs': 0};

    for (var row in telemetry) {
      String name = row['exercise_name'].toString();
      int volume = (row['good_reps'] as int) + (row['bad_reps'] as int);
      
      String lowerName = name.toLowerCase();
      if (lowerName.contains('push') || lowerName.contains('dip') || lowerName.contains('curl')) heatmaps['Arms/Chest'] = heatmaps['Arms/Chest']! + volume;
      else if (lowerName.contains('squat') || lowerName.contains('lunge')) heatmaps['Legs'] = heatmaps['Legs']! + volume;
      else if (lowerName.contains('plank')) heatmaps['Core'] = heatmaps['Core']! + volume;

      try {
        List<dynamic> decoded = jsonDecode(row['rep_scores_array']);
        List<double> scores = decoded.map((e) => (e as num).toDouble()).toList();
        if (scores.length > 2) { 
          rawArrays.putIfAbsent(name, () => []).add(scores);
        }
      } catch (e) {
        continue;
      }
    }

    Map<String, List<double>> averagedCurves = {};
    for (var ex in rawArrays.keys) {
      List<List<double>> sets = rawArrays[ex]!;
      int maxLength = sets.map((s) => s.length).reduce(math.max);
      
      List<double> avgCurve = [];
      for (int i = 0; i < maxLength; i++) {
        double sum = 0;
        int count = 0;
        for (var s in sets) {
          if (i < s.length) {
            sum += s[i];
            count++;
          }
        }
        avgCurve.add(sum / count);
      }
      averagedCurves[ex] = avgCurve;
    }

    _muscleVolume = heatmaps;
    _fatigueCurves = averagedCurves;
    if (_fatigueCurves.isNotEmpty) {
      _selectedFatigueExercise = _fatigueCurves.keys.first;
    }
  }

  // --- UI FORMATTERS & HELPERS ---

  String _formatTotalTime(int? totalSeconds) {
    if (totalSeconds == null || totalSeconds == 0) return "0m";
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m";
  }

  String _formatSessionDate(String sqlDate) {
    final date = DateTime.parse(sqlDate).toLocal();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${months[date.month - 1]} ${date.day}";
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mintGreen.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
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
          width: 32, height: 32,
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

  Widget _buildStatCard({required String title, required String value, required IconData icon, Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: mintGreen, size: 16),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: navyBlue, body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    final bool isDayZero = _timelineData.isEmpty;

    return Scaffold(
      backgroundColor: navyBlue,
      appBar: AppBar(
        backgroundColor: navyBlue, elevation: 0,
        title: const Text('TELEMETRY DASHBOARD', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 16)), 
      ),
      body: isDayZero 
        ? _buildZeroState() 
        : RefreshIndicator(
            color: mintGreen,
            backgroundColor: darkSlate,
            onRefresh: _loadDashboardData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // --- 1. THE OLD MASTER SCORE & NEW VOLUME (Merged) ---
                _buildGlassCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Avg Form Score', style: TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 8),
                            Text(
                              '${(_averageFormScore * 100).toInt()}%',
                              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.timer, color: mintGreen, size: 14),
                                const SizedBox(width: 4),
                                Text(_formatTotalTime(_volumeData['total_time']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.fitness_center, color: mintGreen, size: 14),
                                const SizedBox(width: 4),
                                Text("${_volumeData['total_reps'] ?? 0} Reps", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 120, width: 120,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: _averageFormScore,
                              strokeWidth: 10, backgroundColor: navyBlue, color: mintGreen,
                            ),
                            const Center(child: Icon(Icons.analytics, color: mintGreen, size: 48)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- 2. THE OLD 7-DAY CONSISTENCY TRACKER ---
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
                        children: List.generate(7, (index) => _buildHeatmapDay(_days[index], _weeklyHeatmap[index], false)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // --- 3. THE OLD DIAGNOSTICS PANEL ---
                if (_diagnosticsData.isNotEmpty) ...[
                  const Text('FORM DIAGNOSTICS', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  _buildGlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        ..._diagnosticsData.take(2).map((ex) => _buildDiagnosticRow(
                          name: ex['exercise_name'], 
                          score: (ex['avg_score'] as num).toInt(), 
                          isGood: true
                        )),
                        if (_diagnosticsData.length > 2) ...[
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white10, height: 1)),
                          ..._diagnosticsData.skip(_diagnosticsData.length - 2).map((ex) => _buildDiagnosticRow(
                            name: ex['exercise_name'], 
                            score: (ex['avg_score'] as num).toInt(), 
                            isGood: false
                          )),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // --- 4. THE NEW RADAR & ANATOMY HEATMAP SPLIT ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildRadarCard()),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildAnatomyCard()),
                  ],
                ),
                const SizedBox(height: 24),

                // --- 5. THE NEW FATIGUE PREDICTOR ---
                _buildFatigueCard(),
                const SizedBox(height: 24),

                // --- 6. THE OLD ROLLING TIMELINE ---
                const Text('RECENT ACTIVITY', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                ..._timelineData.take(5).map((session) => _buildTimelineNode(session)),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildDiagnosticRow({required String name, required int score, required bool isGood}) {
    final color = isGood ? mintGreen : neonRed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.5))),
            child: Text("$score%", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildRadarCard() {
    return _buildGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BIOMECHANICAL BALANCE', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: mintGreen.withOpacity(0.2),
                    borderColor: mintGreen,
                    entryRadius: 3,
                    dataEntries: [
                      RadarEntry(value: _radarData['Push']!),
                      RadarEntry(value: _radarData['Pull']!),
                      RadarEntry(value: _radarData['Legs']!),
                      RadarEntry(value: _radarData['Core']!),
                      RadarEntry(value: _radarData['Mobility']!),
                    ],
                  )
                ],
                radarBackgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                radarBorderData: const BorderSide(color: Colors.white10, width: 2),
                tickBorderData: const BorderSide(color: Colors.white10, width: 1),
                tickCount: 4,
                ticksTextStyle: const TextStyle(color: Colors.transparent),
                // DELETED: titlePositionMultiplierPercentage
                getTitle: (index, angle) {
                  final titles = ['PUSH', 'PULL', 'LEGS', 'CORE', 'MOBILITY'];
                  return RadarChartTitle(
                    text: titles[index], 
                    angle: 0, 
                    positionPercentageOffset: 0.2 // Tweak this number if the text overlaps the chart
                  );
                },
                titleTextStyle: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              swapAnimationDuration: const Duration(milliseconds: 400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnatomyCard() {
    return _buildGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('7-DAY LOAD', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: HumanoidPainter(volumes: _muscleVolume),
              size: const Size(double.infinity, 180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFatigueCard() {
    if (_fatigueCurves.isEmpty || _selectedFatigueExercise == null) return const SizedBox.shrink();
    
    final curve = _fatigueCurves[_selectedFatigueExercise]!;
    
    int? failurePoint;
    for (int i = 0; i < curve.length; i++) {
      if (curve[i] < 0.7) { failurePoint = i + 1; break; }
    }

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('FATIGUE TRAJECTORY', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              DropdownButton<String>(
                value: _selectedFatigueExercise,
                dropdownColor: navyBlue,
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down, color: mintGreen),
                style: const TextStyle(color: mintGreen, fontWeight: FontWeight.bold, fontSize: 12),
                items: _fatigueCurves.keys.map((String key) => DropdownMenuItem(value: key, child: Text(key.toUpperCase()))).toList(),
                onChanged: (val) => setState(() => _selectedFatigueExercise = val),
              ),
            ],
          ),
          if (failurePoint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text("Predictive Failure at Rep $failurePoint", style: const TextStyle(color: neonRed, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (val) => FlLine(color: Colors.white10, strokeWidth: 1)),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)))),
                ),
                borderData: FlBorderData(show: false),
                minX: 1, maxX: curve.length.toDouble(),
                minY: 0, maxY: 1.0,
                lineBarsData: [
                  LineChartBarData(
                    spots: curve.asMap().entries.map((e) => FlSpot((e.key + 1).toDouble(), e.value)).toList(),
                    isCurved: true, color: mintGreen, barWidth: 3, isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true, 
                      gradient: LinearGradient(colors: [mintGreen.withOpacity(0.3), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineNode(Map<String, dynamic> session) {
    final int score = session['global_score'];
    final Color scoreColor = score > 75 ? mintGreen : (score > 50 ? Colors.orangeAccent : neonRed);
    final date = DateTime.parse(session['created_at']).toLocal();
    final dateStr = "${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.day}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scoreColor, width: 2), color: Colors.black.withOpacity(0.2)),
          child: Center(child: Text(score.toString(), style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 16))),
        ),
        title: Text(dateStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text('Score Evaluated', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      ),
    );
  }

  Widget _buildZeroState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildGlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: mintGreen.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.power_settings_new, size: 48, color: mintGreen)),
              const SizedBox(height: 24),
              const Text('NO TELEMETRY', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionSetupPage())),
                child: const Text('INITIATE FIRST SESSION', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HumanoidPainter extends CustomPainter {
  final Map<String, int> volumes;

  HumanoidPainter({required this.volumes});

  @override
  void paint(Canvas canvas, Size size) {
    int maxVol = volumes.values.fold(0, math.max);
    if (maxVol == 0) maxVol = 1; 

    Color getColor(String group) {
      double intensity = volumes[group]! / maxVol;
      if (intensity == 0) return Colors.white12;
      if (intensity < 0.5) return Color.lerp(Colors.white24, mintGreen, intensity * 2)!;
      return Color.lerp(mintGreen, neonRed, (intensity - 0.5) * 2)!;
    }

    final paint = Paint()..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    paint.color = Colors.white24; paint.strokeWidth = 14; canvas.drawCircle(Offset(cx, cy - 60), 10, paint);
    paint.color = getColor('Core'); paint.strokeWidth = 24; canvas.drawLine(Offset(cx, cy - 40), Offset(cx, cy + 20), paint);
    paint.color = getColor('Arms/Chest'); paint.strokeWidth = 12;
    canvas.drawLine(Offset(cx - 16, cy - 35), Offset(cx - 35, cy + 10), paint);
    canvas.drawLine(Offset(cx + 16, cy - 35), Offset(cx + 35, cy + 10), paint);
    paint.color = getColor('Legs'); paint.strokeWidth = 16;
    canvas.drawLine(Offset(cx - 8, cy + 25), Offset(cx - 15, cy + 80), paint);
    canvas.drawLine(Offset(cx + 8, cy + 25), Offset(cx + 15, cy + 80), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}