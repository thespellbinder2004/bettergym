import 'dart:convert';
import 'package:flutter/material.dart';
import '../main.dart';
import 'main_layout.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_constants.dart';
import 'ai_video_player.dart';

class ProgressReportPageAI extends StatelessWidget {
  final List<Map<String, dynamic>> aiSessions;
  final String? sessionId;

  const ProgressReportPageAI({
    super.key,
    required this.aiSessions,
    this.sessionId,
  });

  double _toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String _toStr(dynamic value, [String fallback = ""]) {
    if (value == null) return fallback;
    return value.toString();
  }

  Map<String, dynamic> _parseResultJson(dynamic raw) {
    try {
      if (raw == null) return {};
      if (raw is Map<String, dynamic>) return raw;
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Color _scoreColor(int score) {
    if (score >= 100) return const Color(0xFF8B00FF);
    if (score >= 75) return mintGreen;
    if (score >= 50) return Colors.yellow;
    if (score >= 25) return Colors.orange;
    return neonRed;
  }

  // Helper Functions
  String _buildSecureVideoUrl({
    required int userId,
    required String sessionId,
    required String exerciseName,
    required String authToken,
  }) {
    return "${ApiConstants.baseUrl}/stream_ai_video.php"
        "?user_id=$userId"
        "&session_id=${Uri.encodeComponent(sessionId)}"
        "&exercise_name=${Uri.encodeComponent(exerciseName)}"
        "&auth_token=${Uri.encodeComponent(authToken)}";
  }
  // Widgets

  Widget _buildMacroStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionChip(String label, double prob,
      {bool highlight = false}) {
    final color = highlight ? mintGreen : Colors.white70;

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        "$label ${(prob * 100).toStringAsFixed(0)}%",
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRepCard(
      Map<String, dynamic> rep, String exerciseName, int fallbackIndex) {
    final repNumber = _toInt(rep['rep'], fallbackIndex + 1);
    final isGood = rep['is_good_form'] == true;
    final formLabel = _toStr(rep['form_label'], isGood ? "good" : "bad");
    final predictedName = _toStr(rep['pred_name'], '-');
    final confidence = _toDouble(rep['confidence']);
    final startFrame = _toInt(rep['start_frame']);
    final endFrame = _toInt(rep['end_frame']);

    final List topPredictions =
        rep['top_predictions'] is List ? rep['top_predictions'] as List : [];

    final Color accent = isGood ? mintGreen : neonRed;

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
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          iconColor: mintGreen,
          collapsedIconColor: Colors.grey,
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
              color: Colors.black.withOpacity(0.2),
            ),
            child: Center(
              child: Text(
                "$repNumber",
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          title: Text(
            "REP $repNumber",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              isGood ? "Good Form" : "Bad Form",
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: Text(
              "${(confidence * 100).round()}%",
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow("Expected Exercise", exerciseName),
                        _buildDetailRow("Predicted Class", predictedName),
                        _buildDetailRow(
                          "Form Label",
                          formLabel.toUpperCase(),
                          valueColor: accent,
                        ),
                        _buildDetailRow(
                          "Confidence",
                          "${(confidence * 100).toStringAsFixed(0)}%",
                          valueColor: accent,
                        ),
                        _buildDetailRow("Start Frame", "$startFrame"),
                        _buildDetailRow("End Frame", "$endFrame"),
                      ],
                    ),
                  ),
                  if (topPredictions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "TOP PREDICTIONS",
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: topPredictions.map((item) {
                        if (item is! Map) return const SizedBox.shrink();
                        final map = Map<String, dynamic>.from(item);
                        final label = _toStr(map['label'], '-');
                        final prob = _toDouble(map['prob']);
                        return _buildPredictionChip(
                          label,
                          prob,
                          highlight: label.toLowerCase() ==
                              predictedName.toLowerCase(),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseSection(BuildContext context, Map<String, dynamic> row) {
    final resultJson = _parseResultJson(
      row['result_json'] ?? row['result'] ?? row['json'],
    );

    final String exerciseName = _toStr(
      resultJson['exercise'] ??
          resultJson['exercise_name'] ??
          row['exercise_name'],
      'Exercise',
    );

    final int goodReps = _toInt(resultJson['good_reps']);
    final int badReps = _toInt(resultJson['bad_reps']);
    final int score = _toInt(resultJson['score']);
    final int totalReps = _toInt(resultJson['total_reps']);
    final double avgConfidence = _toDouble(resultJson['average_confidence']);
    final String majorityPrediction = _toStr(resultJson['majority_prediction']);

    final List<Map<String, dynamic>> reps =
        (resultJson['reps'] is List ? resultJson['reps'] as List : [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final Color scoreColor = _scoreColor(score);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exerciseName.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMacroStat("GOOD REPS", goodReps.toString(), mintGreen),
              _buildMacroStat("SCORE", score.toString(), scoreColor),
              _buildMacroStat("BAD REPS", badReps.toString(), neonRed),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                _buildDetailRow("Total Reps", totalReps.toString()),
                _buildDetailRow(
                  "Majority Prediction",
                  majorityPrediction.isEmpty ? "-" : majorityPrediction,
                ),
                _buildDetailRow(
                  "Average Confidence",
                  "${(avgConfidence * 100).toStringAsFixed(0)}%",
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: mintGreen,
              foregroundColor: navyBlue,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final authToken = prefs.getString('auth_token');
              final userId = prefs.getInt('user_id');

              if (authToken == null || userId == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Missing login credentials.")),
                  );
                }
                return;
              }

              final videoUrl = _buildSecureVideoUrl(
                userId: userId,
                sessionId: _toStr(row['session_id']),
                exerciseName: exerciseName,
                authToken: authToken,
              );

              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiVideoPlayerPage(
                      videoUrl: videoUrl,
                      title: "$exerciseName Video",
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.play_circle_fill),
            label: const Text(
              "WATCH VIDEO",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          if (reps.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "No per-rep evaluation found.",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            ...reps.asMap().entries.map(
                  (entry) =>
                      _buildRepCard(entry.value, exerciseName, entry.key),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRows = sessionId == null
        ? aiSessions
        : aiSessions
            .where((row) => _toStr(row['session_id']) == sessionId)
            .toList();

    return Scaffold(
      backgroundColor: navyBlue,
      appBar: AppBar(
        backgroundColor: navyBlue,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'AI SESSION REPORT',
          style: TextStyle(
            color: mintGreen,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
      ),
      body: filteredRows.isEmpty
          ? const Center(
              child: Text(
                "No AI results found for this session.",
                style: TextStyle(color: Colors.white70),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredRows.length,
                    itemBuilder: (context, index) {
                      return _buildExerciseSection(
                          context, filteredRows[index]);
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.dashboard),
                    label: const Text(
                      "RETURN TO DASHBOARD",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const MainLayout()),
                        (route) => false,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
