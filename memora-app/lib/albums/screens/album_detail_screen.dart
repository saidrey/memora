import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/auth_controller.dart';
import '../../auth/drive_reconnect_prompt.dart';
import '../../design/design.dart';
import '../../photos/drive_token_api.dart';
import '../../photos/photo_models.dart';
import '../../photos/photo_upload_controller.dart';
import '../album_models.dart';
import '../albums_controller.dart';
import '../collaborator_models.dart';
import '../drive_thumbnail_service.dart';
import '../sharing_models.dart';
import 'album_card_style.dart';
import 'nfc_programming_screen.dart';
import 'photo_viewer_screen.dart';

/// Which section of the screen is currently shown below the hero (mockup
/// redesign, sin spec de Kiro — ver CLAUDE.md): replaces the old single
/// `showModalBottomSheet` trigger with 3 inline tabs. `sharing` is only ever
/// reachable for an owner (see `AlbumDetailScreen`'s AppBar/tab-bar building
/// logic) — the sharing section itself has always been 100% owner-only (M7/
/// M8), so there is no meaningful "Compartir" content for a collaborator to
/// switch to.
enum _AlbumTab { photos, collaborators, sharing }

/// Client-side-only presentation order for the "Fotos" tab's grid — see
/// `_AlbumDetailScreenState._sortedPhotos`.
enum _PhotoSortOrder {
  newestFirst,
  oldestFirst;

  String get label =>
      this == _PhotoSortOrder.newestFirst ? 'Más recientes' : 'Más antiguas';
}

