import '../api/api_client.dart';
import 'photo_models.dart';

/// Backend calls for spec03-fotografias.md, through the shared [ApiClient]
/// — never a bare `http` call. The photo's bytes never reach this class or
/// the backend; only Drive's `fileId` and best-effort metadata do.
class PhotosApi {
  const PhotosApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/photos`. Per memora-backend/spec08, the body is
  /// `storageRef: { fileId }` — NOT `driveFileId` — and `provider` is
  /// omitted (the backend defaults it to `'google-drive'`). Geolocation is
  /// never sent (D8). [albumId] is optional context (D11: without it, the
  /// photo lands only in the library).
  Future<Photo> registerPhoto({
    required String fileId,
    int? width,
    int? height,
    String? mimeType,
    int? sizeBytes,
    DateTime? capturedAt,
    String? albumId,
  }) async {
    final json = await _client.postJson('/photos', {
      'storageRef': {'fileId': fileId},
      'width': ?width,
      'height': ?height,
      'mimeType': ?mimeType,
      'sizeBytes': ?sizeBytes,
      if (capturedAt != null) 'capturedAt': capturedAt.toIso8601String(),
      'albumId': ?albumId,
    });
    return Photo.fromJson(json);
  }
}
