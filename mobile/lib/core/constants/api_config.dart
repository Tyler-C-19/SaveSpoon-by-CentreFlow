import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  // Override with --dart-define=API_BASE_URL=...
  // Release builds use the hosted server, debug builds the emulator's view of this computer.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kReleaseMode
        ? 'https://api.savespoon.com'
        : 'http://10.0.2.2:5000',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '787774110113-di4nmv9tmpplmdt87efoqamk23515vab.apps.googleusercontent.com',
  );

  // The free hosted server can take up to a minute to start after sleeping.
  static const Duration requestTimeout = Duration(seconds: 75);

  static const Duration slowAfter = Duration(seconds: 6);

  static const Duration longWaitAfter = Duration(seconds: 15);

  // Render sleeps after 15 minutes without a request.
  static const Duration idleAfter = Duration(minutes: 14);
}
