import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  /// Registers user and their public key on the server
  Future<void> register({required String username, required String publicKey}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'publicKey': publicKey,
      }),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Registration failed.');
    }
  }

  /// Fetches Bob's public key from server
  Future<String> fetchUserPublicKey(String username) async {
    final response = await http.get(Uri.parse('$baseUrl/api/user/$username'));

    final body = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return body['publicKey'] ?? '';
    } else {
      throw Exception(body['error'] ?? 'User not found.');
    }
  }

  /// Lists all registered users
  Future<List<String>> fetchUsers() async {
    final response = await http.get(Uri.parse('$baseUrl/api/users'));

    final body = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final List<dynamic> list = body['users'] ?? [];
      return list.map((u) => u.toString()).toList();
    } else {
      throw Exception('Failed to fetch user list.');
    }
  }
}
