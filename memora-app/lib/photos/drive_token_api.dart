import '../api/api_client.dart';
import '../api/api_exception.dart';

/// A short-lived Google Drive access token (`scope: drive.file`), obtained
/// from memora-backend, plus its computed expiry. Lives only in memory for
/// the duration of a photo-upload batch — never persisted, never logged.
class DriveToken {
  const DriveToken({required this.accessToken, required this.expiresAt});

  final String accessToken;
  final DateTime expiresAt;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);
}

/// Thrown when memora-backend reports that the user's Google Drive
/// authorization needs to be renewed (401 `DRIVE_REAUTHORIZATION_REQUIRED`).
/// The actual re-authorization flow is `AuthController.reconnectDrive()`
/// (spec06-sesion-y-reauth-drive.md, A1.6) — this exception only lets
/// callers detect and surface the situation without leaking the underlying
/// [ApiException].
class DriveReauthorizationRequiredException implements Exception {
  const DriveReauthorizationRequiredException();

  @override
  String toString() => 'DriveReauthorizationRequiredException';
}

/// Calls `POST /api/v1/auth/drive-token` through the shared [ApiClient]
/// (which already attaches the session Bearer token) — never a bare `http`
/// call, and this is the only place that touches this endpoint.
class DriveTokenApi {
  const DriveTokenApi(this._client);

  final ApiClient _client;

  /// Safety margin subtracted from the server-reported `expiresIn` so the
  /// batch renews the token slightly before Google actually rejects it.
  static const _expiryMargin = Duration(seconds: 30);

  Future<DriveToken> getDriveToken() async {
    try {
      final json = await _client.postJson('/auth/drive-token');
      final accessToken = json['driveAccessToken'] as String;
      final expiresInSeconds = json['expiresIn'] as int;
      final ttl = Duration(seconds: expiresInSeconds) - _expiryMargin;
      return DriveToken(
        accessToken: accessToken,
        expiresAt: DateTime.now().add(ttl.isNegative ? Duration.zero : ttl),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401 &&
          error.code == 'DRIVE_REAUTHORIZATION_REQUIRED') {
        throw const DriveReauthorizationRequiredException();
      }
      rethrow;
    }
  }
}
