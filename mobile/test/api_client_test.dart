import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:savespoon/core/constants/api_config.dart';
import 'package:savespoon/core/network/api_client.dart';

ApiClient clientReturning(MockClientHandler handler) => ApiClient(
  client: MockClient(handler),
  baseUrl: 'http://test.local',
  timeout: const Duration(milliseconds: 50),
);

ApiClient slowClient(MockClientHandler handler) => ApiClient(
  client: MockClient(handler),
  baseUrl: 'http://test.local',
  timeout: const Duration(seconds: 5),
  slowAfter: const Duration(milliseconds: 20),
  longWaitAfter: const Duration(milliseconds: 80),
  tokenReader: () async => 'saved-token',
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

  test('waits up to 75 seconds; waking after 6, slow after 15', () {
    expect(ApiConfig.requestTimeout, const Duration(seconds: 75));
    expect(ApiConfig.slowAfter, const Duration(seconds: 6));
    expect(ApiConfig.longWaitAfter, const Duration(seconds: 15));
    expect(ApiConfig.idleAfter, const Duration(minutes: 14));
    final api = ApiClient(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(api.timeout, ApiConfig.requestTimeout);
    expect(api.slowAfter, ApiConfig.slowAfter);
    expect(api.longWaitAfter, ApiConfig.longWaitAfter);
    expect(api.idleAfter, ApiConfig.idleAfter);
  });

  test('waking turns on for a slow request and off when it answers', () async {
    final answer = Completer<http.Response>();
    final api = slowClient((_) => answer.future);

    final pending = api.get('/api/x');
    expect(api.serverWait.value, ServerWait.none);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(api.serverWait.value, ServerWait.waking);

    answer.complete(http.Response('{}', 200));
    await pending;
    expect(api.serverWait.value, ServerWait.none);
  });

  test('waking stays on until every slow request has finished', () async {
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    final answers = [first, second];
    final api = slowClient((_) => answers.removeAt(0).future);

    final one = api.get('/api/a');
    final two = api.get('/api/b');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(api.serverWait.value, ServerWait.waking);

    first.complete(http.Response('{}', 200));
    await one;
    expect(api.serverWait.value, ServerWait.waking);

    second.complete(http.Response(jsonEncode({'error': 'Nope'}), 400));
    await expectLater(two, throwsA(isA<ApiException>()));
    expect(api.serverWait.value, ServerWait.none);
  });

  test('a quick answer never shows a wait', () async {
    final api = slowClient((_) async => http.Response('{}', 200));
    var changes = 0;
    api.serverWait.addListener(() => changes++);

    await api.get('/api/x');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(api.serverWait.value, ServerWait.none);
    expect(changes, 0);
  });

  test('the wait clears when a slow request fails', () async {
    final api = slowClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      throw http.ClientException('x');
    });

    await expectLater(api.get('/api/x'), throwsA(isA<ApiException>()));
    expect(api.serverWait.value, ServerWait.none);
  });

  group('waking or slow', () {
    late DateTime now;
    late List<Completer<http.Response>> answers;
    late ApiClient api;

    setUp(() {
      now = DateTime(2026, 11, 9, 12);
      answers = [];
      api = ApiClient(
        client: MockClient((_) {
          final answer = Completer<http.Response>();
          answers.add(answer);
          return answer.future;
        }),
        baseUrl: 'http://test.local',
        timeout: const Duration(seconds: 5),
        slowAfter: const Duration(milliseconds: 20),
        longWaitAfter: const Duration(milliseconds: 80),
        clock: () => now,
      );
    });

    // Returns the state seen after [wait], then answers the request.
    Future<ServerWait> stateAfter(Duration wait, {http.Response? reply}) async {
      final pending = api.get('/api/x');
      await Future<void>.delayed(wait);
      final seen = api.serverWait.value;
      answers.last.complete(reply ?? http.Response('{}', 200));
      try {
        await pending;
      } on ApiException {
        // The state was already read.
      }
      return seen;
    }

    const shortWait = Duration(milliseconds: 40);
    const longWait = Duration(milliseconds: 120);

    test('the first request after opening the app shows waking', () async {
      expect(await stateAfter(shortWait), ServerWait.waking);
    });

    test('soon after an answer, a short wait shows nothing', () async {
      await stateAfter(shortWait);
      now = now.add(const Duration(minutes: 13, seconds: 59));
      expect(await stateAfter(shortWait), ServerWait.none);
    });

    test('soon after an answer, a long wait shows slow', () async {
      await stateAfter(shortWait);
      now = now.add(const Duration(minutes: 1));
      expect(await stateAfter(longWait), ServerWait.slow);
      expect(api.serverWait.value, ServerWait.none);
    });

    test('14 minutes without an answer shows waking again', () async {
      await stateAfter(shortWait);
      now = now.add(const Duration(minutes: 14));
      expect(await stateAfter(shortWait), ServerWait.waking);
    });

    test('an error reply from the server counts as an answer', () async {
      await stateAfter(
        shortWait,
        reply: http.Response(jsonEncode({'error': 'No'}), 400),
      );
      expect(await stateAfter(shortWait), ServerWait.none);
    });

    test('a connection failure does not count as an answer', () async {
      final failed = api.get('/api/x');
      await Future<void>.delayed(Duration.zero);
      answers.last.completeError(http.ClientException('x'));
      await expectLater(failed, throwsA(isA<ApiException>()));

      expect(await stateAfter(shortWait), ServerWait.waking);
    });

    test(
      "the host's 502, 503 or 504 page means the server may be starting",
      () async {
        for (final status in [502, 503, 504]) {
          await stateAfter(shortWait);
          now = now.add(const Duration(minutes: 1));
          await stateAfter(
            shortWait,
            reply: http.Response('<html>Service Unavailable</html>', status),
          );
          expect(
            await stateAfter(shortWait),
            ServerWait.waking,
            reason: '$status',
          );
        }
      },
    );
  });

  test(
    "the host's unavailable page gives the server-unavailable message",
    () async {
      for (final status in [502, 503, 504]) {
        final api = clientReturning(
          (_) async =>
              http.Response('<html>Service Unavailable</html>', status),
        );
        await expectLater(
          api.get('/api/x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', ServerMessages.unavailable)
                .having((e) => e.statusCode, 'statusCode', status),
          ),
        );
      }
    },
  );

  test('a 503 with the server\'s own message keeps that message', () async {
    final api = clientReturning(
      (_) async => http.Response(jsonEncode({'error': 'Try later'}), 503),
    );
    await expectLater(
      api.get('/api/x'),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', 'Try later'),
      ),
    );
  });

  test('server-down messages are listed for the plug icon', () {
    expect(ServerMessages.all, {
      'The server took too long to respond.',
      'Cannot reach the server.',
      'The server is unavailable right now. Try again in a minute.',
    });
  });

  group('after a timeout', () {
    late List<Completer<http.Response>> answers;
    late ApiClient api;

    setUp(() {
      answers = [];
      api = ApiClient(
        client: MockClient((_) {
          final answer = Completer<http.Response>();
          answers.add(answer);
          return answer.future;
        }),
        baseUrl: 'http://test.local',
        timeout: const Duration(milliseconds: 150),
        slowAfter: const Duration(milliseconds: 20),
        longWaitAfter: const Duration(milliseconds: 20),
      );
    });

    test('the banner hides, even for other requests still waiting', () async {
      final first = api.get('/api/a');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final second = api.get('/api/b');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(api.serverWait.value, isNot(ServerWait.none));

      await expectLater(
        first,
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            ServerMessages.timeout,
          ),
        ),
      );
      expect(api.serverWait.value, ServerWait.none);

      answers.last.complete(http.Response('{}', 200));
      await second;
    });

    test('new slow requests show no banner until the server answers', () async {
      await expectLater(api.get('/api/a'), throwsA(isA<ApiException>()));

      final waiting = api.get('/api/b');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.serverWait.value, ServerWait.none);
      answers.last.complete(http.Response('{}', 200));
      await waiting;

      final next = api.get('/api/c');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.serverWait.value, ServerWait.slow);
      answers.last.complete(http.Response('{}', 200));
      await next;
      expect(api.serverWait.value, ServerWait.none);
    });

    test("the host's unavailable page also brings the banner back", () async {
      await expectLater(api.get('/api/a'), throwsA(isA<ApiException>()));

      final down = api.get('/api/b');
      await Future<void>.delayed(Duration.zero);
      answers.last.complete(http.Response('<html>Unavailable</html>', 503));
      await expectLater(down, throwsA(isA<ApiException>()));

      final next = api.get('/api/c');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.serverWait.value, ServerWait.waking);
      answers.last.complete(http.Response('{}', 200));
      await next;
    });
  });

  test('wakeUp calls the health check without the saved token', () async {
    late http.Request sent;
    final api = slowClient((request) async {
      sent = request;
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    });

    await api.wakeUp();

    expect(sent.method, 'GET');
    expect(sent.url.toString(), 'http://test.local/api/health');
    expect(sent.headers.containsKey('Authorization'), isFalse);
  });

  test('wakeUp ignores errors and never reports an expired session', () async {
    var expired = 0;
    final api = ApiClient(
      client: MockClient((_) async => http.Response('{}', 401)),
      baseUrl: 'http://test.local',
      tokenReader: () async => 'saved-token',
      onUnauthorized: () => expired++,
    );
    await api.wakeUp();

    final down = clientReturning((_) async => throw http.ClientException('x'));
    await down.wakeUp();

    expect(expired, 0);
  });
}
