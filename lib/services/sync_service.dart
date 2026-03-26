import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/api_constants.dart';
import 'local_db_service.dart';

class SyncService {
  static Future<void> pushUnsyncedData() async {
    try {
      final unsyncedSessions = await LocalDBService.instance.getUnsyncedSessions();
      
      if (unsyncedSessions.isEmpty) {
        debugPrint("SyncService: Local DB clean.");
        return;
      }

      debugPrint("SyncService: Attempting to sync ${unsyncedSessions.length} sessions to ${ApiConstants.baseUrl}...");

      for (var sessionData in unsyncedSessions) {
        final Map<String, dynamic> payload = {
          "session_id": sessionData['id'],
          "user_id": sessionData['user_id'],
          "routine_id": sessionData['routine_id'],
          "status": sessionData['status'],
          "global_score": sessionData['global_score'],
          "duration_seconds": sessionData['duration_seconds'],
          "exercises": sessionData['exercises'].map((ex) => {
            "telemetry_id": ex['id'],
            "exercise_name": ex['exercise_name'],
            "good_reps": ex['good_reps'],
            "bad_reps": ex['bad_reps'],
            "exercise_score": ex['exercise_score'],
            "rep_scores": ex['rep_scores']
          }).toList(),
        };

        // Added a 10-second timeout so it doesn't hang if the server is dead
        final response = await http.post(
          Uri.parse(ApiConstants.syncSessionEndpoint),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          if (responseData['status'] == 'success') {
            await LocalDBService.instance.markSessionAsSynced(sessionData['id']);
            debugPrint("SyncService: Session ${sessionData['id']} synced to server.");
          } else {
            debugPrint("SyncService: Server Rejected - ${responseData['message']}");
          }
        } else {
          debugPrint("SyncService: HTTP Error ${response.statusCode}");
        }
      }
    } on TimeoutException {
      debugPrint("SyncService: Connection timed out. Server unreachable.");
    } catch (e) {
      debugPrint("SyncService: Sync failed - $e");
    }
  }
}