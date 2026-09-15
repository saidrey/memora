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
  String? _refreshToken;

  /// Session access token to attach as `Authorization: Bearer <token>` on
  /// every subsequent request. Set by the auth layer after login/on
  /// startup, and cleared on logout — never logged.
  void setAccessToken(String? accessToken) => _accessToken = accessToken;

  /// Session refresh token, used only internally by the automatic-refresh
  /// interceptor in [_send] (`POST /auth/refresh`) — never attached to a
  /// request header. Set by the auth layer alongside the access token, and
  /// cleared on logout/session invalidation — never logged.
  void setRefreshToken(String? refreshToken) => _refreshToken = refreshToken;

  /// Invoked once an automatic refresh (triggered by a 401 on any request,
  /// see [_send]) succeeds, with the new tokens — so the auth layer can
  /// persist them (`SessionStorage`) and update its in-memory state.
  /// `ApiClient` deliberately doesn't know about `SessionStorage` itself;
  /// this hook is the same minimal-callback pattern as [setAccessToken]
  /// rather than a new event-bus abstraction.
  Future<void> Function(String accessToken, String refreshToken)?
  onSessionRefreshed;

  /// Invoked once an automatic-refresh attempt fails (no refresh token
  /// stored, or `POST /auth/refresh` itself fails/returns non-2xx) right
  /// after a session 401 — signals the auth layer to clear the stored
  /// session and sign the user out locally. The original 401 is still
  /// thrown to the caller afterwards as a safety net, in case the UI that
  /// triggered this request can't react to this hook fast enough.
  Future<void> Function()? onSessionInvalidated;

  /// Coalesces concurrent refresh attempts: while a refresh triggered by one
  /// request is in flight, any other request hitting a 401 at the same time
  /// awaits this same future instead of firing a second
  /// `POST /auth/refresh`.
  Future<bool>? _refreshInFlight;

  /// GETs [path] (relative to the configured base URL) and returns the
  /// decoded JSON body. Throws [ApiException] on network failure or any
  /// non-2xx response.
  Future<Map<String, dynamic>> getJson(String path) async {
    final decoded = await _send('GET', path, body: null);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// GETs [path] and returns the decoded JSON body as a list — for endpoints
  /// whose response is a bare JSON array (e.g. `GET /albums`), not an
  /// object. Throws [ApiException] on network failure or any non-2xx
  /// response.
  Future<List<dynamic>> getJsonList(String path) async {
    final decoded = await _send('GET', path, body: null);
    return decoded is List<dynamic> ? decoded : <dynamic>[];
  }

  /// POSTs [body] (JSON-encoded) to [path] and returns the decoded JSON
  /// response body. Throws [ApiException] on network failure or any non-2xx
  /// response.
  Future<Map<String, dynamic>> postJson(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    final decoded = await _send('POST', path, body: body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// PATCHes [body] (JSON-encoded) to [path] and returns the decoded JSON
  /// response body. Throws [ApiException] on network failure or any non-2xx
  /// response.
  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final decoded = await _send('PATCH', path, body: body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// DELETEs [path]. Most delete endpoints in this API return 204 with no
  /// body — the empty body is tolerated (never force-decoded as JSON), so
  /// this simply discards whatever (if anything) came back. Throws
  /// [ApiException] on network failure or any non-2xx response.
  Future<void> delete(String path) async {
    await _send('DELETE', path, body: null);
  }

  /// Sends the request and returns the decoded JSON body — a `Map`, a
  /// `List`, or `null` for an empty body (e.g. a 204) — centralizing error
  /// mapping to [ApiException] for every HTTP method. Callers decide what
  /// shape they expect (see `getJson` vs `getJsonList`).
  ///
  /// [isRetry] marks a request that's already been retried once after an
  /// automatic session refresh — it disables a further refresh attempt so a
  /// session that's still invalid after refreshing can't recurse.
  Future<dynamic> _send(
    String method,
    String path, {
    required Map<String, dynamic>? body,
    bool isRetry = false,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl${path.startsWith('/') ? path : '/$path'}',
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
    final encodedBody = body != null ? jsonEncode(body) : null;

    final http.Response response;
    try {
      response = switch (method) {
        'GET' => await _httpClient.get(uri, headers: headers),
        'POST' => await _httpClient.post(
          uri,
          headers: headers,
          body: encodedBody,
        ),
        'PATCH' => await _httpClient.patch(
          uri,
          headers: headers,
          body: encodedBody,
        ),
        'DELETE' => await _httpClient.delete(
          uri,
          headers: headers,
          body: encodedBody,
        ),
        _ => throw UnsupportedError('Unsupported HTTP method: $method'),
      };
    } catch (_) {
      throw const ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'No se pudo contactar al backend',
      );
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = decoded is Map<String, dynamic> ? decoded : null;
      final code = errorBody?['code'] as String? ?? 'UNKNOWN_ERROR';
      final exception = ApiException(
        statusCode: response.statusCode,
        code: code,
        message:
            errorBody?['message'] as String? ??
            'Error inesperado (HTTP ${response.statusCode})',
        requestId: errorBody?['requestId'] as String?,
      );

      // A 401 here means the session access token itself is expired/invalid
      // — distinct from Drive's own 401 (`DRIVE_REAUTHORIZATION_REQUIRED`),
      // which is unrelated to the session JWT and must never trigger a
      // session refresh. Only attempt this once per original request
      // (`!isRetry`) so a session that's still invalid after refreshing
      // doesn't recurse.
      final isSessionUnauthorized =
          exception.statusCode == 401 &&
          exception.code != 'DRIVE_REAUTHORIZATION_REQUIRED';
      if (isSessionUnauthorized && !isRetry) {
        final refreshed = await _refreshSession();
        if (refreshed) {
          return _send(method, path, body: body, isRetry: true);
        }
        await onSessionInvalidated?.call();
      }

      throw exception;
    }

    return decoded;
  }

  /// Coalesces concurrent refresh attempts behind [_refreshInFlight] and
  /// runs `POST /auth/refresh` at most once at a time. Returns `true` iff
  /// the session was successfully refreshed (and `_accessToken`/
  /// `_refreshToken` updated in memory, and [onSessionRefreshed] invoked).
  Future<bool> _refreshSession() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _performRefresh();
    _refreshInFlight = future;
    future.whenComplete(() => _refreshInFlight = null);
    return future;
  }

  /// The refresh call itself: deliberately NOT routed through [_send] —
  /// `POST /auth/refresh` has no guard (no Bearer needed/wanted) and
  /// reusing `_send` here would recurse into this same 401-handling code.
  /// Never throws: any failure (no refresh token stored, network error,
  /// non-2xx response, unexpected body shape) simply resolves to `false`.
  Future<bool> _performRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;

    final uri = Uri.parse('$_baseUrl/auth/refresh');
    http.Response response;
    try {
      response = await _httpClient.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sessionRefreshToken': refreshToken}),
      );
    } catch (_) {
      return false;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      return false;
    }
    if (decoded is! Map<String, dynamic>) return false;

    final newAccessToken = decoded['sessionAccessToken'] as String?;
    final newRefreshToken = decoded['sessionRefreshToken'] as String?;
    if (newAccessToken == null || newRefreshToken == null) return false;

    _accessToken = newAccessToken;
    _refreshToken = newRefreshToken;
    await onSessionRefreshed?.call(newAccessToken, newRefreshToken);
    return true;
  }

  void dispose() => _httpClient.close();
}
