import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/api_constants.dart';
import 'local_db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncService {
  static Future<void> pushUnsyncedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? authToken = prefs.getString('auth_token');
      final int? userId = prefs.getInt('user_id');

      if (authToken == null || userId == null) {
        debugPrint(
            "SyncService: Aborting sync. No valid user credentials found.");
        return;
      }

      final unsyncedSessions =
          await LocalDBService.instance.getUnsyncedSessions();

      if (unsyncedSessions.isEmpty) {
        debugPrint("SyncService: Local DB clean.");
        return;
      }

      debugPrint(
          "SyncService: Attempting to sync ${unsyncedSessions.length} sessions to ${ApiConstants.baseUrl}...");

      for (var sessionData in unsyncedSessions) {
        final Map<String, dynamic> payload = {
          "auth_token": authToken,
          "user_id": userId,
          "session_id": sessionData['id'],
          "routine_id": sessionData['routine_id'],
          "status": sessionData['status'],
          "global_score": sessionData['global_score'],
          "duration_seconds": sessionData['duration_seconds'],
          // FIXED ALIGNMENT: Mapping strictly to what the new PHP script expects
          "exercises": (sessionData['exercises'] as List)
              .map((ex) => {
                    "id": ex['id'],
                    "exercise_name": ex['exercise_name'],
                    "good_reps": ex['good_reps'],
                    "bad_reps": ex['bad_reps'],
                    "exercise_score": ex['exercise_score'],
                    "reps": ex['reps']
                  })
              .toList(),
        };

        final response = await http
            .post(
              Uri.parse(ApiConstants.syncSessionEndpoint),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          if (responseData['status'] == 'success') {
            // FIXED TYPO: Removed 'As' to match LocalDBService declaration
            await LocalDBService.instance.markSessionSynced(sessionData['id']);
            debugPrint(
                "SyncService: Session ${sessionData['id']} synced to server.");
          } else {
            debugPrint(
                "SyncService: Server Rejected - ${responseData['message']}");
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

  static Future<bool> pullHistoricalData(int userId, String token) async {
    try {
      debugPrint("SyncService: Pulling historical data for User $userId...");
      debugPrint(
          "SyncService: fetchHistoryEndpoint = ${ApiConstants.fetchHistoryEndpoint}");
      final response = await http
          .post(
            Uri.parse(ApiConstants.fetchHistoryEndpoint),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "user_id": userId,
              "auth_token": token,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['status'] == 'success') {
          List<dynamic> sessions = responseData['sessions'];

          if (sessions.isNotEmpty) {
            await LocalDBService.instance.saveDownloadedHistory(sessions);
            debugPrint(
                "SyncService: Successfully rebuilt local DB with ${sessions.length} sessions.");
          } else {
            debugPrint("SyncService: No historical data found on server.");
          }
          return true;
        } else {
          debugPrint(
              "SyncService: Server rejected pull - ${responseData['message']}");
          return false;
        }
      } else {
        debugPrint("SyncService: HTTP Error ${response.statusCode}");
        return false;
      }
    } catch (e) {
      debugPrint("SyncService: Network failure during pull - $e");
      return false;
    }
  }
}
