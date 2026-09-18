import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../auth/auth_controller.dart';
import '../../auth/drive_reconnect_prompt.dart';
import '../../design/design.dart';
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
///
/// Visual layer restyled in Fase 2 del rediseño "Aurora" (sin spec de
/// Kiro): still an immersive full-bleed viewer (no bright/light-card moment
/// here — an island would fight the photo itself for attention, unlike a
/// flow screen with a natural "reward" beat), but every `Colors.black`/
/// `Colors.white*` literal is replaced with `MemoraColors`, and the
/// error/unavailable "chrome" states reuse the app's icon-chip +
/// `MemoraSecondaryButton` language instead of a bare `OutlinedButton`.
/// NONE of `PhotoViewGallery`/`customChild`'s structure changed — see the
/// gotcha below and in CLAUDE.md before touching anything about gestures.
///
/// **Light-first pivot (60-30-10, sin spec de Kiro)**: this screen is a
/// **deliberate, explicit exception** to the pivot — kept dark on purpose,
/// the same platform convention Apple Photos/Google Photos follow (a
/// full-bleed photo viewer stays black even with the rest of the app in
/// light mode: photo brightness/contrast matters more here than matching
/// the app's own theme). Nothing about this screen's own colors changed —
/// `MemoraColors.deepInk` is still its background. What DID change: several
/// shared `lib/design/` tokens/components this screen borrows
/// (`MemoraColors.border`/`.textSecondary`, `MemoraSecondaryButton`'s
/// default foreground, `MemoraLoadingState`'s default spinner color) got
/// re-calibrated for the light canvas that's now the rest of the app — so
/// this screen can no longer rely on their defaults and passes explicit
/// light-on-dark overrides instead (see `_StateOverlay` and
/// `_PhotoViewerPage.build`).
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
      backgroundColor: MemoraColors.deepInk,
      appBar: AppBar(
        backgroundColor: MemoraColors.deepInk,
        elevation: 0,
        foregroundColor: MemoraColors.paper,
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
        backgroundDecoration: const BoxDecoration(color: MemoraColors.deepInk),
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
      return _StateOverlay(
        icon: Icons.cloud_off,
        message: 'Foto no disponible',
      );
    }

    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.connectionState != ConnectionState.done) {
          // Explicit raw glassBlue: `MemoraLoadingState`'s default
          // (glassBlueOnLight) is calibrated for the light canvas — this
          // screen is the deliberate dark exception (see the class doc).
          child = const Center(
            key: ValueKey('loading'),
            child: MemoraLoadingState(color: MemoraColors.glassBlue),
          );
        } else if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is DriveReauthorizationRequiredException) {
            child = _StateOverlay(
              key: const ValueKey('reauth-error'),
              icon: Icons.link_off,
              message: 'Hace falta reconectar Google Drive para ver esta foto.',
              actionLabel: _isReconnectingDrive
                  ? 'Reconectando...'
                  : 'Reconectar Google Drive',
              onAction: _isReconnectingDrive ? null : _reconnectDrive,
              loading: _isReconnectingDrive,
            );
          } else {
            child = _StateOverlay(
              key: const ValueKey('generic-error'),
              icon: Icons.broken_image_outlined,
              message: 'No se pudo cargar la foto.',
              actionLabel: 'Reintentar',
              onAction: _load,
            );
          }
        } else {
          child = Image.memory(
            snapshot.data!,
            key: const ValueKey('image'),
            fit: BoxFit.contain,
          );
        }
        // Placeholder -> fade-in -> image/error, same crossfade pattern as
        // `_PhotoTile`/`_HeroPhotoImage` (point 6 of the motion pass) —
        // safe to wrap here: `AnimatedSwitcher` is purely visual, it adds
        // no gesture recognizer of its own, so it doesn't interact with the
        // `photo_view` double-tap-arena gotcha documented on `_StateOverlay`.
        return AnimatedSwitcher(
          duration: MemoraMotion.moderate,
          switchInCurve: MemoraMotion.enterCurve,
          switchOutCurve: MemoraMotion.exitCurve,
          child: child,
        );
      },
    );
  }
}

/// The "unavailable" placeholder and every error state inside a photo_view
/// page, unified into one small widget: an icon in a tinted circular chip
/// (same visual language as `MemoraEmptyState`'s icon circle, just reused
/// inline instead of that widget directly — `MemoraEmptyState` always
/// renders its action as a `MemoraPrimaryButton`, which would be wrong here:
/// "Reintentar"/"Reconectar Google Drive" are recovery actions inside one
/// gallery page, not the screen's primary CTA, so they stay
/// `MemoraSecondaryButton` — same choice `album_detail_screen.dart` makes
/// for its own Drive-reauth banner).
///
/// Note on the ~300ms tap delay for [onAction] here: see CLAUDE.md — any
/// interactive widget inside a `photo_view` `customChild` sits in the same
/// gesture arena as `photo_view`'s always-registered double-tap-to-zoom
/// recognizer, so the tap genuinely fires, just after Flutter's
/// `kDoubleTapTimeout` elapses. Not something to "fix" by moving this
/// overlay outside `customChild` — out of scope for this pass.
///
/// **Light-first pivot**: this widget used to reuse the shared
/// `MemoraColors.surface2`/`.border`/`.textSecondary` tokens, which worked
/// because they were dark-canvas-calibrated back then. They're now
/// light-canvas-calibrated (mostly light greys/deepInk-based), so reusing
/// them here would be nearly invisible against this screen's deliberately
/// dark background. Rebuilt self-contained instead: a translucent
/// Paper-tinted circle/border/icon, hardcoded, independent of the
/// light-canvas tokens — same idea, computed relative to `deepInk`
/// (background) instead of relative to `paper` (the rest of the app's
/// background now).
class _StateOverlay extends StatelessWidget {
  const _StateOverlay({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Forwarded to `MemoraSecondaryButton.loading` — see its doc comment.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MemoraSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MemoraColors.paper.withValues(alpha: 0.08),
                border: Border.all(
                  color: MemoraColors.paper.withValues(alpha: 0.24),
                ),
              ),
              child: Icon(
                icon,
                size: 32,
                color: MemoraColors.paper.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: MemoraSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: MemoraColors.paper),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: MemoraSpacing.lg),
              MemoraSecondaryButton(
                label: actionLabel!,
                onPressed: onAction,
                color: MemoraColors.paper,
                loading: loading,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
