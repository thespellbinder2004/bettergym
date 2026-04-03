import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import 'session_setup_page.dart';
import '../services/local_db_service.dart';
import '../services/api_services.dart';
import 'progress_report_page.dart';
import 'session_summary_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  bool _transportActive = false;
  int _enduranceLookback = 7;

  Map<String, dynamic> _data = {};
  Map<String, List<double>> _fatigueCurves = {};
  String? _selectedFatigueExercise;
  List<int> _weeklyHeatmap = [0, 0, 0, 0, 0, 0, 0];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // --- THE COLOR SOP ---
  Color _getScoreColor(double score) {
    if (score >= 100) return const Color(0xFF8B00FF); // Violet
    if (score >= 75) return mintGreen;
    if (score >= 50) return Colors.yellow;
    if (score >= 25) return Colors.orange;
    return neonRed;
  }

  Future<void> _loadDashboardData() async {
    try {
      // Trigger background sync without freezing the UI
      ApiService.syncOfflineData();

      final aggregates = await LocalDBService.instance.getDashboardAggregates();
      final rawEndurance = await LocalDBService.instance
          .getRawTelemetryForPeriod(_enduranceLookback);

      _processEndurance(rawEndurance);
      _processWeeklyConsistency(aggregates['timeline'] ?? []);

      if (mounted) {
        setState(() {
          _data = aggregates;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Dashboard Hydration Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processWeeklyConsistency(List<dynamic> sessions) {
    List<int> generatedHeatmap = [0, 0, 0, 0, 0, 0, 0];
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    for (var s in sessions) {
      final date = DateTime.parse(s['created_at']).toLocal();
      final score = s['global_score'] as int;
      if (date.isAfter(startOfWeek.subtract(const Duration(seconds: 1)))) {
        int dayIndex = date.weekday - 1;
        generatedHeatmap[dayIndex] = score > 75 ? 2 : 1;
      }
    }
    _weeklyHeatmap = generatedHeatmap;
  }

  void _processEndurance(List<Map<String, dynamic>> telemetry) {
    Map<String, List<List<double>>> rawArrays = {};
    for (var row in telemetry) {
      try {
        List<double> scores = List<double>.from(
            jsonDecode(row['rep_scores_array'])
                .map((e) => (e as num).toDouble()));
        rawArrays.putIfAbsent(row['exercise_name'], () => []).add(scores);
      } catch (_) {}
    }

    Map<String, List<double>> averaged = {};
    rawArrays.forEach((name, sets) {
      int maxLen = sets.map((s) => s.length).reduce(math.max);
      List<double> curve = [];
      for (int i = 0; i < maxLen; i++) {
        double sum = 0;
        int count = 0;
        for (var s in sets) {
          if (i < s.length) {
            sum += s[i];
            count++;
          }
        }
        curve.add(sum / count);
      }
      averaged[name] = curve;
    });

    setState(() {
      _fatigueCurves = averaged;
      if (_fatigueCurves.isNotEmpty)
        _selectedFatigueExercise = _fatigueCurves.keys.first;
    });
  }

  String _formatTotalTime(int? totalSeconds) {
    if (totalSeconds == null || totalSeconds == 0) return "0m";
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    return h > 0 ? "${h}h ${m}m" : "${m}m";
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mintGreen.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          backgroundColor: navyBlue,
          body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    final timeline = List<Map<String, dynamic>>.from(_data['timeline'] ?? []);
    final bool isDayZero = timeline.isEmpty;

    if (isDayZero) {
      return Scaffold(
          backgroundColor: navyBlue,
          appBar: AppBar(
              backgroundColor: navyBlue,
              elevation: 0,
              title: const Text('DASHBOARD',
                  style: TextStyle(
                      color: mintGreen,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      fontSize: 16))),
          body: _buildZeroState());
    }

    final lastKnown = _data['last_known'];
    final bool workedToday =
        lastKnown != null && lastKnown['relative_date'] == 'TODAY';
    final weeklyVol = _data['weekly_volume'];

    return Scaffold(
      backgroundColor: navyBlue,
      appBar: AppBar(
        backgroundColor: navyBlue,
        elevation: 0,
        title: const Text('DASHBOARD',
            style: TextStyle(
                color: mintGreen,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                fontSize: 16)),
      ),
      body: RefreshIndicator(
        color: mintGreen,
        backgroundColor: darkSlate,
        onRefresh: _loadDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // --- GIMMICK: LATEST ACTIVITY TRANSPORT ---
            if (_transportActive && timeline.isNotEmpty) ...[
              _buildTimelineNode(timeline.first),
              const SizedBox(height: 24),
            ],

            // --- 1. BENTO BOXES ---
            Row(
              children: [
                Expanded(
                    child: _buildBentoRing("Weekly Average",
                        (_data['bento']['weekly_avg'] ?? 0.0))),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildBentoRing("Monthly Average",
                        (_data['bento']['monthly_avg'] ?? 0.0))),
              ],
            ),
            const SizedBox(height: 24),

            // --- 2. CONSISTENCY HEATMAP ---
            _buildGlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                    7,
                    (i) => _buildHeatmapDay(
                        ['M', 'T', 'W', 'Th', 'F', 'S', 'S'][i],
                        _weeklyHeatmap[i])),
              ),
            ),
            const SizedBox(height: 24),

            // --- 3. ACTION HUB (If no workout today) ---
            if (!workedToday) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen,
                    foregroundColor: navyBlue,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SessionSetupPage())),
                child: const Text('SETUP A SESSION',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.2)),
              ),
              const SizedBox(height: 24),
            ],

            // --- 4. CONTEXTUAL INTELLIGENCE ---
            if (lastKnown != null) ...[
              Text(
                  lastKnown['relative_date'] == 'TODAY'
                      ? "TODAY'S PERFORMANCE"
                      : "LAST SESSION (${lastKnown['relative_date']})",
                  style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              _buildGlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _infoRow(Icons.analytics, "Avg Score",
                        "${lastKnown['global_score']}%",
                        valueColor: _getScoreColor(
                            (lastKnown['global_score'] as num).toDouble())),
                    const Divider(color: Colors.white10),
                    _infoRow(Icons.timer, "Workout Duration",
                        _formatTotalTime(lastKnown['duration_seconds'])),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // --- 5. WEEKLY VOLUME ---
            if (weeklyVol != null &&
                weeklyVol['active_days'] != null &&
                weeklyVol['active_days'] > 0) ...[
              const Text("WEEKLY PERFORMANCE",
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              _buildGlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _infoRow(Icons.calendar_today, "Number of Days Active",
                        "${weeklyVol['active_days']}"),
                    const Divider(color: Colors.white10),
                    _infoRow(Icons.timer, "Total Time Worked Out",
                        _formatTotalTime(weeklyVol['total_time'])),
                    const Divider(color: Colors.white10),
                    _infoRow(Icons.fitness_center, "Total Reps",
                        "${weeklyVol['total_reps'] ?? 0}"),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // --- 6. SWIPABLE GRAPHS ---
            _buildSwipableGraphs(),
            const SizedBox(height: 24),

            // --- 7. FORM DIAGNOSTICS ---
            _buildDiagnostics(),
            const SizedBox(height: 24),

            // --- 8. FORM ENDURANCE ---
            _buildEnduranceSection(),
            const SizedBox(height: 24),

            // --- 9. RECENT ACTIVITY TIMELINE ---
            if (!_transportActive) ...[
              const Text('RECENT ACTIVITY',
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              ...timeline.take(5).map((s) => _buildTimelineNode(s)),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildBentoRing(String label, double score) {
    Color ringColor = _getScoreColor(score);
    return _buildGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 80,
              width: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                      value: score > 0 ? score / 100 : 0.0,
                      strokeWidth: 8,
                      backgroundColor: Colors.white10,
                      color: ringColor),
                  Center(
                      child: Text(score > 0 ? "${score.toInt()}%" : "--",
                          style: TextStyle(
                              color: score > 0 ? ringColor : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 18))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapDay(String day, int intensity) {
    Color blockColor = intensity == 0
        ? navyBlue
        : (intensity == 1 ? mintGreen.withOpacity(0.4) : mintGreen);
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: blockColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: intensity == 0
                      ? Colors.grey.withOpacity(0.2)
                      : Colors.transparent)),
        ),
        const SizedBox(height: 8),
        Text(day, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String val,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: mintGreen, size: 16),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          Text(val,
              style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSwipableGraphs() {
    List<dynamic> g7 = _data['graph_7'] ?? [];
    List<dynamic> g30 = _data['graph_30'] ?? [];

    if (g7.isEmpty && g30.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 220,
      child: PageView(
        children: [
          if (g7.isNotEmpty) _buildTrendChart("WEEKLY AVERAGE TREND", g7),
          if (g30.isNotEmpty) _buildTrendChart("MONTHLY AVERAGE TREND", g30),
        ],
      ),
    );
  }

  Widget _buildTrendChart(String title, List<dynamic> data) {
    List<FlSpot> spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(
            e.key.toDouble(), (e.value['avg_score'] as num).toDouble() / 100.0))
        .toList();
    return _buildGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const Icon(Icons.swipe, color: Colors.white24, size: 16),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(LineChartData(
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (val) =>
                        FlLine(color: Colors.white10, strokeWidth: 1)),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: 1.0,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: mintGreen,
                    barWidth: 3,
                    dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                                radius: 4,
                                color: _getScoreColor(spot.y * 100),
                                strokeWidth: 0)),
                    belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                            colors: [
                              mintGreen.withOpacity(0.3),
                              Colors.transparent
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter)),
                  )
                ])),
          )
        ],
      ),
    );
  }

  Widget _buildDiagnostics() {
    final diag = List<Map<String, dynamic>>.from(_data['diagnostics'] ?? []);
    if (diag.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("FORM DIAGNOSTICS",
            style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
        const SizedBox(height: 8),
        _buildGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ...diag.take(2).map((e) => _diagRow(e)),
              if (diag.length > 2) ...[
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Colors.white10, height: 1)),
                ...diag.skip(diag.length - 2).map((e) => _diagRow(e)),
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _diagRow(Map<String, dynamic> e) {
    double score = (e['avg_score'] as num).toDouble();
    Color c = _getScoreColor(score);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Text(e['exercise_name'].toString().toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: c.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.withOpacity(0.5))),
            child: Text("${score.toInt()}%",
                style: TextStyle(
                    color: c, fontWeight: FontWeight.bold, fontSize: 12)),
          )
        ],
      ),
    );
  }

  Widget _buildEnduranceSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("FORM PROGRESSION",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            DropdownButton<int>(
              value: _enduranceLookback,
              dropdownColor: navyBlue,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: mintGreen),
              style: const TextStyle(
                  color: mintGreen, fontWeight: FontWeight.bold, fontSize: 12),
              items: [7, 14, 30]
                  .map((e) =>
                      DropdownMenuItem(value: e, child: Text("Last $e Days")))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _enduranceLookback = v!;
                  _loadDashboardData();
                });
              },
            )
          ],
        ),
        if (_selectedFatigueExercise != null && _fatigueCurves.isNotEmpty)
          _buildGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  value: _selectedFatigueExercise,
                  isExpanded: true,
                  dropdownColor: navyBlue,
                  underline: const Divider(color: Colors.white10),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                  items: _fatigueCurves.keys
                      .map((k) => DropdownMenuItem(
                          value: k, child: Text(k.toUpperCase())))
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedFatigueExercise = val),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 140,
                  child: LineChart(LineChartData(
                      gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (val) =>
                              FlLine(color: Colors.white10, strokeWidth: 1)),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      minY: 0,
                      maxY: 1.0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: _fatigueCurves[_selectedFatigueExercise]!
                              .asMap()
                              .entries
                              .map((e) => FlSpot(e.key.toDouble(), e.value))
                              .toList(),
                          isCurved: true,
                          color: mintGreen,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                  colors: [
                                    mintGreen.withOpacity(0.3),
                                    Colors.transparent
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter)),
                        )
                      ])),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineNode(Map<String, dynamic> session) {
    double score = (session['global_score'] as num).toDouble();
    Color sColor = _getScoreColor(score);

    DateTime dt = DateTime.parse(session['created_at']).toLocal();
    DateTime now = DateTime.now();
    int diffDays = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    String timeStr = diffDays == 0
        ? "Today"
        : (diffDays == 1 ? "Yesterday" : "$diffDays Days ago");

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: darkSlate,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: sColor, width: 2),
              color: Colors.black.withOpacity(0.2)),
          child: Center(
              child: Text("${score.toInt()}",
                  style: TextStyle(
                      color: sColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16))),
        ),
        title: Text(timeStr,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text('Score Evaluated',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing:
            const Icon(Icons.chevron_right, color: Colors.white38, size: 24),
        onTap: () async {
          // 1. Fetch historical raw data
          final rawTelemetry = await LocalDBService.instance
              .getTelemetryForSession(session['id']);

          // 2. Reconstruct ExerciseTelemetry objects
          List<ExerciseTelemetry> historicalData = rawTelemetry.map((row) {
            List<double> scores = [];
            try {
              scores = List<double>.from(jsonDecode(row['rep_scores_array'])
                  .map((e) => (e as num).toDouble()));
            } catch (_) {}

            bool isTimeBased =
                row['exercise_name'].toString().toLowerCase().contains('plank');

            ExerciseTelemetry ex = ExerciseTelemetry(
              name: row['exercise_name'],
              target: row['good_reps'] + row['bad_reps'],
              isDuration: isTimeBased,
            );

            ex.goodReps = row['good_reps'];
            ex.badReps = row['bad_reps'];
            ex.repScores = scores;
            return ex;
          }).toList();

          if (!context.mounted) return;

          // 3. Push to Progress Report
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProgressReportPage(
                telemetryData: historicalData,
                globalScore: session['global_score'],
                totalDuration: Duration(seconds: session['duration_seconds']),
              ),
            ),
          );
        },
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
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: mintGreen.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.power_settings_new,
                      size: 48, color: mintGreen)),
              const SizedBox(height: 24),
              const Text('NO WORKOUT DATA',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0)),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen,
                    foregroundColor: navyBlue,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SessionSetupPage())),
                child: const Text('SETUP A SESSION',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
