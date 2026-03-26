// lib/utils/api_constants.dart

class ApiConstants {
  // FLIP THIS TO TRUE WHEN DEPLOYING TO BETTERGYM.ONLINE
  static const bool kIsProduction = false; 

  // --- LOCAL XAMPP TESTING ---
  // If using Android Emulator, use 10.0.2.2
  // If using physical phone on Wi-Fi, use your IPv4 (e.g., 192.168.1.5)
  static const String _localBaseUrl = 'http://10.0.2.2/bettergym_api'; 

  // --- PRODUCTION SERVER ---
  static const String _prodBaseUrl = 'https://bettergym.online/api'; // Update folder path if needed

  static String get baseUrl => kIsProduction ? _prodBaseUrl : _localBaseUrl;

  // Endpoint routes
  static String get syncSessionEndpoint => '$baseUrl/sync_session.php';
}