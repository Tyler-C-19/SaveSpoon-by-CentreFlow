import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class ApiClient {
  ApiClient({
    http.Client? client,
    this.baseUrl = ApiConfig.baseUrl,
    this.timeout = ApiConfig.requestTimeout,
    this.tokenReader,
    this.onUnauthorized,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  final Future<String?> Function()? tokenReader;

  final void Function()? onUnauthorized;

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

  Future<dynamic> delete(String path) =>
      _send((headers) => _client.delete(_uri(path), headers: headers));

  void close() => _client.close();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final token = await tokenReader?.call();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      response = await request(headers).timeout(timeout);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on SocketException {
      throw const ApiException('Cannot reach the server.');
    } on http.ClientException {
      throw const ApiException('Cannot reach the server.');
    }

    final data = _decode(response.body);
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
