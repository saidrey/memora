import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

/// Single entry point for talking to memora-backend. Every request to the
/// API must go through this client rather than a bare `http.get`/`http.post`
/// with an embedded URL — per global/spec01-estructura-monorepo.md ("los
/// clientes solo acceden a través de la API") and
/// memora-app/spec01-fundacion-app.md.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? http.Client(),
      _baseUrl = (baseUrl ?? apiBaseUrl).replaceAll(RegExp(r'/+$'), '');

  final http.Client _httpClient;
  final String _baseUrl;
  String? _accessToken;

  /// Session access token to attach as `Authorization: Bearer <token>` on
  /// every subsequent request. Set by the auth layer after login/on
  /// startup, and cleared on logout — never logged.
  void setAccessToken(String? accessToken) => _accessToken = accessToken;

  /// GETs [path] (relative to the configured base URL) and returns the
  /// decoded JSON body. Throws [ApiException] on network failure or any
  /// non-2xx response.
  Future<Map<String, dynamic>> getJson(String path) {
    return _send('GET', path, body: null);
  }

  /// POSTs [body] (JSON-encoded) to [path] and returns the decoded JSON
  /// response body. Throws [ApiException] on network failure or any non-2xx
  /// response.
  Future<Map<String, dynamic>> postJson(
    String path, [
    Map<String, dynamic> body = const {},
  ]) {
    return _send('POST', path, body: body);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    required Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl${path.startsWith('/') ? path : '/$path'}',
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };

    final http.Response response;
    try {
      response = method == 'GET'
          ? await _httpClient.get(uri, headers: headers)
          : await _httpClient.post(
              uri,
              headers: headers,
              body: body != null ? jsonEncode(body) : null,
            );
    } catch (_) {
      throw const ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'No se pudo contactar al backend',
      );
    }

    Map<String, dynamic>? decodedBody;
    try {
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) decodedBody = decoded;
    } catch (_) {
      decodedBody = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        code: decodedBody?['code'] as String? ?? 'UNKNOWN_ERROR',
        message:
            decodedBody?['message'] as String? ??
            'Error inesperado (HTTP ${response.statusCode})',
        requestId: decodedBody?['requestId'] as String?,
      );
    }

    return decodedBody ?? <String, dynamic>{};
  }

  void dispose() => _httpClient.close();
}
