import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import 'album_models.dart';
import 'albums_api.dart';
import 'collaborator_models.dart';
import 'collaborators_api.dart';
import 'sharing_api.dart';
import 'sharing_models.dart';

/// Fixed, user-facing messages — mirrors AuthController's pattern of never
/// surfacing a raw exception/backend detail to the UI.
const _genericErrorMessage = 'Ocurrió un error. Intenta de nuevo.';
const _notAvailableMessage = 'Este álbum no está disponible.';
const _sessionExpiredMessage = 'Tu sesión expiró. Vuelve a iniciar sesión.';
const _invitationNotUsableMessage =
    'Esta invitación no es válida, ya fue usada o expiró.';

/// Owns both the albums-list screen's state and the currently open album's
/// detail-screen state (spec04-ui-albumes.md, extended by
/// spec05-ui-colaboradores.md with collaborators/invitations state) — one
/// [ChangeNotifier], same pattern as [AuthController]/`PhotoUploadController`.
/// A single controller (not two/three) because every mutation that happens
/// on the detail screen also needs the list to be fresh once the user
/// navigates back to it, and this app has no DI/routing framework that would
/// make splitting them cleaner.
class AlbumsController extends ChangeNotifier {
  AlbumsController(this._api, this._collaboratorsApi, this._sharingApi);

  final AlbumsApi _api;
  final CollaboratorsApi _collaboratorsApi;
  final SharingApi _sharingApi;

  // --- Albums-list screen state ---
  bool isLoadingList = false;
  List<AlbumListItem> albums = [];
  String? listErrorMessage;

  // --- Currently open album's detail-screen state ---
  String? currentAlbumId;

  /// The caller's role in [currentAlbumId]. Carried over from the
  /// [AlbumListItem] used to navigate here — `AlbumDetail` (the backend
  /// response for `GET /albums/:id`) does NOT include a role field, only
  /// the combined list endpoint does (see `album_models.dart`).
  AlbumRole? currentAlbumRole;
  bool isLoadingDetail = false;
  AlbumDetail? albumDetail;
  String? detailErrorMessage;

  /// True while a create/rename/visibility/delete/associate/remove-photo
  /// call is in flight — lets screens disable their action buttons instead
  /// of allowing a second tap mid-request.
  bool isMutating = false;
  String? mutationErrorMessage;

  // --- Collaborators/invitations of the currently open album
  //     (spec05-ui-colaboradores.md) — owner-only surfaces on the backend
  //     side too, so these are only meaningful/loaded when
  //     `isCurrentAlbumOwner` is true. ---
  bool isLoadingCollaborators = false;
  List<CollaboratorListItem> collaborators = [];
  List<InvitationListItem> invitations = [];
  String? collaboratorsErrorMessage;

  /// Independent of `currentAlbumId`/owner state: accepting an invitation
  /// happens before the caller knows (or has open) the album it belongs to.
  bool isAcceptingInvitation = false;
  String? acceptInvitationErrorMessage;

  // --- Sharing (spec07-compartir-nfc-qr.md): share-link + NFC/QR tags of
  //     the currently open album — owner-only surfaces on the backend side
  //     too. ---

  /// Not loaded automatically when a detail screen opens — the backend's
  /// `POST .../share-link` is idempotent/harmless to call, but the UI still
  /// only fetches it on demand (the owner taps "Obtener enlace").
  bool isLoadingShareLink = false;
  ShareLink? shareLink;
  String? shareLinkErrorMessage;

  /// NFC/QR tags created during THIS screen session for the currently open
  /// album. Deliberately NOT fetched from the backend on open and NOT
  /// persisted anywhere by this app: there is no
  /// `GET /albums/:albumId/nfc-qr-tags` (list-by-album) endpoint — the
  /// backend only supports create-under-album and get/disable-by-own-id
  /// (see `SharingApi`'s doc comment and this app's CLAUDE.md). A tag
  /// created in a previous screen session (or on another device) keeps
  /// working — its `url` still resolves — but this list can't show it again
  /// until the backend grows a listing endpoint. Reset to `[]` whenever a
  /// *different* album is opened (see `loadAlbumDetail`).
  List<NfcQrTag> nfcQrTags = [];

  bool get isCurrentAlbumOwner => currentAlbumRole == AlbumRole.owner;

