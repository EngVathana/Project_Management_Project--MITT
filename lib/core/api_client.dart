import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.status = 0, this.code = ''});
  final String message, code;
  final int status;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? base})
    : httpClient = client ?? http.Client(),
      base = base ?? _base();
  final http.Client httpClient;
  final String base;
  String? token;

  static String _base() {
    const configured = String.fromEnvironment('MITT_API_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) return '${Uri.base.origin}/api/v1';
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    return 'http://$host:8080/api/v1';
  }

  Uri url(String path, [Map<String, String>? query]) =>
      Uri.parse('$base$path').replace(queryParameters: query);

  Future<Object?> send(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    String? checkoutKey,
  }) async {
    final request = http.Request(method, url(path, query))
      ..headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (checkoutKey != null) request.headers['idempotency-key'] = checkoutKey;
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 25));
    } on Exception {
      throw const ApiFailure('Could not reach MITT. Try again.');
    }
    final Object? result;
    try {
      result = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiFailure(
        'MITT returned an invalid response.',
        status: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      final error = result is Json ? result : <String, dynamic>{};
      throw ApiFailure(
        error['message'] as String? ?? 'The request could not be completed.',
        status: response.statusCode,
        code: error['code'] as String? ?? '',
      );
    }
    return result;
  }

  Future<Json> object(
    String method,
    String path, {
    Json? body,
    String? checkoutKey,
  }) async =>
      await send(method, path, body: body, checkoutKey: checkoutKey) as Json;
  Future<List<Json>> list(String path, [Map<String, String>? query]) async =>
      (await send('GET', path, query: query) as List).cast<Json>();

  Future<int> upload(String purpose, String filename, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const ApiFailure('Choose a file between 1 byte and 5 MB.');
    }
    final uploaded = await object(
      'POST',
      '/files',
      body: {
        'purpose': purpose,
        'filename': filename,
        'data': base64Encode(bytes),
      },
    );
    return uploaded['id'] as int;
  }

  void close() => httpClient.close();
}

String money(int minorUnits) => '\$${(minorUnits / 100).toStringAsFixed(2)}';
String statusLabel(String raw) => switch (raw) {
  'placed' => 'Order placed',
  'on_delivery' => 'On delivery',
  'pet_owner' => 'Pet owner',
  'store_owner' => 'Pet store',
  _ => raw.isEmpty ? '' : '${raw[0].toUpperCase()}${raw.substring(1)}',
};
