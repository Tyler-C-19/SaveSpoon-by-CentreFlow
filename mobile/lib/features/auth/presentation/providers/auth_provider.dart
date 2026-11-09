import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../../data/auth_repository.dart';
import '../../data/google_auth_service.dart';
import '../../domain/auth_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthRepository? _repository;

  AuthStatus _status = AuthStatus.unknown;
  AuthUser? _user;

  AuthStatus get status => _status;
  AuthUser? get user => _user;

  AuthRepository get repository => _repository!;

  late GoogleAuthService _google;

  void attach(AuthRepository repository, GoogleAuthService google) {
    _repository = repository;
    _google = google;
  }

  Future<GoogleProfile?> signInWithGoogle() async {
    final idToken = await _google.getIdToken();
    if (idToken == null) return null;

    final profile = await repository.googleSignIn(idToken);
    if (profile != null) return profile;

    final user = await repository.readCachedUser();
    _setSignedIn(user!);
    return null;
  }

  Future<void> completeGoogleSignUp({
    required GoogleProfile profile,
    required String role,
    required String phone,
    required bool acceptedTerms,
  }) async => _setSignedIn(
    await repository.completeGoogleSignUp(
      idToken: profile.idToken,
      role: role,
      phone: phone,
      acceptedTerms: acceptedTerms,
    ),
  );

  Future<void> restoreSession() async {
    if (!await repository.hasSession()) {
      return _setSignedOut();
    }
    final cached = await repository.readCachedUser();
    if (cached != null) _setSignedIn(cached);
    try {
      final user = await repository.fetchCurrentUser();
      if (cached == null || _status == AuthStatus.authenticated) {
        _setSignedIn(user);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) return _clearAndSignOut();
      // Keep the session when offline.
      if (cached == null) _setSignedOut();
    }
  }

  Future<void> login(String email, String password) async =>
      _setSignedIn(await repository.login(email, password));

  Future<void> verifyEmail(String email, String code) async =>
      _setSignedIn(await repository.verifyEmail(email, code));

  Future<void> logout() async {
    await _clearAndSignOut();
    try {
      await _google.signOut();
    } catch (e) {
      debugPrint('Google sign-out skipped: $e');
    }
  }

  void handleSessionExpired() {
    if (_status != AuthStatus.unauthenticated) _clearAndSignOut();
  }

  Future<void> _clearAndSignOut() async {
    await repository.clearSession();
    _setSignedOut();
  }

  void _setSignedIn(AuthUser user) {
    if (!user.canUseMobileApp) {
      _clearAndSignOut();
      return;
    }
    _user = user;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  void _setSignedOut() {
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