  Future<void> loadAlbums() async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();
    try {
      albums = await _api.listAlbums();
    } catch (error) {
      listErrorMessage = _messageFor(
        error,
        fallback: 'No se pudieron cargar los álbumes. Intenta de nuevo.',
      );
    }
    isLoadingList = false;
    notifyListeners();
  }

  /// Creates an album and, on success, refreshes the list. Returns the
  /// created album, or `null` on failure (see [mutationErrorMessage]).
  Future<AlbumSummary?> createAlbum(String name) async {
    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    AlbumSummary? created;
    try {
      created = await _api.createAlbum(name);
      await loadAlbums();
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return created;
  }

  /// Loads an album's detail and remembers [role] for the duration of this
  /// detail session (see `currentAlbumRole`'s doc).
  Future<void> loadAlbumDetail(String albumId, {required AlbumRole role}) async {
    if (currentAlbumId != albumId) {
      // Opening a genuinely different album (not just refreshing the same
      // one, e.g. after a photo upload): the previous album's share-link
      // and in-memory NFC/QR tags don't carry over — see `nfcQrTags`'s doc
      // comment for why the latter can't simply be re-fetched.
      shareLink = null;
      shareLinkErrorMessage = null;
      nfcQrTags = [];
    }
    currentAlbumId = albumId;
    currentAlbumRole = role;
    isLoadingDetail = true;
    detailErrorMessage = null;
    notifyListeners();

    try {
      albumDetail = await _api.getAlbumDetail(albumId);
    } catch (error) {
      albumDetail = null;
      detailErrorMessage = _messageFor(error);
    }

    isLoadingDetail = false;
    notifyListeners();
  }

  /// Re-fetches the currently open album's detail — used after an external
  /// batch (e.g. `PhotoUploadController.pickAndUploadPhotos`) finishes, so
  /// newly uploaded photos show up without leaving the screen.
  Future<void> refreshCurrentAlbumDetail() async {
    final albumId = currentAlbumId;
    final role = currentAlbumRole;
    if (albumId == null || role == null) return;
    await loadAlbumDetail(albumId, role: role);
  }

  /// Owner-only (enforced by the backend with a 404 for anyone else, and by
  /// the UI never exposing this action to a collaborator in the first
  /// place). Refreshes the open detail on success.
  Future<bool> renameCurrentAlbum(String name) =>
      _updateCurrentAlbum(name: name);

  /// Owner-only, same caveats as [renameCurrentAlbum].
  Future<bool> updateCurrentAlbumVisibility(AlbumVisibility visibility) =>
      _updateCurrentAlbum(visibility: visibility);

  Future<bool> _updateCurrentAlbum({String? name, AlbumVisibility? visibility}) async {
    final albumId = currentAlbumId;
    final role = currentAlbumRole;
    if (albumId == null || role == null) return false;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _api.updateAlbum(albumId, name: name, visibility: visibility);
      await loadAlbumDetail(albumId, role: role);
      succeeded = true;
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return succeeded;
  }

  /// Deletes the currently open album (owner-only) and refreshes the list
  /// so it's already gone once the caller navigates back to it. Returns
  /// `true` on success — the detail screen is responsible for popping
  /// itself off the navigation stack.
  Future<bool> deleteCurrentAlbum() async {
    final albumId = currentAlbumId;
    if (albumId == null) return false;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _api.deleteAlbum(albumId);
      succeeded = true;
      albumDetail = null;
      currentAlbumId = null;
      currentAlbumRole = null;
      await loadAlbums();
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return succeeded;
  }

  /// Removes a photo from the currently open album (relation only — never
  /// the photo or its storage file) and refreshes the detail.
  Future<void> removePhotoFromCurrentAlbum(String photoId) async {
    final albumId = currentAlbumId;
    final role = currentAlbumRole;
    if (albumId == null || role == null) return;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    try {
      await _api.removePhotoFromAlbum(albumId, photoId);
      await loadAlbumDetail(albumId, role: role);
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
  }

  /// Creates the currently open album's share-link if none exists yet, or
  /// returns the existing one — `POST .../share-link` is idempotent (see
  /// `SharingApi.createOrGetShareLink`), so calling this repeatedly (e.g. the
  /// user re-opens the "Compartir" section) is harmless. No-op if no album
  /// is currently open.
  Future<void> loadOrCreateShareLink() async {
    final albumId = currentAlbumId;
    if (albumId == null) return;

    isLoadingShareLink = true;
    shareLinkErrorMessage = null;
    notifyListeners();

    try {
      shareLink = await _sharingApi.createOrGetShareLink(albumId);
    } catch (error) {
      shareLinkErrorMessage = _messageFor(error);
    }

    isLoadingShareLink = false;
    notifyListeners();
  }

  /// Revokes the currently open album's share-link (owner-only). Idempotent
  /// on the backend (see `SharingApi.revokeShareLink`) — revoking again, or
  /// when there was never a link, still succeeds.
  Future<bool> revokeShareLink() async {
    final albumId = currentAlbumId;
    if (albumId == null) return false;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _sharingApi.revokeShareLink(albumId);
      succeeded = true;
      shareLink = null;
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return succeeded;
  }

  /// Creates a new NFC or QR tag for the currently open album (owner-only)
  /// and, on success, appends it to the in-memory [nfcQrTags] list (see its
  /// doc comment on why this list isn't backed by a re-fetchable backend
  /// list). Returns the created tag, or `null` on failure/no open album.
  Future<NfcQrTag?> createNfcQrTag(NfcQrTagType type) async {
    final albumId = currentAlbumId;
    if (albumId == null) return null;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    NfcQrTag? created;
    try {
      created = await _sharingApi.createNfcQrTag(albumId, type);
      nfcQrTags = [...nfcQrTags, created];
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return created;
  }

  /// Disables (soft-deletes, not reactivable) one of the in-memory
  /// [nfcQrTags] by its own id (owner-only). Idempotent on the backend — see
  /// `SharingApi.disableNfcQrTag`. Updates the tag's status locally on
  /// success rather than re-fetching it (the 204 response carries no body).
  Future<bool> disableNfcQrTag(String tagId) async {
    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _sharingApi.disableNfcQrTag(tagId);
      succeeded = true;
      nfcQrTags = [
        for (final tag in nfcQrTags)
          if (tag.id == tagId)
            tag.copyWith(status: NfcQrTagStatus.disabled)
          else
            tag,
      ];
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return succeeded;
  }

  /// Owner-only (enforced backend-side): loads both the collaborators and
  /// the pending/resolved invitations of the currently open album. No-op if
  /// no album is currently open.
  Future<void> loadCollaboratorsAndInvitations() async {
    final albumId = currentAlbumId;
    if (albumId == null) return;

    isLoadingCollaborators = true;
    collaboratorsErrorMessage = null;
    notifyListeners();

    try {
      collaborators = await _collaboratorsApi.listCollaborators(albumId);
      invitations = await _collaboratorsApi.listInvitations(albumId);
    } catch (error) {
      collaboratorsErrorMessage = _messageFor(error);
    }

    isLoadingCollaborators = false;
    notifyListeners();
  }

  /// Creates a new invitation for the currently open album (D12) and
  /// refreshes the invitations list. Returns the created invitation (its
  /// `url` is what the UI shares) on success, or `null` on failure (see
  /// [mutationErrorMessage]).
  Future<InvitationCreated?> createInvitation() async {
    final albumId = currentAlbumId;
    if (albumId == null) return null;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    InvitationCreated? created;
    try {
      created = await _collaboratorsApi.createInvitation(albumId);
      await loadCollaboratorsAndInvitations();
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return created;
  }

  /// Revokes a pending invitation of the currently open album (D13) and
  /// refreshes the invitations list on success.
  Future<bool> revokeInvitation(String invitationId) async {
    final albumId = currentAlbumId;
    if (albumId == null) return false;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _collaboratorsApi.revokeInvitation(albumId, invitationId);
      succeeded = true;
      await loadCollaboratorsAndInvitations();
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return succeeded;
  }

  /// Removes a collaborator from the currently open album (owner-only) and
  /// refreshes the collaborators list on success.
  Future<bool> removeCollaborator(String userId) async {
    final albumId = currentAlbumId;
    if (albumId == null) return false;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _collaboratorsApi.removeCollaborator(albumId, userId);
      succeeded = true;
      await loadCollaboratorsAndInvitations();
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return succeeded;
  }

  /// Leaves the currently open album (D5) — offered only to a collaborator
  /// (the backend rejects an owner with `CANNOT_LEAVE_AS_OWNER`). Clears the
  /// open detail and refreshes the albums list on success, same pattern as
  /// [deleteCurrentAlbum], since the caller no longer has access to it
  /// afterwards.
  Future<bool> leaveCurrentAlbum() async {
    final albumId = currentAlbumId;
    if (albumId == null) return false;

    isMutating = true;
    mutationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _collaboratorsApi.leaveAlbum(albumId);
      succeeded = true;
      albumDetail = null;
      currentAlbumId = null;
      currentAlbumRole = null;
      collaborators = [];
      invitations = [];
      await loadAlbums();
    } catch (error) {
      mutationErrorMessage = _messageFor(error);
    }

    isMutating = false;
    notifyListeners();
    return succeeded;
  }

  /// Accepts an invitation by its token or full URL (see
  /// `CollaboratorsApi.extractToken`) — deliberately independent of
  /// `currentAlbumId`/`currentAlbumRole`: the caller doesn't know (or have
  /// open) which album they're joining until this succeeds. Refreshes the
  /// albums list on success so the newly joined album shows up immediately.
  Future<bool> acceptInvitation(String tokenOrInvitationUrl) async {
    isAcceptingInvitation = true;
    acceptInvitationErrorMessage = null;
    notifyListeners();

    var succeeded = false;
    try {
      await _collaboratorsApi.acceptInvitation(tokenOrInvitationUrl);
      succeeded = true;
      await loadAlbums();
    } catch (error) {
      acceptInvitationErrorMessage = _messageFor(
        error,
        fallback: 'No se pudo aceptar la invitación. Intenta de nuevo.',
      );
    }

    isAcceptingInvitation = false;
    notifyListeners();
    return succeeded;
  }

  /// Maps an error to a fixed, user-facing message. A 401 always means the
  /// session JWT expired (spec02/A1.5's known, out-of-scope gap: no
  /// automatic refresh yet) — regardless of which call triggered it, so it
  /// takes priority over [fallback], the context-specific generic message.
  String _messageFor(Object error, {String fallback = _genericErrorMessage}) {
    if (error is AlbumNotAvailableException) return _notAvailableMessage;
    if (error is AlbumValidationException) return error.message;
    if (error is InvitationNotUsableException) return _invitationNotUsableMessage;
    if (error is CollaboratorActionNotAllowedException) return error.message;
    if (error is ApiException && error.statusCode == 401) {
      return _sessionExpiredMessage;
    }
    return fallback;
  }
}
