import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/api_config.dart';
import '../../../core/network/api_client.dart';

abstract class GoogleAuthService {
  Future<String?> getIdToken();

  Future<void> signOut();
}

class PluginGoogleAuthService implements GoogleAuthService {
  Future<void>? _initialised;

  Future<void> _initialise() => _initialised ??= GoogleSignIn.instance
      .initialize(serverClientId: ApiConfig.googleServerClientId);

  @override
  Future<String?> getIdToken() async {
    try {
      await _initialise();
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('Google sign-in failed: ${e.code.name}');
      throw const ApiException('Google sign-in failed. Try again.');
    }
  }

  @override
  Future<void> signOut() async {
    await _initialise();
    await GoogleSignIn.instance.signOut();
  }
}
