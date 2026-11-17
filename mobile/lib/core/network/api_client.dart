import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;

  final int? statusCode;

  final String? code;

  @override
  String toString() => message;
}

// Messages for when the server itself can't answer.
abstract final class ServerMessages {
  static const String timeout = 'The server took too long to respond.';
  static const String unreachable = 'Cannot reach the server.';
  static const String unavailable =
      'The server is unavailable right now. Try again in a minute.';

  static const Set<String> all = {timeout, unreachable, unavailable};
}

enum ServerWait { none, waking, slow }

class ApiClient {
  ApiClient({
    http.Client? client,
    this.baseUrl = ApiConfig.baseUrl,
    this.timeout = ApiConfig.requestTimeout,
    this.slowAfter = ApiConfig.slowAfter,
    this.longWaitAfter = ApiConfig.longWaitAfter,
    this.idleAfter = ApiConfig.idleAfter,
    DateTime Function()? clock,
    this.tokenReader,
    this.onUnauthorized,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  final Duration slowAfter;
  final Duration longWaitAfter;
  final Duration idleAfter;
  final DateTime Function() _clock;
  final Future<String?> Function()? tokenReader;

  final void Function()? onUnauthorized;

  // waking: a request sent while the server may be asleep or starting has
  // waited longer than slowAfter. slow: any request has waited longer than
  // longWaitAfter.
  final ValueNotifier<ServerWait> serverWait = ValueNotifier(ServerWait.none);
  int _wakingRequests = 0;
  int _slowRequests = 0;
  bool _closed = false;
  DateTime? _lastAnswer;

  // After a request times out, the error screens explain the outage, so the
  // banner stays hidden until the next reply from the server or its host.
  bool _gaveUp = false;

  // The server may be asleep or starting if nothing has come back from it for
  // idleAfter, or its host last said it was unavailable.
  bool get _mayBeAsleep {
    final last = _lastAnswer;
    return last == null || _clock().difference(last) >= idleAfter;
  }

  Future<dynamic> get(String path) =>
      _send((headers) => _client.get(_uri(path), headers: headers));

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) => _send(
    (headers) =>
        _client.post(_uri(path), headers: headers, body: jsonEncode(body)),
  );

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) => _send(
    (headers) =>
        _client.patch(_uri(path), headers: headers, body: jsonEncode(body)),
  );

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) => _send(
    (headers) =>
        _client.put(_uri(path), headers: headers, body: jsonEncode(body)),
  );

  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) => _send(
    (headers) => _client.delete(
      _uri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ),
  );

  // Sends one file as multipart form data.
  Future<dynamic> putFile(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
  }) => _send((headers) async {
    final request = http.MultipartRequest('PUT', _uri(path))
      ..headers.addAll(headers..remove('Content-Type'))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(field, bytes, filename: filename),
      );
    return http.Response.fromStream(await _client.send(request));
  });

  // Starts a sleeping server early. Errors are ignored.
  Future<void> wakeUp() async {
    try {
      await _send(
        (headers) => _client.get(_uri('/api/health'), headers: headers),
        withToken: false,
      );
    } on Object {
      return;
    }
  }

  void close() {
    _closed = true;
    serverWait.dispose();
    _client.close();
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  void _updateWait({int waking = 0, int slow = 0}) {
    _wakingRequests += waking;
    _slowRequests += slow;
    if (_closed) return;
    serverWait.value = _gaveUp
        ? ServerWait.none
        : _wakingRequests > 0
        ? ServerWait.waking
        : _slowRequests > 0
        ? ServerWait.slow
        : ServerWait.none;
  }

  // Render answers 502, 503 or 504 with its own page while the server is
  // starting, suspended or down.
  bool _hostUnavailable(http.Response response, dynamic data) =>
      const {502, 503, 504}.contains(response.statusCode) &&
      !(data is Map && data['error'] is String);

  Future<dynamic> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool withToken = true,
  }) async {
    final token = withToken ? await tokenReader?.call() : null;
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final mayBeAsleep = _mayBeAsleep;
    var counted = false;
    final waitTimer = Timer(mayBeAsleep ? slowAfter : longWaitAfter, () {
      counted = true;
      mayBeAsleep ? _updateWait(waking: 1) : _updateWait(slow: 1);
    });

    final http.Response response;
    try {
      response = await request(headers).timeout(timeout);
    } on TimeoutException {
      _gaveUp = true;
      throw const ApiException(ServerMessages.timeout);
    } on SocketException {
      throw const ApiException(ServerMessages.unreachable);
    } on http.ClientException {
      throw const ApiException(ServerMessages.unreachable);
    } finally {
      waitTimer.cancel();
      if (counted) {
        mayBeAsleep ? _updateWait(waking: -1) : _updateWait(slow: -1);
      }
    }

    if (_gaveUp) {
      _gaveUp = false;
      _updateWait();
    }

    final data = _decode(response.body);
    if (_hostUnavailable(response, data)) {
      _lastAnswer = null;
      throw ApiException(
        ServerMessages.unavailable,
        statusCode: response.statusCode,
      );
    }
    _lastAnswer = _clock();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    if (response.statusCode == 401 && token != null) {
      onUnauthorized?.call();
    }

    final map = data is Map ? data : const {};
    throw ApiException(
      map['error'] is String ? map['error'] as String : 'Something went wrong.',
      statusCode: response.statusCode,
      code: map['code'] is String ? map['code'] as String : null,
    );
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
