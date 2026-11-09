import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:savespoon/features/auth/data/google_auth_service.dart';
import 'package:savespoon/features/auth/data/token_storage.dart';
import 'package:savespoon/features/auth/presentation/pages/splash_page.dart';
import 'package:savespoon/main.dart';

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage({this.token, this.userJson});

  String? token;
  String? userJson;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUserJson() async => userJson;

  @override
  Future<void> save({required String token, required String userJson}) async {
    this.token = token;
    this.userJson = userJson;
  }

  @override
  Future<void> clear() async {
    token = null;
    userJson = null;
  }
}

class FakeGoogleAuth implements GoogleAuthService {
  FakeGoogleAuth({this.idToken});

  String? idToken;
  int signOuts = 0;

  @override
  Future<String?> getIdToken() async => idToken;

  @override
  Future<void> signOut() async => signOuts++;
}

const userJson = {
  '_id': 'u1',
  'name': 'Test Person',
  'email': 'person@example.com',
  'role': 'customer',
};

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Future<void> startApp(
  WidgetTester tester, {
  required FakeTokenStorage storage,
  required MockClientHandler onRequest,
  GoogleAuthService? googleAuth,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    SaveSpoonApp(
      storage: storage,
      httpClient: MockClient((request) async {
        const browsePaths = {'/api/listings', '/api/listings/running-out'};
        return request.method == 'GET' && browsePaths.contains(request.url.path)
            ? jsonResponse({'listings': []})
            : onRequest(request);
      }),
      googleAuth: googleAuth ?? FakeGoogleAuth(),
    ),
  );
  await tester.pump();
  await tester.pump(SplashPage.displayTime);
  await tester.pumpAndSettle();
}
