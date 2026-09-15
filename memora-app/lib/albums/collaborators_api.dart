import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'albums_api.dart' show AlbumNotAvailableException;
import 'collaborator_models.dart';

/// Thrown when `POST /api/v1/invitations/:token/accept` responds 410
/// `INVITATION_NOT_USABLE` — an invitation that's unknown, already
/// accepted/revoked, or expired. Deliberately distinct from
/// [AlbumNotAvailableException]: the backend itself distinguishes them (410
/// vs 404) because a token, unlike a guessed album id, was real input the
/// caller couldn't have gotten by chance (see
/// `memora-backend/src/albums/collaborators/collaborators.errors.ts`).
class InvitationNotUsableException implements Exception {
  const InvitationNotUsableException();

  @override
  String toString() => 'InvitationNotUsableException';
}

/// Thrown for a 400 on a collaborator-administration action — in practice
/// only reachable if the backend ever returns `CANNOT_REMOVE_OWNER` (from
/// [CollaboratorsApi.removeCollaborator]) or `CANNOT_LEAVE_AS_OWNER` (from
/// [CollaboratorsApi.leaveAlbum]), neither of which this app's UI should be
/// able to trigger on its own (owner is never offered "remove" on
/// themselves, and "leave" is never offered to an owner) — kept as a safety
/// net rather than assumed unreachable. [message] is always a fixed,
/// user-facing string, never a raw backend detail.
class CollaboratorActionNotAllowedException implements Exception {
  const CollaboratorActionNotAllowedException(this.message);

  final String message;

  @override
  String toString() => 'CollaboratorActionNotAllowedException($message)';
}

/// Backend calls for spec05-ui-colaboradores.md, through the shared
/// [ApiClient] — same `*Api` pattern as [AlbumsApi]/`PhotosApi`.
class CollaboratorsApi {
  const CollaboratorsApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/albums/:albumId/invitations` (owner-only, enforced
  /// backend-side with a 404 for anyone else — mapped to
  /// [AlbumNotAvailableException] like every other album-scoped 404 in this
  /// app).
  Future<InvitationCreated> createInvitation(String albumId) async {
    try {
      final json = await _client.postJson('/albums/$albumId/invitations');
      return InvitationCreated.fromJson(json);
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `GET /api/v1/albums/:albumId/invitations` (owner-only).
  Future<List<InvitationListItem>> listInvitations(String albumId) async {
    try {
      final list = await _client.getJsonList('/albums/$albumId/invitations');
      return list
          .map(
            (entry) => InvitationListItem.fromJson(entry as Map<String, dynamic>),
          )
          .toList();
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `DELETE /api/v1/albums/:albumId/invitations/:invitationId` (204,
  /// owner-only). Idempotent on the backend (revoking a non-pending
  /// invitation is a no-op) — this method doesn't need to special-case that.
  Future<void> revokeInvitation(String albumId, String invitationId) async {
    try {
      await _client.delete('/albums/$albumId/invitations/$invitationId');
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `POST /api/v1/invitations/:token/accept` (204, any authenticated user;
  /// deliberately not scoped under `/albums`, mirroring the backend's own
  /// separate controller — see
  /// `memora-backend/src/albums/collaborators/accept-invitation.controller.ts`).
  ///
  /// [tokenOrInvitationUrl] accepts either a bare token or the full
  /// invitation URL — see [extractToken].
  Future<void> acceptInvitation(String tokenOrInvitationUrl) async {
    final token = extractToken(tokenOrInvitationUrl);
    try {
      await _client.postJson('/invitations/$token/accept');
    } on ApiException catch (error) {
      if (error.statusCode == 410) {
        throw const InvitationNotUsableException();
      }
      rethrow;
    }
  }

  /// `GET /api/v1/albums/:albumId/collaborators` (owner-only — despite what
  /// spec05-ui-colaboradores.md's prose says about "owner o miembro", the
  /// backend's `CollaboratorsService.list` calls `requireOwner`; see this
  /// app's CLAUDE.md).
  Future<List<CollaboratorListItem>> listCollaborators(String albumId) async {
    try {
      final list = await _client.getJsonList('/albums/$albumId/collaborators');
      return list
          .map(
            (entry) =>
                CollaboratorListItem.fromJson(entry as Map<String, dynamic>),
          )
          .toList();
    } on ApiException catch (error) {
      throw _mapAlbumScopedError(error);
    }
  }

  /// `DELETE /api/v1/albums/:albumId/collaborators/:userId` (204,
  /// owner-only). A 400 `CANNOT_REMOVE_OWNER` becomes
  /// [CollaboratorActionNotAllowedException] — shouldn't be reachable from
  /// this app's UI (the owner is never listed as removable), kept as a
  /// safety net.
  Future<void> removeCollaborator(String albumId, String userId) async {
    try {
      await _client.delete('/albums/$albumId/collaborators/$userId');
    } on ApiException catch (error) {
      throw _mapCollaboratorActionError(error);
    }
  }

  /// `DELETE /api/v1/albums/:albumId/collaborators/me` (204). A 400
  /// `CANNOT_LEAVE_AS_OWNER` becomes [CollaboratorActionNotAllowedException]
  /// — shouldn't be reachable from this app's UI ("abandonar" is only
  /// offered to a collaborator), kept as a safety net.
  Future<void> leaveAlbum(String albumId) async {
    try {
      await _client.delete('/albums/$albumId/collaborators/me');
    } on ApiException catch (error) {
      throw _mapCollaboratorActionError(error);
    }
  }

  /// If [input] parses as an absolute URL (has a scheme, e.g. pasting the
  /// full `https://memora.app/invite/<token>`), returns its last non-empty
  /// path segment; otherwise returns [input] trimmed as-is (the user pasted
  /// a bare token). Exposed (not private) so it's directly unit-testable.
  static String extractToken(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
      if (segments.isNotEmpty) return segments.last;
    }
    return trimmed;
  }

  Exception _mapAlbumScopedError(ApiException error) {
    if (error.statusCode == 404) return const AlbumNotAvailableException();
    return error;
  }

  Exception _mapCollaboratorActionError(ApiException error) {
    if (error.statusCode == 404) return const AlbumNotAvailableException();
    if (error.statusCode == 400) {
      return switch (error.code) {
        'CANNOT_REMOVE_OWNER' => const CollaboratorActionNotAllowedException(
          'No puedes quitar al owner del álbum.',
        ),
        'CANNOT_LEAVE_AS_OWNER' => const CollaboratorActionNotAllowedException(
          'El owner no puede abandonar su propio álbum.',
        ),
        _ => CollaboratorActionNotAllowedException(error.message),
      };
    }
    return error;
  }
}
