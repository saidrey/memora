import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'album_models.dart';

/// Thrown for a 404 on any album operation — an album that doesn't exist
/// and an album that exists but the caller isn't a member of are
/// deliberately indistinguishable here (spec04-ui-albumes.md: "un 404 al
/// operar sobre álbum ajeno/inexistente SHALL tratarse como 'no disponible'
/// sin revelar existencia").
class AlbumNotAvailableException implements Exception {
  const AlbumNotAvailableException();

  @override
  String toString() => 'AlbumNotAvailableException';
}

/// Thrown for a 400 on create/update, or for a client-side validation
/// failure caught before the request is even sent (e.g. an empty or
/// too-long name) — [message] is always a fixed, user-facing string, never
/// a raw backend/internal detail.
class AlbumValidationException implements Exception {
  const AlbumValidationException(this.message);

  final String message;

  @override
  String toString() => 'AlbumValidationException($message)';
}

/// Backend calls for spec04-ui-albumes.md, through the shared [ApiClient] —
/// never a bare `http` call, same `*Api` pattern as [PhotosApi]/
/// `DriveTokenApi`.
class AlbumsApi {
  const AlbumsApi(this._client);

  final ApiClient _client;

  /// Mirrors `MAX_ALBUM_NAME_LENGTH` in `memora-backend`'s
  /// `albums.controller.ts` — validated here too so a bad name never even
  /// reaches the network, though the backend's own 400 is still mapped
  /// cleanly if it somehow gets there.
  static const maxNameLength = 100;

  /// `POST /api/v1/albums`. [visibility] is intentionally omitted by every
  /// caller in this app today (decision D: the create screen doesn't offer
  /// it) — every new album is born `PRIVATE` by the backend's own default.
  /// The parameter still exists (mirroring the backend's own optional
  /// `visibility` on create) so this method's contract isn't artificially
  /// narrower than the endpoint it calls.
  Future<AlbumSummary> createAlbum(String name, {AlbumVisibility? visibility}) async {
    final trimmed = _validatedName(name);
    try {
      final json = await _client.postJson('/albums', {
        'name': trimmed,
        'visibility': ?visibility?.toJson(),
      });
      return AlbumSummary.fromJson(json);
    } on ApiException catch (error) {
      throw _mapWriteError(error);
    }
  }

  /// `GET /api/v1/albums` — a bare JSON array (own albums + albums the
  /// caller collaborates on), not an object; see [ApiClient.getJsonList].
  Future<List<AlbumListItem>> listAlbums() async {
    final list = await _client.getJsonList('/albums');
    return list
        .map((entry) => AlbumListItem.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/v1/albums/:id`. A 404 (ajeno o inexistente) becomes
  /// [AlbumNotAvailableException].
  Future<AlbumDetail> getAlbumDetail(String id) async {
    try {
      final json = await _client.getJson('/albums/$id');
      return AlbumDetail.fromJson(json);
    } on ApiException catch (error) {
      throw _mapReadError(error);
    }
  }

  /// `PATCH /api/v1/albums/:id` with `name` and/or `visibility` — at least
  /// one is required, validated here (client-side) before ever calling the
  /// backend, mirroring the 400 `INVALID_REQUEST` it would otherwise return
  /// for an empty patch. Owner-only; a 404 (not owner, or doesn't exist)
  /// becomes [AlbumNotAvailableException].
  Future<AlbumSummary> updateAlbum(
    String id, {
    String? name,
    AlbumVisibility? visibility,
  }) async {
    if (name == null && visibility == null) {
      throw const AlbumValidationException(
        'Debes indicar un nombre o una visibilidad nuevos.',
      );
    }
    final trimmedName = name != null ? _validatedName(name) : null;
    try {
      final json = await _client.patchJson('/albums/$id', {
        'name': ?trimmedName,
        'visibility': ?visibility?.toJson(),
      });
      return AlbumSummary.fromJson(json);
    } on ApiException catch (error) {
      throw _mapWriteError(error);
    }
  }

  /// `DELETE /api/v1/albums/:id` (204). Owner-only; deletes only the
  /// grouping and its relations, never the photos or their Drive files
  /// (D16) — enforced backend-side, the app just calls it.
  Future<void> deleteAlbum(String id) async {
    try {
      await _client.delete('/albums/$id');
    } on ApiException catch (error) {
      throw _mapReadError(error);
    }
  }

  /// `POST /api/v1/albums/:albumId/photos` (204) — associates an existing
  /// photo of the caller's with the album (N:M, idempotent).
  Future<void> addPhotoToAlbum(String albumId, String photoId) async {
    try {
      await _client.postJson('/albums/$albumId/photos', {'photoId': photoId});
    } on ApiException catch (error) {
      throw _mapReadError(error);
    }
  }

  /// `DELETE /api/v1/albums/:albumId/photos/:photoId` (204) — removes only
  /// the relation, never the photo or its storage file.
  Future<void> removePhotoFromAlbum(String albumId, String photoId) async {
    try {
      await _client.delete('/albums/$albumId/photos/$photoId');
    } on ApiException catch (error) {
      throw _mapReadError(error);
    }
  }

  String _validatedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AlbumValidationException(
        'El nombre del álbum no puede estar vacío.',
      );
    }
    if (trimmed.length > maxNameLength) {
      throw const AlbumValidationException(
        'El nombre del álbum no puede superar los 100 caracteres.',
      );
    }
    return trimmed;
  }

  Exception _mapReadError(ApiException error) {
    if (error.statusCode == 404) return const AlbumNotAvailableException();
    return error;
  }

  Exception _mapWriteError(ApiException error) {
    if (error.statusCode == 404) return const AlbumNotAvailableException();
    if (error.statusCode == 400) return AlbumValidationException(error.message);
    return error;
  }
}
