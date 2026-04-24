class ApiConstants {
  // FLIP THIS TO TRUE WHEN DEPLOYING TO BETTERGYM.ONLINE
  static const bool kIsProduction = true;

  // --- LOCAL XAMPP TESTING ---
  static const String _localBaseUrl = "http://192.168.1.5";
  static const String _productionBaseUrl = "https://bettergym.online";

  static const String baseUrl =
      kIsProduction ? _productionBaseUrl : _localBaseUrl;

// EXISTING ENDPOINTS
  static const String syncSessionEndpoint = "$baseUrl/sync_session.php";
  static const String fetchHistoryEndpoint = "$baseUrl/fetch_history.php";

  // THE NEW ENDPOINT
  static const String updateSettingsEndpoint = "$baseUrl/update_settings.php";

  static const String pingEndpoint = "$baseUrl/ping.php";
}
