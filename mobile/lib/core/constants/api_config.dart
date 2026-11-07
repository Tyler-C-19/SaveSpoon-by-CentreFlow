abstract final class ApiConfig {
  // Override with --dart-define=API_BASE_URL=...
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '787774110113-di4nmv9tmpplmdt87efoqamk23515vab.apps.googleusercontent.com',
  );

  static const Duration requestTimeout = Duration(seconds: 20);
}