/// Hand-rolled Spanish date formatting for the hero's "Creado el ..." line
/// (e.g. "12 sep. 2026") — no new date-formatting package, per the redesign
/// brief. Distinct from `_AlbumDetailScreenState._formatDate` (which stays
/// `dd/mm/yyyy`, used for invitation/tag expiry elsewhere on this screen);
/// this one is specific to the hero's metadata row.
String _formatDateEs(DateTime date) {
  const months = [
    'ene.',
    'feb.',
    'mar.',
    'abr.',
    'may.',
    'jun.',
    'jul.',
    'ago.',
    'sep.',
    'oct.',
    'nov.',
    'dic.',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Initials for the current user's own `_EntityRow` avatar (mockup redesign,
/// sin spec de Kiro — ver CLAUDE.md), derived from a real display name when
/// available and from [fallback] (the email, already resolved by the caller)
/// otherwise — never from `userId` (unlike [_initialsFromId] below), since
/// this row is specifically the one case where a real name/email IS
/// available (`AuthController.user`, already loaded for this screen).
String _personInitials(String? name, String fallback) {
  final source = (name != null && name.trim().isNotEmpty)
      ? name.trim()
      : fallback.trim();
  if (source.isEmpty) return '?';
  final parts = source.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
}

/// Initials for another collaborator's `_EntityRow` avatar — same logic the
/// old `_CollaboratorAvatarStack._initialsFor` used, kept as a free function
/// since that widget is gone. `CollaboratorListItem` only carries `userId`
/// (no name/email — a real backend limitation, see CLAUDE.md/README.md), so
/// this is the only material available to derive initials from.
String _initialsFromId(String userId) {
  final trimmed = userId.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
}

/// Album detail screen (spec04-ui-albumes.md): a grid of the album's photo
/// thumbnails (fetched from Drive, decision A), "agregar fotos" (reusing
/// `PhotoUploadController.pickAndUploadPhotos` with this album's id, per
/// decision C), removing a photo from the album, and — owner-only —
/// renaming, changing visibility, and deleting the album (D1: hidden
/// entirely for a collaborator, never just disabled).
///
/// Extended by spec05-ui-colaboradores.md with, still owner-only: inviting
/// (D12, share sheet), the collaborators list ("quitar"), and pending
/// invitations ("revocar", D13) — plus, for a collaborator, a single
/// "Abandonar álbum" action (D5). Deliberately kept in this same screen
/// rather than a separate one, per spec05's own recommendation.
///
/// Extended again by spec07-compartir-nfc-qr.md with a "Compartir"
/// section, still owner-only: obtain/share/revoke the album's share-link
/// (M7), and create/render/block NFC or QR tags (M8) — see
/// `_buildSharingSection`.
///
/// Visual layer redone in Fase 2 del rediseño "Aurora" (sin spec de Kiro):
/// an image-led hero (`_AlbumHero`/`_HeroPhotoImage`) using the album's
/// first photo (or a deterministic gradient fallback when there are none)
/// with `MemoraCurvedHero`'s asymmetric wave seam into the content below,
/// a two-column photo grid restyled with `lib/design/` tokens/components,
/// and the sharing/collaborators sections rebuilt with `MemoraCard`/
/// `MemoraBadge`/`MemoraSecondaryButton` instead of raw `Card`/`ListTile`/
/// `TextButton`. None of the controller/API/model logic changed — see
/// CLAUDE.md's "Fase 2" section for the gotchas preserved as-is (the
/// `ValueKey('${photo.id}#$_epoch')` pattern, the owner-only gating, the
/// Drive-reauth distinction) and the new pieces added for this screen.
///
/// Restructured again in a post-feedback pass (sin spec de Kiro, "más
/// dinamismo y menos ruido visual"): the sharing/collaborators content
/// (`_buildSharingSection`/`_buildOwnerCollaboratorsSection`/
/// `_buildCollaboratorSection`) moved out of the main `CustomScrollView`
/// into a `showModalBottomSheet` opened from a single AppBar trigger
/// (`_openSharingSheet`) — same widgets, same controller calls, same
/// owner-only gating, only relocated so the photo grid (this screen's
/// actual content) isn't competing with an always-expanded admin section.
/// Removing a photo now requires an explicit confirmation
/// (`_confirmRemovePhoto`) before `removePhotoFromCurrentAlbum` is ever
/// called. The photo grid's entrance is a real `flutter_animate` stagger
/// (fade + scale) instead of appearing instantly, and the hero shares a
/// `Hero` transition with `AlbumsListScreen`'s `_AlbumGridCard` (see
/// `_AlbumHero`'s doc comment for why the `Hero` wraps only the unclipped
/// background, never `MemoraCurvedHero`'s `ClipPath`).
class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.controller,
    required this.photoUploadController,
    required this.driveThumbnailService,
    required this.authController,
    required this.albumId,
    required this.role,
  });

  final AlbumsController controller;
  final PhotoUploadController photoUploadController;
  final DriveThumbnailService driveThumbnailService;
  final AuthController authController;
  final String albumId;
  final AlbumRole role;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  bool get _isOwner => widget.role == AlbumRole.owner;

  /// Bumped after a successful Drive reconnect (see `_reconnectDrive`) and
  /// folded into every `_PhotoTile`'s `ValueKey`, alongside `photo.id` — the
  /// only way to force `GridView.builder` to actually recreate the tiles
  /// (and their `late final _thumbnailFuture`) instead of reusing State for
  /// the same photo.id, which by itself would keep showing the old, failed
  /// future forever (see CLAUDE.md's `key`-by-position/by-id gotcha).
  int _epoch = 0;

  /// Which of the 3 inline pill tabs below the hero is currently shown
  /// (mockup redesign, sin spec de Kiro) — replaces the old single
  /// `showModalBottomSheet` trigger. Defaults to `photos` (the tab's
  /// default/initial content, per the brief).
  _AlbumTab _activeTab = _AlbumTab.photos;

  /// Current sort direction for the "Fotos" tab's grid — purely a
  /// presentation choice (see `_sortedPhotos`), never sent anywhere.
  _PhotoSortOrder _photoSortOrder = _PhotoSortOrder.newestFirst;

  /// Set (via `_PhotoTile`'s error callback) as soon as any thumbnail fails
  /// with `DriveReauthorizationRequiredException` — drives the "Reconectar
  /// Google Drive" banner below.
  bool _hasThumbnailReauthFailure = false;
  bool _isReconnectingDrive = false;

  /// Which specific mutation is currently in flight, if any — `isMutating`
  /// on `AlbumsController` is a single shared flag across every mutation
  /// this screen can trigger (rename/visibility/delete/invite/revoke/
  /// remove-collaborator/leave/create-tag/disable-tag), so on its own it
  /// can't tell one button's "I'm the one running" state from another's.
  /// Set right before each mutating call and cleared in a `finally`, purely
  /// local UI state (no controller change) — lets each action show its own
  /// "Verbo-ing..." label/spinner instead of every button just going
  /// generically disabled at once (point 5 of the motion pass).
  String? _pendingAction;

  bool _isPending(String action) =>
      _pendingAction == action && widget.controller.isMutating;

  void _onThumbnailReauthRequired() {
    if (_hasThumbnailReauthFailure) return;
    setState(() => _hasThumbnailReauthFailure = true);
  }

  Future<void> _reconnectDrive() async {
    setState(() => _isReconnectingDrive = true);
    final reconnected = await promptDriveReconnect(
      context,
      widget.authController,
    );
    if (!mounted) return;
    if (reconnected) {
      widget.driveThumbnailService.clearCache();
      setState(() {
        _epoch++;
        _hasThumbnailReauthFailure = false;
        _isReconnectingDrive = false;
      });
    } else {
      setState(() => _isReconnectingDrive = false);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.photoUploadController.addListener(_onChanged);
    widget.controller.loadAlbumDetail(widget.albumId, role: widget.role);
    // Both endpoints behind this are owner-only on the backend too (see
    // CLAUDE.md's note on spec05's "owner o miembro" imprecision) — never
    // loaded for a collaborator.
    if (_isOwner) {
      widget.controller.loadCollaboratorsAndInvitations();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.photoUploadController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _addPhotos() async {
    await widget.photoUploadController.pickAndUploadPhotos(
      albumId: widget.albumId,
    );
    if (!mounted) return;
    await widget.controller.refreshCurrentAlbumDetail();
  }

  Future<void> _removePhoto(Photo photo) async {
    await widget.controller.removePhotoFromCurrentAlbum(photo.id);
  }

  /// Bug real reportado por el usuario en dispositivo: el "×" de cada tile
  /// llamaba `_removePhoto` directo, así que un toque accidental borraba la
  /// foto del álbum sin ningún paso intermedio. Same
  /// `AlertDialog`+"Cancelar"/destructive-action pattern already used by
  /// every other destructive confirmation on this screen (delete album,
  /// revoke invitation/share-link, remove collaborator, leave album) and by
  /// `nfc_programming_screen.dart` ("Sobrescribir"/"Bloquear
  /// definitivamente"/"Deshabilitar"): `TextButton.styleFrom(foregroundColor:
  /// MemoraColors.semanticError)` on the destructive action, never on
  /// "Cancelar". No `TextField` here, so the `autofocus`/`showDialog` gotcha
  /// doesn't apply.
  Future<void> _confirmRemovePhoto(Photo photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar esta foto?'),
        content: const Text(
          'Se quitará esta foto del álbum. La fotografía en sí no se '
          'borra: sigue existiendo en tu Google Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: MemoraColors.semanticError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _removePhoto(photo);
    if (mounted) _showConfirmationSnackBar('Foto eliminada.');
  }

  /// Brief, consistent confirmation feedback after a successful
  /// create/delete/save-style mutation (point 7 of the motion pass) — a
  /// `SnackBar` with a small check icon, reusing `MemoraTheme`'s
  /// `snackBarTheme` for its look (no new package, no bespoke overlay).
  void _showConfirmationSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 20,
              color: MemoraColors.semanticSuccess,
            ),
            const SizedBox(width: MemoraSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// spec08-visor-foto-inapp.md: opens the full-screen viewer at the tapped
  /// photo's position, handing it [photos] (the SAME list/order the caller
  /// is currently displaying — the grid's sorted order, or the hero's own
  /// `detail.photos`) and the SAME `DriveThumbnailService`/`AuthController`
  /// instances this screen already uses — so the viewer shares the thumbnail
  /// cache (a photo already shown in the grid opens instantly) and the same
  /// Drive-reconnect flow (spec06), without any second download pipeline.
  void _openPhotoViewer(List<Photo> photos, int index) {
    Navigator.of(context).push(
      MemoraPageRoute(
        builder: (_) => PhotoViewerScreen(
          photos: photos,
          initialIndex: index,
          thumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
        ),
      ),
    );
  }

  /// Client-side-only presentation order for the "Fotos" tab's grid (mockup
  /// redesign, sin spec de Kiro) — never touches `AlbumsController`/
  /// `detail.photos` itself, purely how this widget lays out the SAME list.
  /// Sorts by `Photo.capturedAt`: descending (newest first) by default,
  /// toggled to ascending via the header's sort control. A photo with a
  /// null `capturedAt` always sinks to the end of the list, in EITHER sort
  /// direction, and — critically — in a stable order relative to any other
  /// null-`capturedAt` photo (never shuffled amongst themselves just because
  /// the sort direction flipped). `List.sort` isn't guaranteed stable in
  /// Dart, so this sorts `(originalIndex, photo)` pairs and falls back to
  /// comparing `originalIndex` whenever two photos tie (both null, or —
  /// smaller odds — the exact same `capturedAt`) instead of relying on the
  /// underlying sort algorithm's stability.
  List<Photo> _sortedPhotos(List<Photo> photos) {
    final indexed = List<MapEntry<int, Photo>>.generate(
      photos.length,
      (i) => MapEntry(i, photos[i]),
    );
    indexed.sort((a, b) {
      final aDate = a.value.capturedAt;
      final bDate = b.value.capturedAt;
      if (aDate == null && bDate == null) return a.key.compareTo(b.key);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final cmp = _photoSortOrder == _PhotoSortOrder.newestFirst
          ? bDate.compareTo(aDate)
          : aDate.compareTo(bDate);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    return [for (final entry in indexed) entry.value];
  }

  Future<void> _renameAlbum() async {
    final currentName = widget.controller.albumDetail?.name ?? '';
    final nameController = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar álbum'),
        content: TextField(
          controller: nameController,
          // NOT autofocus: true here — combined with showDialog's barrier
          // dismiss (tap outside) or an immediate pop (Cancel), a pending
          // autofocus request outliving the dialog's Element triggers a
          // framework-internal assertion failure
          // ('_dependents.isEmpty': is not true, framework.dart) that
          // crashes the screen. Reproduced and confirmed on-device; safe to
          // just not request focus automatically for this short-lived
          // rename dialog.
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(nameController.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    setState(() => _pendingAction = 'rename');
    await widget.controller.renameCurrentAlbum(newName);
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (widget.controller.mutationErrorMessage == null) {
      _showConfirmationSnackBar('Álbum renombrado.');
    }
  }

  Future<void> _changeVisibility() async {
    final current = widget.controller.albumDetail?.visibility;
    final chosen = await showDialog<AlbumVisibility>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Visibilidad del álbum'),
        children: [
          for (final option in AlbumVisibility.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  Icon(
                    option == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    option == AlbumVisibility.public ? 'Pública' : 'Privada',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;
    setState(() => _pendingAction = 'visibility');
    await widget.controller.updateCurrentAlbumVisibility(chosen);
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (widget.controller.mutationErrorMessage == null) {
      _showConfirmationSnackBar('Visibilidad actualizada.');
    }
  }

  Future<void> _deleteAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar álbum'),
        content: const Text(
          'Se eliminará este álbum y se quitarán sus fotos de él, pero '
          'las fotografías NO se borrarán: siguen existiendo en tu '
          'biblioteca de Memora y en tu Google Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingAction = 'delete');
    final deleted = await widget.controller.deleteCurrentAlbum();
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _pendingAction = null);
  }

  /// D12: creates an invitation and offers to share its `url` through the
  /// system share sheet, showing `expiresAt`. Errors surface through the
  /// existing `mutationErrorMessage` banner, same as every other mutation on
  /// this screen.
  Future<void> _createAndShareInvitation() async {
    setState(() => _pendingAction = 'invite');
    final created = await widget.controller.createInvitation();
    if (mounted) setState(() => _pendingAction = null);
    if (created == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invitación creada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(created.url),
            const SizedBox(height: 8),
            Text('Expira el ${_formatDate(created.expiresAt)}.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // System share sheet (spec05 decision), not just clipboard —
              // SharePlus.instance.share is the current (non-deprecated)
              // share_plus v13 API.
              SharePlus.instance.share(ShareParams(text: created.url));
            },
            child: const Text('Compartir'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRevokeInvitation(InvitationListItem invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revocar invitación'),
        content: const Text(
          'El enlace dejará de funcionar para cualquiera que todavía no lo '
          'haya usado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingAction = 'revoke-invitation:${invitation.id}');
    await widget.controller.revokeInvitation(invitation.id);
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (widget.controller.mutationErrorMessage == null) {
      _showConfirmationSnackBar('Invitación revocada.');
    }
  }

  Future<void> _confirmRemoveCollaborator(
    CollaboratorListItem collaborator,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitar colaborador'),
        content: Text(
          '¿Quitar a "${collaborator.userId}" de este álbum? Sus fotos ya '
          'aportadas permanecerán en el álbum.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(
      () => _pendingAction = 'remove-collaborator:${collaborator.userId}',
    );
    await widget.controller.removeCollaborator(collaborator.userId);
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (widget.controller.mutationErrorMessage == null) {
      _showConfirmationSnackBar('Colaborador quitado.');
    }
  }

  /// D5: leaving keeps historical photos in the album (the backend never
  /// touches photo rows on a collaborator leaving) — made explicit in the
  /// confirmation text, same spirit as `_deleteAlbum`'s D16 disclosure.
  Future<void> _confirmLeaveAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abandonar álbum'),
        content: const Text(
          'Dejarás de colaborar en este álbum. Las fotos que ya aportaste '
          'permanecen en él mientras sigan disponibles en tu Google Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abandonar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingAction = 'leave');
    final left = await widget.controller.leaveCurrentAlbum();
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (left) Navigator.of(context).pop();
  }

  /// M7: fetches (or creates, first time) the album's share-link. Errors
  /// surface through `shareLinkErrorMessage`, shown inline in the sharing
  /// section rather than the generic `mutationErrorMessage` banner, since
  /// this isn't a destructive mutation.
  /// No `_pendingAction` tagging needed here (unlike the mutations below):
  /// `AlbumsController.loadOrCreateShareLink` already drives its own
  /// `isLoadingShareLink` flag, and the sharing section already swaps the
  /// button for `MemoraLoadingState` while it's true (see `_buildBody`
  /// below) — a spinner replacing the trigger entirely, same visual intent
  /// as the in-button spinner used everywhere else on this screen.
  Future<void> _obtainShareLink() async {
    await widget.controller.loadOrCreateShareLink();
  }

  Future<void> _confirmRevokeShareLink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revocar enlace'),
        content: const Text(
          'Cualquiera que tenga este enlace dejará de poder ver el álbum '
          'con él. Puedes generar uno nuevo más tarde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingAction = 'revoke-share-link');
    await widget.controller.revokeShareLink();
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (widget.controller.mutationErrorMessage == null) {
      _showConfirmationSnackBar('Enlace revocado.');
    }
  }

  /// M8: creates a new tag of [type] and appends it to the controller's
  /// in-memory list (see `AlbumsController.nfcQrTags`'s doc comment).
  Future<void> _createTag(NfcQrTagType type) async {
    setState(() => _pendingAction = 'create-tag:${type.name}');
    await widget.controller.createNfcQrTag(type);
    if (mounted) setState(() => _pendingAction = null);
  }

  /// spec09-programar-nfc.md: distinct from "Crear etiqueta NFC" above
  /// (spec07's manual flow, which only shows the URL for the user to grab
  /// with their own NFC tool) — this creates the tag the SAME way (P1: same
  /// `AlbumsController.createNfcQrTag` call, no duplicate POST) and then
  /// pushes a dedicated screen that writes it to a physical tag natively via
  /// `nfc_manager`, verifies the write, and optionally locks the chip
  /// read-only (Android only). Both actions coexist; neither replaces the
  /// other.
  Future<void> _programNfcTag() async {
    setState(() => _pendingAction = 'program-nfc');
    final created = await widget.controller.createNfcQrTag(NfcQrTagType.nfc);
    if (mounted) setState(() => _pendingAction = null);
    if (created == null || !mounted) return;
    await Navigator.of(context).push(
      MemoraPageRoute(
        builder: (_) => NfcProgrammingScreen(
          tag: created,
          albumsController: widget.controller,
        ),
      ),
    );
  }

  Future<void> _confirmDisableTag(NfcQrTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bloquear etiqueta'),
        content: const Text(
          'Esta etiqueta dejará de resolver al álbum. No se puede '
          'reactivar: si la necesitas de nuevo, crea una etiqueta nueva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingAction = 'disable-tag:${tag.id}');
    await widget.controller.disableNfcQrTag(tag.id);
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (widget.controller.mutationErrorMessage == null) {
      _showConfirmationSnackBar('Etiqueta bloqueada.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final detail = controller.albumDetail;

    return Scaffold(
      // The hero (photo or fallback gradient) is meant to run full-bleed
      // under the status bar / app bar, editorial-gallery style, instead of
      // a plain title bar — the app bar itself stays transparent and only
      // supplies the back button + owner actions, floating over the hero.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: MemoraColors.paper,
        // Mockup redesign (sin spec de Kiro, ver CLAUDE.md): 3 circular
        // triggers instead of the previous "people" icon (opened a bottom
        // sheet) + 3 loose owner-only icons. The first two just switch
        // `_activeTab` (see `_buildBody`'s tab bar below the hero) — the
        // "Compartir" trigger only exists for an owner, since that whole
        // section (and its tab) has always been 100% owner-only (M7/M8);
        // showing it to a collaborator would open a tab with nothing to
        // show. The overflow "···" (owner-only) replaces the 3 loose
        // rename/visibility/delete icons with the SAME handlers
        // (`_renameAlbum`/`_changeVisibility`/`_deleteAlbum`) — only where
        // they live changed.
        actions: detail == null
            ? null
            : [
                _HeroAppBarCircleIcon(
                  icon: Icons.person_add_alt,
                  tooltip: 'Colaboradores',
                  onPressed: () =>
                      setState(() => _activeTab = _AlbumTab.collaborators),
                ),
                if (_isOwner)
                  _HeroAppBarCircleIcon(
                    icon: Icons.ios_share_outlined,
                    tooltip: 'Compartir',
                    onPressed: () =>
                        setState(() => _activeTab = _AlbumTab.sharing),
                  ),
                if (_isOwner)
                  _HeroAppBarCircleIcon.menu(
                    tooltip: 'Más opciones',
                    enabled: !controller.isMutating,
                    onSelected: (action) {
                      switch (action) {
                        case _OwnerMenuAction.rename:
                          _renameAlbum();
                        case _OwnerMenuAction.visibility:
                          _changeVisibility();
                        case _OwnerMenuAction.delete:
                          _deleteAlbum();
                      }
                    },
                  ),
              ],
      ),
      body: AnimatedSwitcher(
        duration: MemoraMotion.moderate,
        switchInCurve: MemoraMotion.enterCurve,
        switchOutCurve: MemoraMotion.exitCurve,
        child: _buildBody(controller),
      ),
      // The screen's single primary CTA (per `MemoraPrimaryButton`'s own
      // contract) — the sharing section below uses `MemoraSecondaryButton`
      // throughout so this stays the only gradient action on the screen.
      floatingActionButton: MemoraPrimaryButton(
        label: widget.photoUploadController.isRunning
            ? 'Subiendo...'
            : 'Agregar fotos',
        icon: Icons.add_a_photo_outlined,
        onPressed: widget.photoUploadController.isRunning ? null : _addPhotos,
        loading: widget.photoUploadController.isRunning,
      ),
    );
  }

  Widget _buildBody(AlbumsController controller) {
    if (controller.isLoadingDetail && controller.albumDetail == null) {
      return const _AlbumDetailSkeleton(key: ValueKey('loading'));
    }
    if (controller.detailErrorMessage != null) {
      return SafeArea(
        key: const ValueKey('error'),
        child: MemoraEmptyState(
          icon: Icons.error_outline,
          title: 'No se pudo cargar el álbum',
          subtitle:
              '${controller.detailErrorMessage}\n\nRevisa tu conexión e '
              'intenta de nuevo.',
          actionLabel: 'Reintentar',
          onAction: () =>
              controller.loadAlbumDetail(widget.albumId, role: widget.role),
        ),
      );
    }
    final detail = controller.albumDetail;
    if (detail == null) {
      return const SizedBox.shrink(key: ValueKey('empty'));
    }

    // Which tabs actually exist for THIS role — "Compartir" never exists for
    // a collaborator (that whole section has always been 100% owner-only,
    // M7/M8; there is nothing to show there). Used both by the pill bar and
    // to guard against a stale `_activeTab == sharing` if role/ownership
    // could ever change under an already-open screen (it can't today, but
    // this keeps the guard cheap and explicit rather than assumed).
    final tabs = <_AlbumTab>[
      _AlbumTab.photos,
      _AlbumTab.collaborators,
      if (_isOwner) _AlbumTab.sharing,
    ];
    final activeTab = tabs.contains(_activeTab) ? _activeTab : _AlbumTab.photos;
    final sortedPhotos = _sortedPhotos(detail.photos);

    // A single CustomScrollView (instead of a fixed photo grid plus a
    // separately-scrolling collaborators section) so the whole screen has
    // one scroll position — the photo grid stays lazy (SliverGrid.builder),
    // the tab content below it is built eagerly since it's expected to stay
    // small for an MVP album. Keyed by the active tab so switching tabs
    // resets scroll position instead of carrying over an unrelated offset,
    // and so the screen's existing loading/error/content `AnimatedSwitcher`
    // (see `build`) crossfades between tabs too, not just between the 3
    // top-level states.
    return CustomScrollView(
      key: ValueKey('content-${activeTab.name}'),
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            // The photo-count stat pill straddles the hero's curved bottom
            // edge — its own "overflowing element" moment for this screen,
            // deliberately different from `AlbumsListScreen`'s role badge
            // overflowing a card's top edge (same motif, used sparingly and
            // never the same way twice).
            clipBehavior: Clip.none,
            children: [
              _AlbumHero(
                detail: detail,
                thumbnailService: widget.driveThumbnailService,
                epoch: _epoch,
                role: widget.role,
                onReauthRequired: _onThumbnailReauthRequired,
                onTap: detail.photos.isEmpty
                    ? null
                    : () => _openPhotoViewer(detail.photos, 0),
              ),
              Positioned(
                bottom: -26,
                left: MemoraSpacing.lg,
                child: _PhotoCountBadge(count: detail.photoCount),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            MemoraSpacing.lg,
            MemoraSpacing.xl,
            MemoraSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: MemoraSegmentedTabs(
              tabs: [
                for (final tab in tabs)
                  MemoraSegmentedTab(
                    icon: switch (tab) {
                      _AlbumTab.photos => Icons.photo_outlined,
                      _AlbumTab.collaborators => Icons.person_add_alt,
                      _AlbumTab.sharing => Icons.link,
                    },
                    label: switch (tab) {
                      _AlbumTab.photos => 'Fotos',
                      _AlbumTab.collaborators => 'Colaboradores',
                      _AlbumTab.sharing => 'Compartir',
                    },
                  ),
              ],
              activeIndex: tabs.indexOf(activeTab),
              onChanged: (index) => setState(() => _activeTab = tabs[index]),
            ),
          ),
        ),
        if (controller.mutationErrorMessage != null)
          SliverToBoxAdapter(
            child: _errorBanner(controller.mutationErrorMessage!),
          ),
        if (activeTab == _AlbumTab.photos &&
            widget.photoUploadController.batchErrorMessage != null)
          SliverToBoxAdapter(
            child: _errorBanner(
              widget.photoUploadController.batchErrorMessage!,
            ),
          ),
        if (activeTab == _AlbumTab.photos && _hasThumbnailReauthFailure)
          SliverToBoxAdapter(child: _driveReauthBanner()),
        switch (activeTab) {
          _AlbumTab.photos => _buildPhotosTabSliver(sortedPhotos),
          _AlbumTab.collaborators => SliverToBoxAdapter(
            child: _isOwner
                ? _buildOwnerCollaboratorsSection(controller)
                : _buildCollaboratorSection(controller),
          ),
          _AlbumTab.sharing => SliverToBoxAdapter(
            child: _buildSharingSection(controller, detail),
          ),
        },
        const SliverToBoxAdapter(child: SizedBox(height: MemoraSpacing.xxl)),
      ],
    );
  }

  /// The "Fotos" tab's content (mockup redesign, sin spec de Kiro): a
  /// "Fotos" header + the sort control (`_photoSortOrder`), then the same
  /// photo grid as before — same key-by-id+epoch pattern, same staggered
  /// entrance — just fed [sortedPhotos] (this widget's client-side sort of
  /// `detail.photos`, see `_sortedPhotos`) instead of the raw list.
  Widget _buildPhotosTabSliver(List<Photo> sortedPhotos) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            MemoraSpacing.lg,
            MemoraSpacing.lg,
            MemoraSpacing.lg,
            MemoraSpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fotos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                PopupMenuButton<_PhotoSortOrder>(
                  tooltip: 'Ordenar',
                  initialValue: _photoSortOrder,
                  onSelected: (order) =>
                      setState(() => _photoSortOrder = order),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _PhotoSortOrder.newestFirst,
                      child: Text('Más recientes'),
                    ),
                    PopupMenuItem(
                      value: _PhotoSortOrder.oldestFirst,
                      child: Text('Más antiguas'),
                    ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _photoSortOrder.label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: MemoraColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: MemoraColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (sortedPhotos.isEmpty)
          const SliverToBoxAdapter(
            child: MemoraEmptyState(
              icon: Icons.photo_library_outlined,
              title: 'Este álbum todavía no tiene fotos',
              subtitle:
                  'Usa "Agregar fotos" para empezar a construir esta colección.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              MemoraSpacing.md,
              0,
              MemoraSpacing.md,
              MemoraSpacing.md,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: MemoraSpacing.sm,
                mainAxisSpacing: MemoraSpacing.sm,
              ),
              itemCount: sortedPhotos.length,
              itemBuilder: (context, index) {
                final photo = sortedPhotos[index];
                final tile = RepaintBoundary(
                  child: _PhotoTile(
                    // Without a stable key, the default by-position
                    // reconciliation reuses a tile's State (and its cached
                    // _thumbnailFuture) for whatever photo ends up at the
                    // same index after a removal — showing a stale thumbnail
                    // for the wrong photo. Keying by photo.id forces Flutter
                    // to treat each photo as its own Element/State.
                    //
                    // The `#$_epoch` suffix is separate: it's bumped after a
                    // successful Drive reconnect specifically to force
                    // recreation (a new State, a new _thumbnailFuture) for
                    // the SAME photo.id — keying by id alone would keep
                    // reusing the State holding the old failed future.
                    key: ValueKey('${photo.id}#$_epoch'),
                    photo: photo,
                    thumbnailService: widget.driveThumbnailService,
                    onRemove: () => _confirmRemovePhoto(photo),
                    onReauthRequired: _onThumbnailReauthRequired,
                    onTap: () => _openPhotoViewer(sortedPhotos, index),
                  ),
                );
                // A real staggered entrance (flutter_animate, using the
                // centralized MemoraMotion tokens for its duration/curve/
                // stagger step) instead of a plain instant appearance —
                // MemoraMotion.stagger caps the delay at the first dozen
                // tiles so a large album's grid doesn't make the user wait
                // through an ever-longer stagger to see its last rows.
                // Respects reduce motion explicitly (flutter_animate's
                // effects don't check it on their own).
                if (MemoraMotion.reduceMotion(context)) return tile;
                return tile
                    .animate(delay: MemoraMotion.stagger(index))
                    .fadeIn(
                      duration: MemoraMotion.moderate,
                      curve: MemoraMotion.enterCurve,
                    )
                    .scale(
                      begin: const Offset(0.88, 0.88),
                      end: const Offset(1, 1),
                      duration: MemoraMotion.moderate,
                      curve: MemoraMotion.enterCurve,
                    );
              },
            ),
          ),
      ],
    );
  }

  Widget _errorBanner(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(
      MemoraSpacing.md,
      0,
      MemoraSpacing.md,
      MemoraSpacing.sm,
    ),
    child: _InlineBanner(icon: Icons.error_outline, message: message),
  );

  Widget _driveReauthBanner() => Padding(
    padding: const EdgeInsets.fromLTRB(
      MemoraSpacing.md,
      0,
      MemoraSpacing.md,
      MemoraSpacing.sm,
    ),
    child: _InlineBanner(
      icon: Icons.link_off,
      message:
          'Hace falta reconectar Google Drive para ver algunas miniaturas.',
      action: MemoraSecondaryButton(
        label: _isReconnectingDrive
            ? 'Reconectando...'
            : 'Reconectar Google Drive',
        icon: Icons.link,
        onPressed: _isReconnectingDrive ? null : _reconnectDrive,
      ),
    ),
  );

  /// spec07-compartir-nfc-qr.md, owner-only: the album's visibility (D17,
  /// linking back to the AppBar's "Cambiar visibilidad" action rather than
  /// duplicating that control), the share-link (M7: obtain/share/revoke),
  /// and NFC/QR tags (M8: create, render the QR / show the URL for NFC,
  /// block). See `AlbumsController.nfcQrTags`'s doc comment for why tags
  /// created in a previous screen session aren't listed here.
  ///
  /// **Rediseño post-feedback en dispositivo real (sin spec de Kiro, ver
  /// CLAUDE.md)**: el usuario describió este panel como "sin vida, sin
  /// orden, puros botones ahi puestos". Este bloque ahora usa
  /// [_SectionHeader] (chip circular con `signatureGradient`, mismo lenguaje
  /// que `_QuickAccessCard`/`_InitialsAvatar` de `HomeScreen`) en vez del
  /// ícono monocromo de 18px suelto, un `Divider` real entre cada
  /// sub-bloque (visibilidad / enlace / etiquetas NFC-QR) en vez de solo un
  /// `SizedBox`, y un teñido sutil (`_sectionTint`, ~7-8% de Glass Blue sobre
  /// Paper) para que esta card tenga identidad de color propia frente a la
  /// de Colaboradores (teñida de Aura Violet). El bloque de enlace bajó de
  /// dos `MemoraSecondaryButton` compitiendo (Compartir/Revocar) a UNA
  /// acción primaria ("Compartir", pill) + una acción de mantenimiento como
  /// `IconButton` con tooltip ("Revocar") — mismo criterio pedido para
  /// cualquier acción secundaria de este panel.
  Widget _buildSharingSection(AlbumsController controller, AlbumDetail detail) {
    final link = controller.shareLink;
    final textTheme = Theme.of(context).textTheme;
    final isPublic = detail.visibility == AlbumVisibility.public;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MemoraSpacing.md,
        MemoraSpacing.lg,
        MemoraSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemoraCard(
            borderRadius: MemoraRadius.card,
            gradient: _sectionTint(MemoraColors.glassBlue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: _SectionHeader(
                        icon: Icons.ios_share_outlined,
                        title: 'Compartir',
                        subtitle: 'Controla quién puede ver y agregar fotos.',
                      ),
                    ),
                    const SizedBox(width: MemoraSpacing.sm),
                    _VisibilityPill(
                      isPublic: isPublic,
                      loading: _isPending('visibility'),
                      onTap: controller.isMutating ? null : _changeVisibility,
                    ),
                  ],
                ),
                const SizedBox(height: MemoraSpacing.lg),
                _buildShareLinkCard(controller, link, textTheme),
                const SizedBox(height: MemoraSpacing.lg),
                _buildQuickShareRow(controller),
                for (final tag in controller.nfcQrTags) ...[
                  const SizedBox(height: MemoraSpacing.sm),
                  _buildTagCard(controller, tag),
                ],
              ],
            ),
          ),
          const SizedBox(height: MemoraSpacing.lg),
          // "Más formas de compartir" banner (mockup redesign, sin spec de
          // Kiro — ver CLAUDE.md): colocado al final del tab "Compartir" en
          // vez de después de "Colaboradores" como en la referencia visual,
          // porque este tab no existe para un colaborador y el banner habla
          // exclusivamente de NFC/QR (contenido de este tab, no del de
          // colaboradores) — decisión documentada, no un descuido.
          _MoreWaysToShareBanner(
            onTap: controller.isMutating ? null : _programNfcTag,
          ),
        ],
      ),
    );
  }

  /// The share-link block of the "Compartir" tab (mockup redesign, sin spec
  /// de Kiro): same `loadOrCreateShareLink`/`SharePlus`/`_confirmRevokeShareLink`
  /// logic as before, restyled into a single highlighted card per the
  /// reference — an icon + "Enlace de compartición" + a one-line
  /// description, a gradient pill "Obtener enlace" while there's none yet,
  /// or the selectable url + "Compartir"/revoke actions once it exists.
  Widget _buildShareLinkCard(
    AlbumsController controller,
    ShareLink? link,
    TextTheme textTheme,
  ) {
    return MemoraCard(
      elevation: MemoraCardElevation.level1,
      borderRadius: MemoraRadius.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: MemoraColors.signatureGradient,
                ),
                child: const Icon(
                  Icons.link,
                  size: 18,
                  color: MemoraColors.paper,
                ),
              ),
              const SizedBox(width: MemoraSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Enlace de compartición', style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Cualquiera con el enlace puede ver este álbum.',
                      style: textTheme.bodySmall?.copyWith(
                        color: MemoraColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MemoraSpacing.md),
          if (controller.isLoadingShareLink)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: MemoraSpacing.sm),
              child: MemoraLoadingState(compact: true),
            )
          else if (controller.shareLinkErrorMessage != null)
            Text(
              controller.shareLinkErrorMessage!,
              style: textTheme.bodySmall?.copyWith(
                color: MemoraColors.semanticError,
              ),
            )
          else if (link == null)
            _GradientPillButton(
              label: 'Obtener enlace',
              icon: Icons.link,
              onPressed: _obtainShareLink,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(link.url, style: textTheme.bodySmall),
                const SizedBox(height: MemoraSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: MemoraSecondaryButton(
                        label: 'Compartir',
                        icon: Icons.share_outlined,
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(text: link.url),
                        ),
                      ),
                    ),
                    const SizedBox(width: MemoraSpacing.xs),
                    _isPending('revoke-share-link')
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  MemoraColors.semanticError,
                                ),
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.link_off),
                            color: MemoraColors.semanticError,
                            tooltip: 'Revocar enlace',
                            onPressed: controller.isMutating
                                ? null
                                : _confirmRevokeShareLink,
                          ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// The "Más formas de compartir" row of the reference — 4 existing actions
  /// (create QR tag / create NFC tag / program NFC tag / share the link
  /// through the system share sheet) reorganized as icon-chip + label items
  /// separated by thin vertical rules, instead of the previous `Wrap` of 3
  /// `MemoraSecondaryButton`s. Each item calls the SAME handler as before —
  /// "Compartir en otras apps" is the only new wiring (`_shareInOtherApps`),
  /// and it's a thin wrapper: obtain-or-create the link (existing
  /// `loadOrCreateShareLink`) then the same `SharePlus` call already used
  /// elsewhere on this screen.
  Widget _buildQuickShareRow(AlbumsController controller) {
    final items = [
      _QuickShareItemData(
        icon: Icons.qr_code,
        label: 'Crear etiqueta QR',
        onTap: controller.isMutating
            ? null
            : () => _createTag(NfcQrTagType.qr),
        loading: _isPending('create-tag:${NfcQrTagType.qr.name}'),
      ),
      _QuickShareItemData(
        icon: Icons.nfc,
        label: 'Crear etiqueta NFC',
        onTap: controller.isMutating
            ? null
            : () => _createTag(NfcQrTagType.nfc),
        loading: _isPending('create-tag:${NfcQrTagType.nfc.name}'),
      ),
      _QuickShareItemData(
        icon: Icons.nfc_outlined,
        label: 'Programar etiqueta NFC',
        onTap: controller.isMutating ? null : _programNfcTag,
        loading: _isPending('program-nfc'),
      ),
      _QuickShareItemData(
        icon: Icons.ios_share_outlined,
        label: 'Compartir en otras apps',
        onTap:
            (controller.isMutating ||
                controller.isLoadingShareLink ||
                _isPending('share-other-apps'))
            ? null
            : _shareInOtherApps,
        loading:
            _isPending('share-other-apps') || controller.isLoadingShareLink,
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: 1,
                height: 52,
                child: ColoredBox(color: MemoraColors.border),
              ),
            ),
          Expanded(child: _QuickShareItem(data: item)),
        ],
      ],
    );
  }

  /// Wired to "Compartir en otras apps" (see `_buildQuickShareRow`): reuses
  /// the album's existing share-link (obtaining/creating it first if it
  /// doesn't exist yet, same call as "Obtener enlace") and opens the SAME
  /// system share sheet already used by the link card and the invitation
  /// dialog — no new sharing mechanism.
  Future<void> _shareInOtherApps() async {
    setState(() => _pendingAction = 'share-other-apps');
    if (widget.controller.shareLink == null) {
      await widget.controller.loadOrCreateShareLink();
    }
    if (mounted) setState(() => _pendingAction = null);
    final link = widget.controller.shareLink;
    if (link == null || !mounted) return;
    await SharePlus.instance.share(ShareParams(text: link.url));
  }

  Widget _buildTagCard(AlbumsController controller, NfcQrTag tag) {
    final textTheme = Theme.of(context).textTheme;

    return MemoraCard(
      elevation: MemoraCardElevation.level1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tag.type == NfcQrTagType.qr ? Icons.qr_code : Icons.nfc,
                size: 18,
                color: MemoraColors.glassBlueOnLight,
              ),
              const SizedBox(width: MemoraSpacing.sm),
              Text(
                tag.type == NfcQrTagType.qr ? 'QR' : 'NFC',
                style: textTheme.titleSmall,
              ),
              const Spacer(),
              MemoraBadge(
                label: tag.isDisabled ? 'Bloqueada' : 'Activa',
                dotColor: tag.isDisabled
                    ? MemoraColors.semanticError
                    : MemoraColors.semanticSuccess,
              ),
            ],
          ),
          const SizedBox(height: MemoraSpacing.sm),
          if (tag.type == NfcQrTagType.qr)
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: MemoraColors.paper,
                  borderRadius: BorderRadius.circular(MemoraRadius.card),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(MemoraSpacing.sm),
                  child: QrImageView(
                    data: tag.url,
                    size: 160,
                    backgroundColor: MemoraColors.paper,
                  ),
                ),
              ),
            )
          else
            SelectableText(tag.url, style: textTheme.bodySmall),
          const SizedBox(height: MemoraSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: MemoraSecondaryButton(
              label: 'Bloquear',
              icon: Icons.block,
              destructive: true,
              onPressed: (controller.isMutating || tag.isDisabled)
                  ? null
                  : () => _confirmDisableTag(tag),
              loading: _isPending('disable-tag:${tag.id}'),
            ),
          ),
        ],
      ),
    );
  }

  /// D1/D12/D13: invite (share sheet), collaborators list ("quitar"),
  /// pending invitations ("revocar") — all owner-only, hidden entirely (not
  /// just disabled) for a collaborator, same criterion as the AppBar
  /// actions above.
  ///
  /// **Rediseño post-feedback en dispositivo real (sin spec de Kiro, ver
  /// CLAUDE.md)**: usa [_SectionHeader] (mismo chip circular con
  /// `signatureGradient` que el resto del panel, ahora con `subtitle`) y un
  /// teñido propio (`_sectionTint(MemoraColors.auraViolet)`, distinto del de
  /// "Compartir") para que esta card tenga identidad de color propia.
  ///
  /// **Segundo ajuste visual (nueva referencia `colaboradores.png`, sin spec
  /// de Kiro — ver CLAUDE.md)**: el `_CollaboratorAvatarStack` superpuesto
  /// (una fila de círculos) volvió a ser una LISTA DE FILAS completas
  /// (`_EntityRow`, una por colaborador + una fija para el usuario actual),
  /// pedido explícito del usuario al ver la nueva referencia. Como
  /// `CollaboratorListItem` solo trae `userId` (sin nombre/foto — limitación
  /// real del backend, documentada en CLAUDE.md/README.md, no resuelta acá),
  /// cada fila de "otro" colaborador sigue derivando sus iniciales del
  /// `userId` (misma función que ya existía) pero con el título genérico
  /// "Colaborador" (nunca un nombre inventado). La fila del propio usuario
  /// (el owner, ya que esta sección solo se construye para `_isOwner`) SÍ
  /// muestra su nombre/email real, vía `widget.authController.user` — dato ya
  /// disponible en esta pantalla, sin ninguna llamada nueva — con una
  /// etiqueta "Tú" junto al nombre. La acción de "quitar" volvió a vivir en
  /// un menú "···" por fila (mismo `_confirmRemoveCollaborator`, sin cambios
  /// de comportamiento) en vez de tocar el avatar. Las invitaciones
  /// pendientes usan el mismo `_EntityRow` (icono de sobre en vez de avatar,
  /// badge "Pendiente", menú con "Revocar") en lugar del antiguo `_PersonRow`
  /// — mismo `_confirmRevokeInvitation`, sin acción nueva inventada (el
  /// backend no expone "reenviar").
  Widget _buildOwnerCollaboratorsSection(AlbumsController controller) {
    final pendingInvitations = controller.invitations
        .where((invitation) => invitation.isPending)
        .toList();
    final textTheme = Theme.of(context).textTheme;
    final currentUser = widget.authController.user;
    final currentUserLabel =
        (currentUser?.name != null && currentUser!.name!.trim().isNotEmpty)
        ? currentUser.name!
        : (currentUser?.email ?? 'Tú');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MemoraSpacing.md,
        MemoraSpacing.lg,
        MemoraSpacing.md,
        MemoraSpacing.lg,
      ),
      child: MemoraCard(
        borderRadius: MemoraRadius.card,
        gradient: _sectionTint(MemoraColors.auraViolet),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: _SectionHeader(
                    icon: Icons.group_outlined,
                    title: 'Colaboradores',
                    subtitle: 'Personas que pueden ver y agregar fotos.',
                  ),
                ),
                const SizedBox(width: MemoraSpacing.sm),
                MemoraSecondaryButton(
                  label: 'Invitar',
                  icon: Icons.person_add_alt,
                  onPressed: controller.isMutating
                      ? null
                      : _createAndShareInvitation,
                  loading: _isPending('invite'),
                ),
              ],
            ),
            const SizedBox(height: MemoraSpacing.lg),
            _EntityRow(
              avatarLabel: _personInitials(currentUser?.name, currentUserLabel),
              avatarGradient: true,
              title: currentUserLabel,
              isYou: true,
              subtitle: 'Puede ver y agregar fotos',
              badgeLabel: 'Owner',
            ),
            if (controller.isLoadingCollaborators)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: MemoraSpacing.sm),
                child: MemoraLoadingState(compact: true),
              )
            else if (controller.collaboratorsErrorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: MemoraSpacing.sm,
                ),
                child: Text(
                  controller.collaboratorsErrorMessage!,
                  style: textTheme.bodySmall?.copyWith(
                    color: MemoraColors.semanticError,
                  ),
                ),
              )
            else
              for (final collaborator in controller.collaborators)
                _EntityRow(
                  avatarLabel: _initialsFromId(collaborator.userId),
                  avatarGradient: true,
                  title: 'Colaborador',
                  subtitle: 'Puede ver y agregar fotos',
                  badgeLabel: 'Colaborador',
                  isLoading: _isPending(
                    'remove-collaborator:${collaborator.userId}',
                  ),
                  menuItems: [
                    _RowMenuItem(
                      label: 'Quitar',
                      destructive: true,
                      onTap: controller.isMutating
                          ? null
                          : () => _confirmRemoveCollaborator(collaborator),
                    ),
                  ],
                ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: MemoraSpacing.md),
              child: Divider(height: 1, color: MemoraColors.border),
            ),
            Row(
              children: [
                Text('Invitaciones pendientes', style: textTheme.titleSmall),
                const SizedBox(width: MemoraSpacing.sm),
                MemoraBadge(label: '${pendingInvitations.length}'),
              ],
            ),
            const SizedBox(height: MemoraSpacing.sm),
            if (pendingInvitations.isEmpty)
              Text(
                'No hay invitaciones pendientes.',
                style: textTheme.bodySmall,
              )
            else
              for (final invitation in pendingInvitations)
                _EntityRow(
                  avatarIcon: Icons.mail_outline,
                  title: 'Invitación pendiente',
                  subtitle: 'Expira el ${_formatDate(invitation.expiresAt)}',
                  badgeLabel: 'Pendiente',
                  isLoading: _isPending(
                    'revoke-invitation:${invitation.id}',
                  ),
                  menuItems: [
                    _RowMenuItem(
                      label: 'Revocar',
                      destructive: true,
                      onTap: controller.isMutating
                          ? null
                          : () => _confirmRevokeInvitation(invitation),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  /// D5: the only collaborator-facing action of this section. Same
  /// `_SectionHeader` language as the owner-only sections above, for a
  /// consistent panel even though a plain collaborator only ever sees this
  /// one block.
  Widget _buildCollaboratorSection(AlbumsController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MemoraSpacing.md,
        MemoraSpacing.lg,
        MemoraSpacing.md,
        MemoraSpacing.lg,
      ),
      child: MemoraCard(
        borderRadius: MemoraRadius.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.group_outlined,
              title: 'Este álbum',
            ),
            const SizedBox(height: MemoraSpacing.md),
            Text(
              'Estás colaborando en este álbum.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: MemoraSpacing.md),
            MemoraSecondaryButton(
              label: 'Abandonar álbum',
              icon: Icons.logout,
              destructive: true,
              onPressed: controller.isMutating ? null : _confirmLeaveAlbum,
              loading: _isPending('leave'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }
}

/// Initial-load placeholder for the whole screen: a hero-shaped skeleton
/// block plus a 2-column grid of tile-shaped skeletons (see
/// `memora_skeleton.dart`), replacing the previous centered spinner — the
/// shapes roughly match the hero/grid that will replace them once
/// `loadAlbumDetail` resolves.
class _AlbumDetailSkeleton extends StatelessWidget {
  const _AlbumDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(MemoraSpacing.lg),
              child: MemoraSkeleton(height: 220, borderRadius: 32),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: MemoraSpacing.md),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: MemoraSpacing.sm,
                mainAxisSpacing: MemoraSpacing.sm,
                childAspectRatio: 1,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => const MemoraPhotoTileSkeleton(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    super.key,
    required this.photo,
    required this.thumbnailService,
    required this.onRemove,
    required this.onReauthRequired,
    required this.onTap,
  });

  final Photo photo;
  final DriveThumbnailService thumbnailService;
  final VoidCallback onRemove;

  /// Called (at most once per tile instance) when this tile's thumbnail
  /// fails with [DriveReauthorizationRequiredException] — lets the parent
  /// screen show a single "Reconectar Google Drive" banner instead of each
  /// tile handling it on its own.
  final VoidCallback onReauthRequired;

  /// spec08-visor-foto-inapp.md: opens the full-screen viewer at this
  /// photo's position. Only wraps the thumbnail area (see `build`) — never
  /// the "×" remove button, which keeps its own separate `InkWell`.
  final VoidCallback onTap;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  late final Future<Uint8List> _thumbnailFuture = widget.thumbnailService
      .getThumbnail(widget.photo.storageRef.fileId)
      .catchError((Object error) {
        if (error is DriveReauthorizationRequiredException) {
          // Not called synchronously from build/initState — scheduled for
          // after this frame, since notifying the parent here can trigger
          // its own setState while this tile's widget tree is still being
          // built.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onReauthRequired();
          });
        }
        // Rethrow so FutureBuilder still sees the error (this side-effect
        // must never swallow it — the tile itself still needs to show its
        // own "link_off" icon for this specific photo).
        throw error;
      });

  @override
  Widget build(BuildContext context) {
    final isUnavailable =
        widget.photo.availability == PhotoAvailability.unavailable;

    // Photography is intentionally edge-to-edge in the editorial system:
    // rounded image tiles made every photo read like the same generic card.
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          child: ColoredBox(
            color: MemoraColors.surface1,
            child: FutureBuilder<Uint8List>(
              future: _thumbnailFuture,
              builder: (context, snapshot) {
                final Widget child;
                if (snapshot.connectionState != ConnectionState.done) {
                  child = const Center(
                    key: ValueKey('loading'),
                    child: MemoraLoadingState(compact: true),
                  );
                } else if (snapshot.hasError) {
                  final needsReauth =
                      snapshot.error is DriveReauthorizationRequiredException;
                  child = Center(
                    key: const ValueKey('error'),
                    child: Icon(
                      needsReauth
                          ? Icons.link_off
                          : Icons.broken_image_outlined,
                      color: needsReauth
                          ? MemoraColors.semanticError
                          : MemoraColors.textTertiary,
                    ),
                  );
                } else {
                  child = Image.memory(
                    snapshot.data!,
                    key: const ValueKey('image'),
                    fit: BoxFit.cover,
                  );
                }
                // Placeholder -> fade-in -> image, never an abrupt swap
                // (point 6 of the motion pass): a plain crossfade between
                // whichever of the three states above is current.
                return AnimatedSwitcher(
                  duration: MemoraMotion.moderate,
                  switchInCurve: MemoraMotion.enterCurve,
                  switchOutCurve: MemoraMotion.exitCurve,
                  child: child,
                );
              },
            ),
          ),
        ),
        if (isUnavailable)
          Container(
            color: MemoraColors.deepInk.withValues(alpha: 0.6),
            alignment: Alignment.center,
            child: const Icon(Icons.cloud_off, color: MemoraColors.paper),
          ),
        Positioned(
          top: MemoraSpacing.xs,
          right: MemoraSpacing.xs,
          child: InkWell(
            onTap: widget.onRemove,
            customBorder: const CircleBorder(),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MemoraColors.deepInk.withValues(alpha: 0.6),
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: MemoraColors.paper,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which owner-only action was picked from `_HeroAppBarCircleIcon.menu`'s
/// overflow menu — the same 3 actions that used to be 3 loose AppBar icons
/// (rename/visibility/delete, see CLAUDE.md's "Fase 2" history), now grouped
/// under a single "···" trigger (mockup redesign, sin spec de Kiro). Only
/// WHERE these actions live changed — `_renameAlbum`/`_changeVisibility`/
/// `_deleteAlbum` themselves are untouched.
enum _OwnerMenuAction { rename, visibility, delete }

/// One of the (up to) 3 circular triggers floating over the hero photo
/// (mockup redesign, sin spec de Kiro — ver CLAUDE.md): a translucent Deep
/// Ink circle behind a Paper icon, so it reads clearly over any part of the
/// photo — same "chip over a photo" language as `_PhotoCountBadge`'s seam
/// pill, just circular/dark instead of pill-shaped/light, since this one
/// sits directly on the image instead of on the hero's curved seam.
///
/// The default constructor is a plain tappable icon (used for
/// "Colaboradores"/"Compartir", which just flip `_activeTab`); the named
/// `.menu` constructor wraps the same circle around a `PopupMenuButton` for
/// the owner-only overflow — one widget, two trigger shapes, so all 3 read
/// as the same visual element.
class _HeroAppBarCircleIcon extends StatelessWidget {
  const _HeroAppBarCircleIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : isMenu = false,
       enabled = true,
       onSelected = null;

  const _HeroAppBarCircleIcon.menu({
    required this.tooltip,
    required this.enabled,
    required this.onSelected,
  }) : isMenu = true,
       icon = Icons.more_vert,
       onPressed = null;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isMenu;
  final bool enabled;
  final void Function(_OwnerMenuAction action)? onSelected;

  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      color: MemoraColors.deepInk.withValues(alpha: 0.38),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        width: _size,
        height: _size,
        decoration: decoration,
        child: isMenu
            ? PopupMenuButton<_OwnerMenuAction>(
                enabled: enabled,
                tooltip: tooltip,
                icon: const Icon(
                  Icons.more_vert,
                  color: MemoraColors.paper,
                  size: 20,
                ),
                onSelected: onSelected,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _OwnerMenuAction.rename,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Renombrar'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _OwnerMenuAction.visibility,
                    child: ListTile(
                      leading: Icon(Icons.visibility_outlined),
                      title: Text('Cambiar visibilidad'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _OwnerMenuAction.delete,
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        color: MemoraColors.semanticError,
                      ),
                      title: Text(
                        'Eliminar álbum',
                        style: TextStyle(color: MemoraColors.semanticError),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              )
            : IconButton(
                padding: EdgeInsets.zero,
                onPressed: onPressed,
                tooltip: tooltip,
                icon: Icon(icon, color: MemoraColors.paper, size: 20),
              ),
      ),
    );
  }
}

/// A small bordered banner for inline error/status messages (mutation
/// errors, the Drive-reauth notice) — replaces the raw red `Text` used
/// before, with an optional trailing [action] button.
class _InlineBanner extends StatelessWidget {
  const _InlineBanner({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(MemoraSpacing.sm + 2),
      decoration: BoxDecoration(
        color: MemoraColors.semanticError.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MemoraRadius.card),
        border: Border.all(
          color: MemoraColors.semanticError.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: MemoraColors.semanticError),
              const SizedBox(width: MemoraSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: textTheme.bodySmall?.copyWith(
                    color: MemoraColors.semanticError,
                  ),
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: MemoraSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Subtle background tint for a sharing-sheet section card (post-feedback
/// redesign, sin spec de Kiro — ver CLAUDE.md): blends [accent] onto
/// [MemoraColors.paper] at a low, deliberately restrained alpha (~7-8% at
/// the top-left corner, fading to ~3% at the bottom-right) so each section
/// of the panel ("Compartir" vs "Colaboradores") reads with its own color
/// identity instead of every card being the exact same flat tone — the
/// concrete complaint was "todo color claro, parece una hoja de oficina".
/// Passed as `MemoraCard.gradient`, which already supports an arbitrary
/// `Gradient` override in place of a flat elevation color; the card's
/// existing border/press behavior is untouched. Not a `const` (built from
/// `Color.alphaBlend`, which isn't a const function) — cheap enough to
/// recompute per build, same as `gradientForAlbumId`'s callers.
LinearGradient _sectionTint(Color accent) {
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(accent.withValues(alpha: 0.08), MemoraColors.paper),
      Color.alphaBlend(accent.withValues(alpha: 0.03), MemoraColors.paper),
    ],
  );
}

/// Section header for the sharing/collaborators sections (post-feedback
/// redesign, sin spec de Kiro — ver CLAUDE.md): a circular chip with
/// [MemoraColors.signatureGradient] behind the icon (Paper-colored, 18px) +
/// the section title with real typographic weight
/// (`textTheme.headlineSmall`). Reuses the exact chip language already used
/// by `HomeScreen._QuickAccessCard`/`_InitialsAvatar` and this same screen's
/// role badge — never a bare 18px monochrome icon floating next to text,
/// which is what this panel looked like before ("ícono chiquito de 18px
/// suelto al lado del texto").
///
/// **`subtitle` (nueva referencia `colaboradores.png`, sin spec de Kiro)** —
/// una segunda línea corta bajo el título ("Controla quién puede ver y
/// agregar fotos."/"Personas que pueden ver y agregar fotos."), opcional
/// para no forzarla en ningún uso futuro de este header que no la necesite.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  static const _chipSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: _chipSize,
          height: _chipSize,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: MemoraColors.signatureGradient,
          ),
          child: Icon(icon, size: 18, color: MemoraColors.paper),
        ),
        const SizedBox(width: MemoraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: textTheme.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: textTheme.bodySmall?.copyWith(
                    color: MemoraColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A small tappable pill showing the album's current visibility (D17), with
/// a trailing chevron signaling it opens `_changeVisibility` — the SAME
/// action already wired to the AppBar's overflow menu, just also reachable
/// from here per the reference (`colaboradores.png`'s "🔒 Álbum privado ›"
/// pill next to the "Compartir" header). No new controller call.
class _VisibilityPill extends StatelessWidget {
  const _VisibilityPill({
    required this.isPublic,
    required this.onTap,
    this.loading = false,
  });

  final bool isPublic;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(MemoraRadius.pill),
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MemoraSpacing.sm + 2,
            vertical: MemoraSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: MemoraColors.surface2,
            borderRadius: BorderRadius.circular(MemoraRadius.pill),
            border: Border.all(color: MemoraColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  isPublic ? Icons.public : Icons.lock_outline,
                  size: 14,
                  color: MemoraColors.textSecondary,
                ),
              const SizedBox(width: MemoraSpacing.xs),
              Text(
                isPublic ? 'Álbum público' : 'Álbum privado',
                style: textTheme.labelMedium,
              ),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: MemoraColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gradient pill CTA for "Obtener enlace" (reference `colaboradores.png`).
///
/// **Nota de diseño (marcado para revisión de Kiro, ver reporte final)**:
/// `MemoraPrimaryButton`'s own doc comment says it must never be used more
/// than once per screen, and this screen already spends its one
/// `MemoraPrimaryButton` on the "Agregar fotos" FAB — so this is a SEPARATE,
/// smaller widget (not `MemoraPrimaryButton`) that borrows the same
/// `signatureGradient` fill for this one action, because the visual
/// reference explicitly shows a gradient pill here. This does mean the
/// screen now has two gradient-filled CTAs (the FAB, always visible, and
/// this one, only inside the "Compartir" tab) — a deliberate exception to
/// that widget's "one per screen" rule, not an oversight.
class _GradientPillButton extends StatelessWidget {
  const _GradientPillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(MemoraRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(MemoraRadius.pill),
          onTap: onPressed,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: MemoraColors.signatureGradient,
              borderRadius: BorderRadius.all(
                Radius.circular(MemoraRadius.pill),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: MemoraSpacing.lg,
              vertical: MemoraSpacing.sm + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: MemoraColors.deepInk),
                const SizedBox(width: MemoraSpacing.sm),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Data for one item of the "más formas de compartir" quick-access row (see
/// `_buildQuickShareRow`) — a plain data holder, no logic of its own.
class _QuickShareItemData {
  const _QuickShareItemData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
}

/// One icon-chip + label item of the quick-share row (reference
/// `colaboradores.png`'s 4-item row under the share-link card) — the whole
/// column is the tap target, matching `_QuickAccessCard`'s "icon in a
/// circular chip" language elsewhere in the app.
class _QuickShareItem extends StatelessWidget {
  const _QuickShareItem({required this.data});

  final _QuickShareItemData data;

  static const _chipSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = data.onTap != null && !data.loading;

    return Opacity(
      opacity: enabled || data.loading ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(MemoraRadius.card),
          onTap: enabled ? data.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: MemoraSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _chipSize,
                  height: _chipSize,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: MemoraColors.surface2,
                  ),
                  child: data.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          data.icon,
                          size: 20,
                          color: MemoraColors.glassBlueOnLight,
                        ),
                ),
                const SizedBox(height: MemoraSpacing.xs),
                Text(
                  data.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: MemoraColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dark "Aurora" full-width banner promoting the physical-tag flows (NFC
/// programming, first) — the reference (`colaboradores.png`) shows this at
/// the end of the panel, its exact copy in English/generic ("tap to share",
/// not translated verbatim per the brief — the user asked for original,
/// Memora-toned Spanish copy). Same visual language as
/// `HomeScreen._AlbumsHeroCard` (radial `deepInk`/`auraViolet` gradient, a
/// decorative asset image overflowing/rotated near an edge) — reused
/// deliberately so this reads as the same design system, not a one-off.
class _MoreWaysToShareBanner extends StatelessWidget {
  const _MoreWaysToShareBanner({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(MemoraRadius.card),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.85, -0.2),
            radius: 1.2,
            colors: [MemoraColors.auraViolet, MemoraColors.deepInk],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -22,
                  bottom: -20,
                  child: Transform.rotate(
                    angle: -0.3,
                    child: Opacity(
                      opacity: 0.9,
                      child: Image.asset(
                        'assets/images/nfc_icon.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MemoraSpacing.md,
                    MemoraSpacing.md,
                    100,
                    MemoraSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Comparte con solo un toque',
                        style: textTheme.titleMedium?.copyWith(
                          color: MemoraColors.paper,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: MemoraSpacing.xs),
                      Text(
                        'Programa una etiqueta NFC o crea un QR para este '
                        'álbum: se abre acercando el teléfono o escaneando, '
                        'sin apps ni conexión.',
                        style: textTheme.bodySmall?.copyWith(
                          color: MemoraColors.paper.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: MemoraSpacing.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Programar ahora',
                            style: textTheme.labelLarge?.copyWith(
                              color: MemoraColors.glassBlue,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: MemoraColors.glassBlue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One menu action of an `_EntityRow`'s "···" overflow (e.g. "Quitar"/
/// "Revocar") — a plain data holder, mirroring `_QuickShareItemData`.
class _RowMenuItem {
  const _RowMenuItem({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool destructive;
}

/// A full-width row for one person/invitation (reference `colaboradores.png`
/// — replaces the previous overlapping avatar-stack and the old
/// `_PersonRow`): an avatar (initials on a gradient circle for a person, or
/// a plain icon chip for an invitation) + title/subtitle + a trailing role
/// badge + an optional "···" overflow menu. Used for the current user
/// (owner) row, each other collaborator's row, and each pending
/// invitation's row — see `_buildOwnerCollaboratorsSection`.
class _EntityRow extends StatelessWidget {
  const _EntityRow({
    this.avatarLabel,
    this.avatarIcon,
    this.avatarGradient = false,
    required this.title,
    this.isYou = false,
    required this.subtitle,
    required this.badgeLabel,
    this.menuItems = const [],
    this.isLoading = false,
  }) : assert(
         avatarLabel != null || avatarIcon != null,
         'either avatarLabel or avatarIcon must be set',
       );

  /// Initials shown on the circular avatar — mutually exclusive with
  /// [avatarIcon] (a person row uses initials, an invitation row uses an
  /// icon instead, since it isn't a person yet).
  final String? avatarLabel;
  final IconData? avatarIcon;

  /// Whether the avatar fills with [MemoraColors.signatureGradient] (a
  /// person) or the neutral [MemoraColors.surface2] (an invitation icon).
  final bool avatarGradient;

  final String title;

  /// Shows a small "Tú" tag next to [title] — only ever true for the current
  /// user's own row.
  final bool isYou;
  final String subtitle;
  final String badgeLabel;

  /// Empty hides the "···" trigger entirely (e.g. the current user's own
  /// row, which has no self-removal action from here).
  final List<_RowMenuItem> menuItems;

  /// Shows a small spinner in place of the "···" trigger while this row's
  /// own action is in flight — same per-row loading intent as the old
  /// `_PersonRow.isLoading`.
  final bool isLoading;

  static const _diameter = 44.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MemoraSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: _diameter,
            height: _diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: avatarGradient ? MemoraColors.signatureGradient : null,
              color: avatarGradient ? null : MemoraColors.surface2,
            ),
            child: avatarIcon != null
                ? Icon(
                    avatarIcon,
                    size: 18,
                    color: MemoraColors.textSecondary,
                  )
                : Text(
                    avatarLabel!,
                    style: textTheme.labelMedium?.copyWith(
                      color: MemoraColors.paper,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: MemoraSpacing.xs),
                      const MemoraBadge(label: 'Tú'),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: MemoraColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
          MemoraBadge(label: badgeLabel),
          if (menuItems.isNotEmpty) ...[
            const SizedBox(width: MemoraSpacing.xs),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<int>(
                icon: const Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: MemoraColors.textSecondary,
                ),
                onSelected: (index) => menuItems[index].onTap?.call(),
                itemBuilder: (context) => [
                  for (final (index, item) in menuItems.indexed)
                    PopupMenuItem(
                      value: index,
                      enabled: item.onTap != null,
                      child: Text(
                        item.label,
                        style: item.destructive
                            ? const TextStyle(
                                color: MemoraColors.semanticError,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// The photo-count stat pill that straddles the hero's curved bottom edge
/// (see `_buildBody`'s `Stack`) — floats right on the seam between the
/// (still dark-scrimmed) photo hero above and the light content below, so
/// it needs to read as bright against both. Uses `level1` (a soft
/// off-white, close to Paper) rather than the default page background —
/// same "bright pill on the seam" idea as before the pivot, just no longer
/// a rare exception (it's simply this card system's lightest default now).
class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MemoraCard(
      borderRadius: MemoraRadius.pill,
      padding: const EdgeInsets.symmetric(
        horizontal: MemoraSpacing.md,
        vertical: MemoraSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 16),
          const SizedBox(width: MemoraSpacing.xs),
          // No explicit color needed anymore: `textTheme.*` already
          // defaults to Deep Ink on the light canvas (see
          // memora_typography.dart's class doc) — the old override here was
          // a workaround for `MemoraCardElevation.light`'s ambient-default
          // gotcha, which no longer applies to `level1`.
          Text('$count', style: textTheme.titleSmall),
          const SizedBox(width: MemoraSpacing.xs),
          Text(count == 1 ? 'foto' : 'fotos', style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// The album's hero: the first photo in the album (fetched from Drive, same
/// as any grid tile) full-bleed at the top of the screen with the
/// `MemoraHeroCurve` seam into the content below, or a deterministic
/// gradient (same `gradientForAlbumId` used by `AlbumsListScreen`'s
/// abstract cards) when the album has no photos yet. Two scrims over the
/// image (top, for the transparent app bar's back/action icons; bottom, for
/// the name/role text) — same "derived from Deep Ink, never plain black"
/// pattern as `HomeScreen._WelcomeHeroBackdrop`.
///
/// Post-feedback "más dinamismo" pass: `background` is wrapped in a
/// `Hero(tag: 'album-hero-${detail.id}')` shared with the matching tag on
/// `AlbumsListScreen._AlbumGridCard`'s `MemoraCard`, so tapping an album
/// card now flies into this screen instead of just cutting to it.
/// **Deliberately wrapped around only the raw background (the photo/
/// gradient), never around `MemoraCurvedHero` itself**: `MemoraCurvedHero`
/// clips its `background` with `MemoraHeroCurve` (a `ClipPath`), and a
/// `Hero` flight interpolates its child's size every animation frame — if
/// the `ClipPath` were INSIDE the `Hero`'s child, its wave would need to be
/// recomputed at each of those frame sizes too. `MemoraHeroCurve.shouldReclip`
/// was fixed (see its own doc comment) to always return `true` specifically
/// to make that safe, but this widget still keeps the `Hero` as the
/// `background` argument PASSED INTO `MemoraCurvedHero` rather than wrapping
/// the whole thing — `MemoraCurvedHero`'s `ClipPath` then sits as an
/// ANCESTOR of the `Hero`, never a descendant, so it's simply not part of
/// what Flutter captures and flies in the overlay (`Hero` only captures its
/// own `child` subtree, not its ancestors) — the safer of the two options
/// the brief allowed, chosen because this environment has no device to
/// visually confirm the flight looks right either way. The overlay
/// (name/role text) stays OUTSIDE the `Hero` on purpose too: it has no
/// equivalent on the list card's side, so it simply isn't part of the
/// flight and fades in normally once the destination route settles.
class _AlbumHero extends StatelessWidget {
  const _AlbumHero({
    required this.detail,
    required this.thumbnailService,
    required this.epoch,
    required this.role,
    required this.onReauthRequired,
    required this.onTap,
  });

  final AlbumDetail detail;
  final DriveThumbnailService thumbnailService;
  final int epoch;
  final AlbumRole role;
  final VoidCallback onReauthRequired;
  final VoidCallback? onTap;

  static const _height = 300.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final heroPhoto = detail.photos.isEmpty ? null : detail.photos.first;

    final Widget background = heroPhoto == null
        ? DecoratedBox(
            decoration: BoxDecoration(gradient: gradientForAlbumId(detail.id)),
          )
        : _HeroPhotoImage(
            key: ValueKey('hero-${heroPhoto.id}#$epoch'),
            photo: heroPhoto,
            onReauthRequired: onReauthRequired,
            thumbnailService: thumbnailService,
          );

    final headlineShadows = MemoraTypography.legibilityShadows();
    final metadataShadows = MemoraTypography.legibilityShadows(
      intensity: 0.7,
    );

    return MemoraCurvedHero(
      height: _height,
      background: GestureDetector(
        onTap: onTap,
        child: Hero(tag: 'album-hero-${detail.id}', child: background),
      ),
      overlay: Stack(
        children: [
          // Top scrim: keeps the transparent app bar's back/owner-action
          // icons legible over any part of the photo.
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: 0.45,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      MemoraColors.deepInk.withValues(alpha: 0.75),
                      MemoraColors.deepInk.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom scrim: keeps the name/role legible, intensifying only
          // near the bottom edge so the photo itself stays visible.
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      MemoraColors.deepInk.withValues(alpha: 0),
                      MemoraColors.deepInk.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MemoraSpacing.lg,
                0,
                MemoraSpacing.lg,
                MemoraSpacing.xl + MemoraSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Explicit Paper: `textTheme.headlineMedium` now defaults
                  // to Deep Ink (the light-canvas color) — this title sits
                  // over the hero photo/gradient with a Deep Ink scrim
                  // instead, the deliberate dark exception (see
                  // memora_typography.dart's class doc).
                  Text(
                    detail.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.headlineMedium?.copyWith(
                      color: MemoraColors.paper,
                      shadows: headlineShadows,
                    ),
                  ),
                  const SizedBox(height: MemoraSpacing.xs),
                  MemoraBadge(
                    label: role == AlbumRole.owner ? 'Owner' : 'Colaborador',
                    variant: MemoraBadgeVariant.gradient,
                  ),
                  const SizedBox(height: MemoraSpacing.xs),
                  // Metadata row (mockup redesign, sin spec de Kiro): the
                  // same subtle legibility shadow as the headline above, at
                  // a lower intensity — small metadata text over a busy
                  // photo still needs it, just not as strongly as the large
                  // headline does.
                  _HeroMetadataRow(detail: detail, shadows: metadataShadows),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fetches and renders the hero photo's bytes — mirrors `_PhotoTile`'s
/// `late final`/`catchError`/re-throw pattern exactly (see CLAUDE.md: a
/// `Future` cached in a `late final` field needs the parent to key this
/// widget by `photo.id` + an epoch to force a fresh fetch after a Drive
/// reconnect; the error must be re-thrown, never swallowed, so
/// `FutureBuilder` still sees it). Kept as its own widget rather than
/// reusing `_PhotoTile` because the hero has no "remove" button, a bigger
/// error icon, and fills its container instead of a small grid cell.
/// The hero's metadata line (mockup redesign, sin spec de Kiro — ver
/// CLAUDE.md), directly below the role badge: photo count + creation date,
/// each behind a small icon. Purely presentational — reads straight off
/// [AlbumDetail.photoCount]/[AlbumDetail.createdAt], no new state or
/// controller call. The date is formatted by hand in Spanish
/// (`_formatDateEs`, e.g. "12 sep. 2026") — no date-formatting package
/// added for this.
class _HeroMetadataRow extends StatelessWidget {
  const _HeroMetadataRow({required this.detail, required this.shadows});

  final AlbumDetail detail;
  final List<Shadow> shadows;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: MemoraColors.paper,
      fontWeight: FontWeight.w700,
      shadows: shadows,
    );
    final iconColor = MemoraColors.paper.withValues(alpha: 0.9);

    Widget item(IconData icon, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor, shadows: shadows),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
        ],
      );
    }

    return Wrap(
      spacing: MemoraSpacing.md,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item(
          Icons.photo_outlined,
          detail.photoCount == 1
              ? '${detail.photoCount} foto'
              : '${detail.photoCount} fotos',
        ),
        item(
          Icons.calendar_today_outlined,
          'Creado el ${_formatDateEs(detail.createdAt)}',
        ),
      ],
    );
  }
}

class _HeroPhotoImage extends StatefulWidget {
  const _HeroPhotoImage({
    super.key,
    required this.photo,
    required this.thumbnailService,
    required this.onReauthRequired,
  });

  final Photo photo;
  final DriveThumbnailService thumbnailService;
  final VoidCallback onReauthRequired;

  @override
  State<_HeroPhotoImage> createState() => _HeroPhotoImageState();
}

class _HeroPhotoImageState extends State<_HeroPhotoImage> {
  late final Future<Uint8List> _future = widget.thumbnailService
      .getThumbnail(widget.photo.storageRef.fileId)
      .catchError((Object error) {
        if (error is DriveReauthorizationRequiredException) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onReauthRequired();
          });
        }
        throw error;
      });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MemoraColors.surface1,
      child: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snapshot) {
          final Widget child;
          if (snapshot.connectionState != ConnectionState.done) {
            child = const Center(
              key: ValueKey('loading'),
              child: MemoraLoadingState(),
            );
          } else if (snapshot.hasError) {
            final needsReauth =
                snapshot.error is DriveReauthorizationRequiredException;
            child = Center(
              key: const ValueKey('error'),
              child: Icon(
                needsReauth ? Icons.link_off : Icons.broken_image_outlined,
                size: 40,
                color: needsReauth
                    ? MemoraColors.semanticError
                    : MemoraColors.textTertiary,
              ),
            );
          } else {
            child = Image.memory(
              snapshot.data!,
              key: const ValueKey('image'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          }
          return AnimatedSwitcher(
            duration: MemoraMotion.moderate,
            switchInCurve: MemoraMotion.enterCurve,
            switchOutCurve: MemoraMotion.exitCurve,
            child: child,
          );
        },
      ),
    );
  }
}
