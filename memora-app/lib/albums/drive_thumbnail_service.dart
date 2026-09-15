import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../photos/drive_token_api.dart';

/// Thrown on any failure downloading a thumbnail from Drive that ISN'T
/// [DriveReauthorizationRequiredException] (network, non-2xx, etc.) — never
/// carries token contents.
class DriveThumbnailException implements Exception {
  const DriveThumbnailException(this.message);

  final String message;

  @override
  String toString() => 'DriveThumbnailException($message)';
}

/// Downloads photo thumbnails straight from Google Drive using each photo's
/// `storageRef.fileId` plus the app's short-lived `driveAccessToken`
/// (spec04-ui-albumes.md, decision A) — via `GET
/// https://www.googleapis.com/drive/v3/files/{fileId}?alt=media`, the same
/// "no Drive SDK, plain `http` against `googleapis.com`" pattern as
/// `DriveUploadService`. Deliberately NOT Drive's `thumbnailLink`/
/// `webContentLink`: those need separate Google auth and expire, and
/// `drive.file` scope doesn't reliably expose `thumbnailLink` for files the
/// app itself didn't just create in the same session.
///
/// Caching: an in-memory `Map<fileId, bytes>` with no expiry or size cap —
/// this app only opens one album detail screen at a time and a session's
/// worth of thumbnails is small, so a simple unbounded map is enough for
/// this scope (documented here rather than added speculatively: a real
/// LRU/disk cache is a future improvement if this stops being true).
///
/// Token sharing: this service keeps its OWN small `DriveToken` cache
/// rather than reusing `PhotoUploadController`'s. It's still handed the
/// SAME `DriveTokenApi` instance from `main.dart` (a stateless wrapper
/// around `ApiClient`, so sharing it costs nothing and avoids a pointless
/// second object), but the *cached token* itself is kept separate because
/// the two callers have different lifecycles: a photo-upload batch is
/// short-lived and clears its cache when the batch ends, while the album
/// detail screen keeps requesting thumbnails for as long as it's open.
/// `POST /auth/drive-token` is cheap and idempotent, so the rare case where
/// both request a token at the same moment just costs one extra call —
/// an acceptable trade for not coupling two independent controllers
/// through shared mutable state.
class DriveThumbnailService {
  DriveThumbnailService({required this.driveTokenApi, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final DriveTokenApi driveTokenApi;
  final http.Client _httpClient;

  static const _filesEndpoint = 'https://www.googleapis.com/drive/v3/files';

  DriveToken? _cachedToken;
  final Map<String, Uint8List> _cache = {};

  /// Returns the raw image bytes for [fileId] — from the in-memory cache
  /// when available. Lets [DriveReauthorizationRequiredException] propagate
  /// unwrapped so callers can show the specific "reconectar Drive" message
  /// (spec04: "si falta el drive-token... la app SHALL avisar sin romper la
  /// pantalla"); any other failure surfaces as [DriveThumbnailException].
  Future<Uint8List> getThumbnail(String fileId) async {
    final cached = _cache[fileId];
    if (cached != null) return cached;

    final token = await _ensureDriveToken();
    final uri = Uri.parse(
      '$_filesEndpoint/$fileId',
    ).replace(queryParameters: {'alt': 'media'});

    final http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: {'Authorization': 'Bearer ${token.accessToken}'},
      );
    } catch (_) {
      throw const DriveThumbnailException('No se pudo cargar la miniatura.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const DriveThumbnailException('No se pudo cargar la miniatura.');
    }

    final bytes = response.bodyBytes;
    _cache[fileId] = bytes;
    return bytes;
  }

  Future<DriveToken> _ensureDriveToken() async {
    final cached = _cachedToken;
    if (cached != null && !cached.isExpired) return cached;
    final token = await driveTokenApi.getDriveToken();
    _cachedToken = token;
    return token;
  }

  /// Empties the in-memory thumbnail cache and drops the cached Drive token
  /// (spec06-sesion-y-reauth-drive.md, A1.6): called after a successful
  /// Google Drive reconnect so the next `getThumbnail` call for every photo
  /// actually re-fetches — both the bytes (the old cached ones may be
  /// missing entirely for files that failed before) and the token (the one
  /// cached here predates the reconnect and may be tied to the stale
  /// authorization). Callers pair this with forcing their thumbnail widgets
  /// to rebuild (e.g. bumping an "epoch" in a `ValueKey`) — clearing this
  /// cache alone doesn't do that on its own.
  void clearCache() {
    _cache.clear();
    _cachedToken = null;
  }

  void dispose() => _httpClient.close();
}
