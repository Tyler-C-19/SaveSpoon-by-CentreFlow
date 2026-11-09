import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/google_auth_service.dart';
import 'features/auth/data/token_storage.dart';
import 'features/auth/presentation/providers/auth_provider.dart';

void main() {
  runApp(const SaveSpoonApp());
}

class SaveSpoonApp extends StatefulWidget {
  const SaveSpoonApp({
    super.key,
    this.storage,
    this.httpClient,
    this.googleAuth,
  });

  final TokenStorage? storage;
  final http.Client? httpClient;
  final GoogleAuthService? googleAuth;

  @override
  State<SaveSpoonApp> createState() => _SaveSpoonAppState();
}

class _SaveSpoonAppState extends State<SaveSpoonApp> {
  final AuthProvider _auth = AuthProvider();
  late final ApiClient _api;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final storage = widget.storage ?? SecureTokenStorage();
    _api = ApiClient(
      client: widget.httpClient,
      tokenReader: storage.readToken,
      onUnauthorized: _auth.handleSessionExpired,
    );
    _auth.attach(
      AuthRepository(api: _api, storage: storage),
      widget.googleAuth ?? PluginGoogleAuthService(),
    );
    _auth.restoreSession();
    _router = createAppRouter(_auth);
  }

  @override
  void dispose() {
    _router.dispose();
    _auth.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: _auth,
      child: MaterialApp.router(
        title: 'SaveSpoon',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
