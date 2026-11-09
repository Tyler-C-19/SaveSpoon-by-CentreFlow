import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../domain/auth_user.dart';
import 'token_storage.dart';

class GoogleProfile {
  const GoogleProfile({
    required this.idToken,
    required this.email,
    required this.name,
  });

  final String idToken;
  final String email;
  final String name;
}

class AuthRepository {
  AuthRepository({required this.api, required this.storage});

  final ApiClient api;
  final TokenStorage storage;

  Future<bool> register({
    required String role,
    required String name,
    required String email,
    required String phone,
    required String password,
    required bool acceptedTerms,
  }) async {
    final data = await api.post(
      '/api/auth/register',
      body: {
        'role': role,
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'acceptedTerms': acceptedTerms,
      },
    );
    return data['emailSent'] == true;
  }

  Future<AuthUser> verifyEmail(String email, String code) async {
    final data = await api.post(
      '/api/auth/verify-email',
      body: {'email': email, 'code': code},
    );
    return _saveSession(data as Map<String, dynamic>);
  }

  Future<void> resendVerification(String email) =>
      api.post('/api/auth/resend-verification', body: {'email': email});

  Future<AuthUser> login(String email, String password) async {
    final data = await api.post(
      '/api/auth/login',
      body: {'email': email, 'password': password},
    );
    return _saveSession(data as Map<String, dynamic>);
  }

  Future<void> forgotPassword(String email) =>
      api.post('/api/auth/forgot-password', body: {'email': email});

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) => api.post(
    '/api/auth/reset-password',
    body: {'email': email, 'code': code, 'newPassword': newPassword},
  );

  Future<GoogleProfile?> googleSignIn(String idToken) async {
    final data = await api.post(
      '/api/auth/google',
      body: {'idToken': idToken},
    ) as Map<String, dynamic>;
    if (data['needsProfile'] == true) {
      return GoogleProfile(
        idToken: idToken,
        email: data['email'] as String,
        name: data['name'] as String? ?? '',
      );
    }
    await _saveSession(data);
    return null;
  }

  Future<AuthUser> completeGoogleSignUp({
    required String idToken,
    required String role,
    required String phone,
    required bool acceptedTerms,
  }) async {
    final data = await api.post(
      '/api/auth/google/complete',
      body: {
        'idToken': idToken,
        'role': role,
        'phone': phone,
        'acceptedTerms': acceptedTerms,
      },
    );
    return _saveSession(data as Map<String, dynamic>);
  }

  Future<bool> hasSession() async => await storage.readToken() != null;

  Future<AuthUser> fetchCurrentUser() async {
    final data = await api.get('/api/auth/me');
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AuthUser?> readCachedUser() async {
    final json = await storage.readUserJson();
    if (json == null) return null;
    return AuthUser.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> clearSession() => storage.clear();

  Future<AuthUser> _saveSession(Map<String, dynamic> data) async {
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await storage.save(
      token: data['token'] as String,
      userJson: jsonEncode(user.toJson()),
    );
    return user;
  }
}
