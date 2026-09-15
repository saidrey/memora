import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../auth/auth_controller.dart';
import '../../auth/drive_reconnect_prompt.dart';
import '../../photos/drive_token_api.dart';
import '../../photos/photo_models.dart';
import '../drive_thumbnail_service.dart';

/// Full-screen photo viewer (spec08-visor-foto-inapp.md): opened by tapping
/// a thumbnail in the album detail grid (spec04). Shows the photo in full
/// resolution with zoom/pan/double-tap (via `photo_view`) and swipe
/// navigation across the album's photos, in the same order as the detail
/// grid.
///
/// Key design point (see spec08's brief): "full resolution" here is NOT a
/// second, higher-quality download pipeline. `DriveThumbnailService.
/// getThumbnail` already downloads the complete file from Drive
/// (`alt=media`) — the photo optimized to ≤2048px on its longer side at
/// upload time (spec03) IS what Drive stores and what that method returns.
/// So this screen calls the exact same method, with the exact same shared
/// [DriveThumbnailService] instance the caller already uses for the grid —
/// inheriting its in-memory cache (a photo already shown as a thumbnail
/// opens instantly here) and never duplicating the download pipeline.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.thumbnailService,
    required this.authController,
  });

  final List<Photo> photos;
  final int initialIndex;
  final DriveThumbnailService thumbnailService;
  final AuthController authController;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // Minimal chrome (UI mínima funcional, spec08): just a way back. No
        // metadata/location shown here (D8) — dimensions/capture date are
        // optional per the spec and not included in this cut.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: widget.photos.length,
        builder: (context, index) {
          final photo = widget.photos[index];
          // .customChild (not `imageProvider:`) is what lets each page own
          // async loading/error/retry state while still getting photo_view's
          // zoom/pan/pinch/double-tap behavior wrapped around whatever this
          // child ends up rendering.
          return PhotoViewGalleryPageOptions.customChild(
            child: _PhotoViewerPage(
              key: ValueKey(photo.id),
              photo: photo,
              thumbnailService: widget.thumbnailService,
              authController: widget.authController,
            ),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
          );
        },
      ),
    );
  }
}

/// One page of the gallery. A separate `StatefulWidget` per page (rather
/// than sharing state at the gallery level) so each photo's load/retry
/// state is independent — swiping to another photo never disturbs a page
/// that's mid-error or mid-retry.
///
/// Deliberately NOT `late final Future<Uint8List>` (the gotcha documented in
/// CLAUDE.md for `_PhotoTile`): a `late final` future is computed once and
/// never again, so a "reintentar" button would have nothing new to trigger.
/// `_future` is a mutable field reassigned by `_load()`, called from
/// `initState` and again on every retry / after a successful Drive
/// reconnect.
class _PhotoViewerPage extends StatefulWidget {
  const _PhotoViewerPage({
    super.key,
    required this.photo,
    required this.thumbnailService,
    required this.authController,
  });

  final Photo photo;
  final DriveThumbnailService thumbnailService;
  final AuthController authController;

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  Future<Uint8List>? _future;
  bool _isReconnectingDrive = false;

  bool get _isUnavailable =>
      widget.photo.availability == PhotoAvailability.unavailable;

  @override
  void initState() {
    super.initState();
    // Photos marked `unavailable` (M6) never attempt a Drive download at
    // all — `_future` stays null and `build` shows the placeholder directly.
    if (!_isUnavailable) _load();
  }

  void _load() {
    final future = widget.thumbnailService.getThumbnail(
      widget.photo.storageRef.fileId,
    );
    // `Future.ignore()` marks `future` as intentionally fire-and-forget
    // for Dart's zone-level "unhandled future error" detection, without
    // consuming it — `future` itself (not a derived future) is still what
    // gets stored and handed to `FutureBuilder` below (Futures support
    // multiple independent listeners, unlike Streams). This matters
    // specifically because `_load` can run from a tap callback
    // ("Reintentar"/after reconnecting), not just `initState`: unlike
    // `_PhotoTile`'s `late final` future in album_detail_screen.dart
    // (created in `initState`, immediately followed by a synchronous
    // `build()` that subscribes `FutureBuilder` in the same frame),
    // `setState` here only schedules a rebuild for the NEXT frame — a real
    // gap during which `future` would otherwise have no listener at all if
    // it settles before then, and Dart would report it as unhandled and
    // crash instead of surfacing the intended error state. Reproduced in
    // `test/photo_viewer_screen_test.dart` with a fake service that
    // resolves within a microtask — a real Drive call is slow enough that
    // the next frame usually beats it, but this must not be relied on.
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  Future<void> _reconnectDrive() async {
    setState(() => _isReconnectingDrive = true);
    final reconnected = await promptDriveReconnect(
      context,
      widget.authController,
    );
    if (!mounted) return;
    setState(() => _isReconnectingDrive = false);
    if (reconnected) {
      // Same mechanism the album grid uses after a successful reconnect
      // (spec06): drop the cached bytes AND the cached Drive token, then
      // ask again. No need to propagate this to other already-open pages —
      // the byte cache is only ever populated on success, never on
      // failure, so there's nothing "stuck" left behind for them; they'll
      // simply request with the now-fresh token if/when the user swipes to
      // them.
      widget.thumbnailService.clearCache();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnavailable) {
      return _placeholder(
        icon: Icons.cloud_off,
        message: 'Foto no disponible',
      );
    }

    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is DriveReauthorizationRequiredException) {
            return _errorState(
              message: 'Hace falta reconectar Google Drive para ver '
                  'esta foto.',
              actionLabel: _isReconnectingDrive
                  ? 'Reconectando...'
                  : 'Reconectar Google Drive',
              onAction: _isReconnectingDrive ? null : _reconnectDrive,
            );
          }
          return _errorState(
            message: 'No se pudo cargar la foto.',
            actionLabel: 'Reintentar',
            onAction: _load,
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.contain);
      },
    );
  }

  Widget _placeholder({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _errorState({
    required String message,
    required String actionLabel,
    required VoidCallback? onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image, color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
