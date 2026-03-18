import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://bettergym.online/';

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login.php'),
      body: {
        'username': username,
        'password': password,
      },
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String email,
    required String firstName,
    required String lastName,
    required String birthday,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register.php'),
      body: {
        'username': username,
        'password': password,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'birthday': birthday,
      },
    );

    return jsonDecode(response.body);
  }
}
