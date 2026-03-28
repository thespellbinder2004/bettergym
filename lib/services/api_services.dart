import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';

class ApiService {
  // --- ENVIRONMENT ROUTING ---
  static const String liveBaseUrl = 'https://bettergym.online/bettergym_api';
  static const String localBaseUrl = 'http://192.168.100.14/bettergym_api';

  static String? _activeBaseUrl;

  // Dynamically determine which server is alive
  static Future<String> getBaseUrl() async {
    if (_activeBaseUrl != null) return _activeBaseUrl!;

    try {
      // Ping the live server with a 2-second timeout. 
      // (Assuming you have a simple ping.php or just checking the root index)
      final response = await http.get(Uri.parse('$liveBaseUrl/login.php')).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200 || response.statusCode == 405) { // 405 Method Not Allowed is fine, means server is up
        debugPrint("ROUTING: Connected to LIVE server.");
        _activeBaseUrl = liveBaseUrl;
        return _activeBaseUrl!;
      }
    } catch (e) {
      debugPrint("ROUTING: Live server unreachable. Falling back to XAMPP ($localBaseUrl).");
    }

    _activeBaseUrl = localBaseUrl;
    return _activeBaseUrl!;
  }

  // --- AUTHENTICATION ---
  static Future<Map<String, dynamic>> login({required String username, required String password}) async {
    final baseUrl = await getBaseUrl();
    final response = await http.post(
      Uri.parse('$baseUrl/login.php'),
      body: {'username': username, 'password': password},
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> register({
    required String username, required String password, required String email,
    required String firstName, required String lastName, required String birthday,
  }) async {
    final baseUrl = await getBaseUrl();
    final response = await http.post(
      Uri.parse('$baseUrl/register.php'),
      body: {
        'username': username, 'password': password, 'email': email,
        'first_name': firstName, 'last_name': lastName, 'birthday': birthday,
      },
    );
    return jsonDecode(response.body);
  }

  // --- THE SYNC ENGINE ---
  static Future<void> syncOfflineData() async {
    try {
      final unsyncedSessions = await LocalDBService.instance.getUnsyncedSessions();
      if (unsyncedSessions.isEmpty) return;

      final baseUrl = await getBaseUrl();

      // TODO: Fetch the actual logged-in user's ID and Auth Token here (e.g., from SharedPreferences)
      String currentUserId = "1"; // Replace with actual
      String currentAuthToken = "YOUR_SAVED_TOKEN"; // Replace with actual

      for (var session in unsyncedSessions) {
        // Your sync_session.php expects auth_token, user_id, and session_id at the root
        session['auth_token'] = currentAuthToken;
        session['user_id'] = currentUserId;
        session['session_id'] = session['id']; // Map SQLite 'id' to PHP 'session_id'

        // Map telemetry 'id' to PHP 'telemetry_id'
        if (session['exercises'] != null) {
          for (var ex in session['exercises']) {
            ex['telemetry_id'] = ex['id'];
          }
        }

        final response = await http.post(
          Uri.parse('$baseUrl/sync_session.php'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(session),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final resData = jsonDecode(response.body);
          if (resData['status'] == 'success') {
            await LocalDBService.instance.markSessionAsSynced(session['id']);
            debugPrint("SYNC SUCCESS: Session ${session['id']} backed up.");
          } else {
            debugPrint("SYNC REJECTED: ${resData['message']}");
          }
        }
      }
    } catch (e) {
      debugPrint("SYNC NETWORK ERROR: $e");
    }
  }
}