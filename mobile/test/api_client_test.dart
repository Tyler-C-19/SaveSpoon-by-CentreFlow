import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:savespoon/core/network/api_client.dart';

ApiClient clientReturning(MockClientHandler handler) => ApiClient(
  client: MockClient(handler),
  baseUrl: 'http://test.local',
  timeout: const Duration(milliseconds: 50),
);

void main() {
  test('get returns decoded JSON and uses the base URL', () async {
    late Uri requested;
    final api = clientReturning((request) async {
      requested = request.url;
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    });

    expect(await api.get('/api/health'), {'status': 'ok'});
    expect(requested.toString(), 'http://test.local/api/health');
  });

  test('post sends a JSON body', () async {
    late http.Request sent;
    final api = clientReturning((request) async {
      sent = request;
      return http.Response('{}', 201);
    });

    await api.post('/api/x', body: {'a': 1});

    expect(sent.method, 'POST');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {'a': 1});
  });

  test('an error response uses the server message and status', () async {
    final api = clientReturning(
      (_) async => http.Response(jsonEncode({'error': 'Email in use'}), 409),
    );

    await expectLater(
      api.get('/api/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', 'Email in use')
            .having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('a non-JSON error falls back to a generic message', () async {
    final api = clientReturning((_) async => http.Response('<html>', 500));

    await expectLater(
      api.get('/api/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', 'Something went wrong.')
            .having((e) => e.statusCode, 'statusCode', 500),
      ),
    );
  });

  test('a connection failure gives a friendly error', () async {
    final api = clientReturning((_) async => throw http.ClientException('x'));

    await expectLater(
      api.get('/api/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', 'Cannot reach the server.')
            .having((e) => e.statusCode, 'statusCode', isNull),
      ),
    );
  });

  test('a slow server gives a timeout error', () async {
    final api = clientReturning((_) => Completer<http.Response>().future);

    await expectLater(
      api.get('/api/x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'The server took too long to respond.',
        ),
      ),
    );
  });
}
