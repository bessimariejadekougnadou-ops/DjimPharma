import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final Map<String, dynamic> user;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({http.Client? client}) : _client = client ?? http.Client();

  static const _tokenKey = 'auth_token';
  static const _prenomKey = 'auth_user_prenom';
  static const _nomKey = 'auth_user_nom';
  static const _emailKey = 'auth_user_email';
  static const _requestTimeout = Duration(seconds: 12);
  final http.Client _client;

  Uri _endpoint(String path) => Uri.parse('${ApiConfig.baseUrl}/$path');

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final body = jsonEncode({
      'email': email.trim().toLowerCase(),
      'mot_de_passe': password,
    });

    http.Response response;
    try {
      response = await _client
          .post(
            _endpoint('connexion/'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 4));
      ApiConfig.markSuccess(ApiConfig.baseUrl);
    } catch (_) {
      response = await _client
          .post(
            Uri.parse('${ApiConfig.wifiBaseUrl}/connexion/'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_requestTimeout);
      ApiConfig.markSuccess(ApiConfig.wifiBaseUrl);
    }

    final data = _decodeResponse(response);
    final token = data['token'];
    final user = data['utilisateur'];
    if (token is! String || user is! Map<String, dynamic>) {
      throw const AuthException('Réponse de connexion invalide.');
    }

    await _saveToken(token);
    await _saveUser(user);
    return AuthSession(token: token, user: user);
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String phone = '',
  }) async {
    final body = jsonEncode({
      'nom': lastName.trim(),
      'prenom': firstName.trim(),
      'email': email.trim().toLowerCase(),
      'mot_de_passe': password,
      'telephone': phone.trim(),
    });

    http.Response response;
    try {
      response = await _client
          .post(
            _endpoint('inscription/'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 4));
      ApiConfig.markSuccess(ApiConfig.baseUrl);
    } catch (_) {
      response = await _client
          .post(
            Uri.parse('${ApiConfig.wifiBaseUrl}/inscription/'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_requestTimeout);
      ApiConfig.markSuccess(ApiConfig.wifiBaseUrl);
    }

    _decodeResponse(response);
    await _saveUser({
      'prenom': firstName.trim(),
      'nom': lastName.trim(),
      'email': email.trim().toLowerCase(),
    });
  }

  Future<String?> getToken() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_tokenKey);
  }

  Future<void> logout() async {
    final token = await getToken();

    if (token != null) {
      try {
        await _client
            .post(
              _endpoint('deconnexion/'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Token $token',
              },
            )
            .timeout(_requestTimeout);
      } catch (_) {
        // On continue la déconnexion locale même si le serveur ne répond plus.
      }
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    await preferences.remove(_prenomKey);
    await preferences.remove(_nomKey);
    await preferences.remove(_emailKey);
  }

  Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
    if (token == null) {
      throw const AuthException('Aucune session active.');
    }

    http.Response response;
    try {
      response = await _client
          .get(
            _endpoint('profil/'),
            headers: {'Authorization': 'Token $token'},
          )
          .timeout(const Duration(seconds: 4));
      ApiConfig.markSuccess(ApiConfig.baseUrl);
    } catch (_) {
      response = await _client
          .get(
            Uri.parse('${ApiConfig.wifiBaseUrl}/profil/'),
            headers: {'Authorization': 'Token $token'},
          )
          .timeout(_requestTimeout);
      ApiConfig.markSuccess(ApiConfig.wifiBaseUrl);
    }

    final data = _decodeResponse(response);
    await _saveUser(data);
    return data;
  }

  Future<void> _saveUser(Map<String, dynamic> user) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final prenom = (user['prenom'] ?? user['first_name'] ?? '').toString().trim();
      final nom = (user['nom'] ?? user['last_name'] ?? '').toString().trim();
      final email = (user['email'] ?? '').toString().trim();

      if (prenom.isNotEmpty) {
        await preferences.setString(_prenomKey, prenom);
      }
      if (nom.isNotEmpty) {
        await preferences.setString(_nomKey, nom);
      }
      if (email.isNotEmpty) {
        await preferences.setString(_emailKey, email);
      }
    } catch (_) {}
  }

  Future<Map<String, String>> getCachedUser() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return {
        'prenom': preferences.getString(_prenomKey) ?? '',
        'nom': preferences.getString(_nomKey) ?? '',
        'email': preferences.getString(_emailKey) ?? '',
      };
    } catch (_) {
      return {'prenom': '', 'nom': '', 'email': ''};
    }
  }

  Future<void> _saveToken(String token) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, token);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } on FormatException {
        throw AuthException(
          'Le serveur a renvoyé une réponse invalide (${response.statusCode}).',
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_messageFrom(data, response.statusCode));
    }
    return data;
  }

  String _messageFrom(Map<String, dynamic> data, int statusCode) {
    final message = _findMessage(data);
    if (message != null) return message;

    return 'Erreur serveur ($statusCode).';
  }

  String? _findMessage(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is List) {
      for (final item in value) {
        final message = _findMessage(item);
        if (message != null) return message;
      }
    }
    if (value is Map) {
      for (final item in value.values) {
        final message = _findMessage(item);
        if (message != null) return message;
      }
    }
    return null;
  }
}
