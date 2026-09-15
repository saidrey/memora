import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'albums_api.dart' show AlbumNotAvailableException;
import 'sharing_models.dart';

/// Backend calls for spec07-compartir-nfc-qr.md: the album's share-link (M7,
/// `memora-backend/spec09-compartir-visor.md`) and its NFC/QR tags (M8,
/// `memora-backend/spec10-nfc-qr.md`) — through the shared [ApiClient], same
/// `*Api` pattern as [AlbumsApi]/[CollaboratorsApi].
///
/// Route shapes, confirmed against the backend's own controllers (not just
/// the spec's prose):
/// - Share-link routes hang off the album (`/albums/:albumId/share-link`) —
///   `NfcQrTagsController` and `AlbumShareLinkController`-equivalent both
///   live under `/albums`.
/// - Creating a tag also hangs off the album
///   (`POST /albums/:albumId/nfc-qr-tags`) — this endpoint has NO dedup, it
///   always creates a new tag.
/// - Getting/disabling a tag does NOT: `GET /nfc-qr-tags/:id` and
///   `PATCH /nfc-qr-tags/:id/disable` are a *separate* controller
///   (`NfcQrTagController`) addressed only by the tag's own id, never
///   nested under `/albums/:albumId`. Do not "fix" these into a nested
///   shape — that would be wrong.
class SharingApi {
  const SharingApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/albums/:albumId/share-link` (owner-only). Idempotent:
  /// returns the album's existing link if one was already created, or
  /// creates it otherwise — there is deliberately no separate GET for this,
  /// calling this again *is* how the app "reads" the current link.
  Future<ShareLink> createOrGetShareLink(String albumId) async {
    try {
      final json = await _client.postJson('/albums/$albumId/share-link');
      return ShareLink.fromJson(json);
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `DELETE /api/v1/albums/:albumId/share-link` (204, owner-only).
  /// Idempotent on the backend — revoking when there was no link, or one
  /// already revoked, is a no-op rather than an error.
  Future<void> revokeShareLink(String albumId) async {
    try {
      await _client.delete('/albums/$albumId/share-link');
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `POST /api/v1/albums/:albumId/nfc-qr-tags` (owner-only). Always creates
  /// a brand-new tag — an album can have several, there's no dedup by
  /// [type] or otherwise.
  Future<NfcQrTag> createNfcQrTag(String albumId, NfcQrTagType type) async {
    try {
      final json = await _client.postJson('/albums/$albumId/nfc-qr-tags', {
        'type': type.toJson(),
      });
      return NfcQrTag.fromJson(json);
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `GET /api/v1/nfc-qr-tags/:tagId` (owner-only) — note: NOT nested under
  /// `/albums/:albumId`, see the class doc comment.
  Future<NfcQrTag> getNfcQrTag(String tagId) async {
    try {
      final json = await _client.getJson('/nfc-qr-tags/$tagId');
      return NfcQrTag.fromJson(json);
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `PATCH /api/v1/nfc-qr-tags/:tagId/disable` (204, owner-only) — note:
  /// NOT nested under `/albums/:albumId`, see the class doc comment.
  /// Idempotent (soft-delete): disabling an already-disabled tag is a no-op,
  /// never an error. Not reactivable in this MVP.
  Future<void> disableNfcQrTag(String tagId) async {
    try {
      await _client.patchJson('/nfc-qr-tags/$tagId/disable', const {});
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// A 404 here is always "not yours or doesn't exist" — for the share-link
  /// it hangs off an album (so it reuses [AlbumNotAvailableException]
  /// directly, like every other album-scoped 404 in this app); for a tag,
  /// the same message is conceptually accurate ("not available") even
  /// though the resource itself isn't literally an album, so it's reused
  /// rather than introducing a near-duplicate exception type.
  Exception _mapAlbumScopedError(ApiException error) {
    if (error.statusCode == 404) return const AlbumNotAvailableException();
    return error;
  }
}
