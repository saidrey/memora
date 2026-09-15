import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/auth_controller.dart';
import '../../auth/drive_reconnect_prompt.dart';
import '../../photos/drive_token_api.dart';
import '../../photos/photo_models.dart';
import '../../photos/photo_upload_controller.dart';
import '../album_models.dart';
import '../albums_controller.dart';
import '../collaborator_models.dart';
import '../drive_thumbnail_service.dart';
import '../sharing_models.dart';
import 'photo_viewer_screen.dart';

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
/// `_buildSharingSection`. Not a designed screen (UI mínima funcional).
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

  /// Set (via `_PhotoTile`'s error callback) as soon as any thumbnail fails
  /// with `DriveReauthorizationRequiredException` — drives the "Reconectar
  /// Google Drive" banner below.
  bool _hasThumbnailReauthFailure = false;
  bool _isReconnectingDrive = false;

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

  /// spec08-visor-foto-inapp.md: opens the full-screen viewer at the tapped
  /// photo's position, handing it the same photo list (order preserved) and
  /// the SAME `DriveThumbnailService`/`AuthController` instances this screen
  /// already uses — so the viewer shares the thumbnail cache (a photo
  /// already shown in the grid opens instantly) and the same Drive-reconnect
  /// flow (spec06), without any second download pipeline.
  void _openPhotoViewer(int index) {
    final photos = widget.controller.albumDetail?.photos;
    if (photos == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          photos: photos,
          initialIndex: index,
          thumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
        ),
      ),
    );
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
    await widget.controller.renameCurrentAlbum(newName);
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
                  Text(option == AlbumVisibility.public ? 'Pública' : 'Privada'),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;
    await widget.controller.updateCurrentAlbumVisibility(chosen);
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
    final deleted = await widget.controller.deleteCurrentAlbum();
    if (deleted && mounted) Navigator.of(context).pop();
  }

  /// D12: creates an invitation and offers to share its `url` through the
  /// system share sheet, showing `expiresAt`. Errors surface through the
  /// existing `mutationErrorMessage` banner, same as every other mutation on
  /// this screen.
  Future<void> _createAndShareInvitation() async {
    final created = await widget.controller.createInvitation();
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
    await widget.controller.revokeInvitation(invitation.id);
  }

  Future<void> _confirmRemoveCollaborator(CollaboratorListItem collaborator) async {
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
    await widget.controller.removeCollaborator(collaborator.userId);
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
    final left = await widget.controller.leaveCurrentAlbum();
    if (left && mounted) Navigator.of(context).pop();
  }

  /// M7: fetches (or creates, first time) the album's share-link. Errors
  /// surface through `shareLinkErrorMessage`, shown inline in the sharing
  /// section rather than the generic `mutationErrorMessage` banner, since
  /// this isn't a destructive mutation.
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
    await widget.controller.revokeShareLink();
  }

  /// M8: creates a new tag of [type] and appends it to the controller's
  /// in-memory list (see `AlbumsController.nfcQrTags`'s doc comment).
  Future<void> _createTag(NfcQrTagType type) async {
    await widget.controller.createNfcQrTag(type);
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
    await widget.controller.disableNfcQrTag(tag.id);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final detail = controller.albumDetail;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.name ?? 'Álbum'),
        actions: _isOwner && detail != null
            ? [
                IconButton(
                  onPressed: controller.isMutating ? null : _renameAlbum,
                  icon: const Icon(Icons.edit),
                  tooltip: 'Renombrar',
                ),
                IconButton(
                  onPressed: controller.isMutating ? null : _changeVisibility,
                  icon: const Icon(Icons.visibility),
                  tooltip: 'Cambiar visibilidad',
                ),
                IconButton(
                  onPressed: controller.isMutating ? null : _deleteAlbum,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Eliminar álbum',
                ),
              ]
            : null,
      ),
      body: SafeArea(child: _buildBody(controller)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.photoUploadController.isRunning ? null : _addPhotos,
        icon: const Icon(Icons.add_a_photo),
        label: Text(
          widget.photoUploadController.isRunning
              ? 'Subiendo...'
              : 'Agregar fotos',
        ),
      ),
    );
  }

  Widget _buildBody(AlbumsController controller) {
    if (controller.isLoadingDetail && controller.albumDetail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.detailErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            controller.detailErrorMessage!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final detail = controller.albumDetail;
    if (detail == null) return const SizedBox.shrink();

    // A single CustomScrollView (instead of a fixed photo grid plus a
    // separately-scrolling collaborators section) so the whole screen has
    // one scroll position — the photo grid stays lazy (SliverGrid.builder),
    // the collaborators/invitations section below it is built eagerly since
    // it's expected to stay small for an MVP album.
    return CustomScrollView(
      slivers: [
        if (controller.mutationErrorMessage != null)
          SliverToBoxAdapter(child: _errorBanner(controller.mutationErrorMessage!)),
        if (widget.photoUploadController.batchErrorMessage != null)
          SliverToBoxAdapter(
            child: _errorBanner(widget.photoUploadController.batchErrorMessage!),
          ),
        if (_hasThumbnailReauthFailure)
          SliverToBoxAdapter(child: _driveReauthBanner()),
        if (detail.photos.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Este álbum todavía no tiene fotos.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: detail.photos.length,
              itemBuilder: (context, index) {
                final photo = detail.photos[index];
                return _PhotoTile(
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
                  onRemove: () => _removePhoto(photo),
                  onReauthRequired: _onThumbnailReauthRequired,
                  onTap: () => _openPhotoViewer(index),
                );
              },
            ),
          ),
        if (_isOwner)
          SliverToBoxAdapter(child: _buildSharingSection(controller, detail)),
        SliverToBoxAdapter(
          child: _isOwner
              ? _buildOwnerCollaboratorsSection(controller)
              : _buildCollaboratorSection(controller),
        ),
      ],
    );
  }

  Widget _errorBanner(String message) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      message,
      style: const TextStyle(color: Colors.red, fontSize: 12),
      textAlign: TextAlign.center,
    ),
  );

  Widget _driveReauthBanner() => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: [
        const Text(
          'Hace falta reconectar Google Drive para ver algunas '
          'miniaturas.',
          style: TextStyle(color: Colors.red, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: _isReconnectingDrive ? null : _reconnectDrive,
          child: Text(
            _isReconnectingDrive ? 'Reconectando...' : 'Reconectar Google Drive',
          ),
        ),
      ],
    ),
  );

  /// spec07-compartir-nfc-qr.md, owner-only: the album's visibility (D17,
  /// linking back to the AppBar's "Cambiar visibilidad" action rather than
  /// duplicating that control), the share-link (M7: obtain/share/revoke),
  /// and NFC/QR tags (M8: create, render the QR / show the URL for NFC,
  /// block). See `AlbumsController.nfcQrTags`'s doc comment for why tags
  /// created in a previous screen session aren't listed here.
  Widget _buildSharingSection(AlbumsController controller, AlbumDetail detail) {
    final link = controller.shareLink;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text(
            'Compartir',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                detail.visibility == AlbumVisibility.public
                    ? 'Álbum público'
                    : 'Álbum privado',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              TextButton(
                onPressed: controller.isMutating ? null : _changeVisibility,
                child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Enlace de compartición',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (controller.isLoadingShareLink)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.shareLinkErrorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                controller.shareLinkErrorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            )
          else if (link == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton(
                onPressed: _obtainShareLink,
                child: const Text('Obtener enlace para compartir'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(link.url),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(text: link.url),
                        ),
                        icon: const Icon(Icons.share),
                        label: const Text('Compartir'),
                      ),
                      TextButton.icon(
                        onPressed: controller.isMutating
                            ? null
                            : _confirmRevokeShareLink,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Revocar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Etiquetas NFC/QR',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              'Solo se muestran las etiquetas creadas en esta sesión de la '
              'pantalla: al volver a abrir el álbum, esta lista empieza '
              'vacía de nuevo, aunque las etiquetas creadas antes siguen '
              'funcionando.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.isMutating
                    ? null
                    : () => _createTag(NfcQrTagType.qr),
                icon: const Icon(Icons.qr_code),
                label: const Text('Crear etiqueta QR'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isMutating
                    ? null
                    : () => _createTag(NfcQrTagType.nfc),
                icon: const Icon(Icons.nfc),
                label: const Text('Crear etiqueta NFC'),
              ),
            ],
          ),
          for (final tag in controller.nfcQrTags) _buildTagCard(controller, tag),
        ],
      ),
    );
  }

  Widget _buildTagCard(AlbumsController controller, NfcQrTag tag) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tag.type == NfcQrTagType.qr ? Icons.qr_code : Icons.nfc),
                const SizedBox(width: 8),
                Text(
                  tag.type == NfcQrTagType.qr ? 'QR' : 'NFC',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  tag.isDisabled ? 'Bloqueada' : 'Activa',
                  style: TextStyle(
                    fontSize: 12,
                    color: tag.isDisabled ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (tag.type == NfcQrTagType.qr)
              Center(child: QrImageView(data: tag.url, size: 160))
            else
              SelectableText(tag.url),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: (controller.isMutating || tag.isDisabled)
                    ? null
                    : () => _confirmDisableTag(tag),
                icon: const Icon(Icons.block),
                label: const Text('Bloquear'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D1/D12/D13: invite (share sheet), collaborators list ("quitar"),
  /// pending invitations ("revocar") — all owner-only, hidden entirely (not
  /// just disabled) for a collaborator, same criterion as the AppBar
  /// actions above.
  Widget _buildOwnerCollaboratorsSection(AlbumsController controller) {
    final pendingInvitations = controller.invitations
        .where((invitation) => invitation.isPending)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Colaboradores',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              TextButton.icon(
                onPressed: controller.isMutating
                    ? null
                    : _createAndShareInvitation,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Invitar'),
              ),
            ],
          ),
          if (controller.isLoadingCollaborators)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.collaboratorsErrorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                controller.collaboratorsErrorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            )
          else ...[
            if (controller.collaborators.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Todavía no tienes colaboradores en este álbum.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ...controller.collaborators.map(
                (collaborator) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(collaborator.userId),
                  subtitle: Text('Se unió el ${_formatDate(collaborator.joinedAt)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Quitar',
                    onPressed: controller.isMutating
                        ? null
                        : () => _confirmRemoveCollaborator(collaborator),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Invitaciones pendientes',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (pendingInvitations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No hay invitaciones pendientes.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ...pendingInvitations.map(
                (invitation) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text('Expira el ${_formatDate(invitation.expiresAt)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.cancel_outlined),
                    tooltip: 'Revocar',
                    onPressed: controller.isMutating
                        ? null
                        : () => _confirmRevokeInvitation(invitation),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// D5: the only collaborator-facing action of this section.
  Widget _buildCollaboratorSection(AlbumsController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          OutlinedButton.icon(
            onPressed: controller.isMutating ? null : _confirmLeaveAlbum,
            icon: const Icon(Icons.logout),
            label: const Text('Abandonar álbum'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
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

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          child: ColoredBox(
            color: Colors.black12,
            child: FutureBuilder<Uint8List>(
              future: _thumbnailFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  final needsReauth =
                      snapshot.error is DriveReauthorizationRequiredException;
                  return Center(
                    child: Icon(
                      needsReauth ? Icons.link_off : Icons.broken_image,
                      color: Colors.grey,
                    ),
                  );
                }
                return Image.memory(snapshot.data!, fit: BoxFit.cover);
              },
            ),
          ),
        ),
        if (isUnavailable)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: const Icon(Icons.cloud_off, color: Colors.white),
          ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: widget.onRemove,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
