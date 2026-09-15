import 'package:flutter/material.dart';

import '../albums/albums_controller.dart';
import '../albums/drive_thumbnail_service.dart';
import '../albums/screens/accept_invitation_screen.dart';
import '../albums/screens/albums_list_screen.dart';
import '../api/api_exception.dart';
import '../api/health_api.dart';
import '../auth/auth_controller.dart';
import '../auth/drive_reconnect_prompt.dart';
import '../photos/photo_upload_controller.dart';

enum _ConnectivityState { loading, connected, unavailable }

/// Minimal functional screen for memora-app/spec02-login-google.md and
/// spec03-fotografias.md — not a designed screen. Visual identity is a
/// separate, still-pending decision. Also keeps the spec01
/// backend-connectivity indicator, folded into this single home screen
/// instead of separate routes (no navigation stack exists yet, and one
/// combined screen matches "pantalla mínima").
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.healthApi,
    required this.authController,
    required this.photoUploadController,
    required this.albumsController,
    required this.driveThumbnailService,
  });

  final HealthApi healthApi;
  final AuthController authController;
  final PhotoUploadController photoUploadController;
  final AlbumsController albumsController;
  final DriveThumbnailService driveThumbnailService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _ConnectivityState _connectivity = _ConnectivityState.loading;
  String? _connectivityError;

  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_onAuthChanged);
    widget.photoUploadController.addListener(_onAuthChanged);
    // Only auto-restore on a fresh controller (status == unknown) — lets
    // tests/callers inject an already-resolved AuthController without
    // triggering a real secure-storage read.
    if (widget.authController.status == AuthStatus.unknown) {
      widget.authController.bootstrap();
    }
    _checkHealth();
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    widget.photoUploadController.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() => setState(() {});

  void _openAlbums() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumsListScreen(
          controller: widget.albumsController,
          photoUploadController: widget.photoUploadController,
          driveThumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
        ),
      ),
    );
  }

  void _openAcceptInvitation() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AcceptInvitationScreen(
          controller: widget.albumsController,
          photoUploadController: widget.photoUploadController,
          driveThumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
        ),
      ),
    );
  }

  Future<void> _checkHealth() async {
    setState(() {
      _connectivity = _ConnectivityState.loading;
      _connectivityError = null;
    });
    try {
      await widget.healthApi.getHealth();
      if (!mounted) return;
      setState(() => _connectivity = _ConnectivityState.connected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectivity = _ConnectivityState.unavailable;
        _connectivityError = error is ApiException
            ? error.message
            : 'Error desconocido';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authController;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Memora',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildConnectivityIndicator(),
                const SizedBox(height: 32),
                _buildAuthSection(auth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectivityIndicator() {
    final isLoading = _connectivity == _ConnectivityState.loading;
    final isConnected = _connectivity == _ConnectivityState.connected;

    if (isLoading) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Backend: ${isConnected ? "ok" : "no disponible"}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        if (!isConnected && _connectivityError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _connectivityError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildAuthSection(AuthController auth) {
    switch (auth.status) {
      case AuthStatus.unknown:
        return const CircularProgressIndicator();

      case AuthStatus.authenticating:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Iniciando sesión...'),
          ],
        );

      case AuthStatus.authenticated:
        final user = auth.user;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user?.name ?? user?.email ?? 'Sesión iniciada',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            if (user?.name != null) ...[
              const SizedBox(height: 4),
              Text(
                user!.email,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: auth.signOut,
              child: const Text('Cerrar sesión'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _openAlbums,
              child: const Text('Álbumes'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _openAcceptInvitation,
              child: const Text('Unirme a un álbum'),
            ),
            _buildPhotosSection(),
          ],
        );

      case AuthStatus.unauthenticated:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: auth.signIn,
              child: const Text('Iniciar sesión con Google'),
            ),
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                auth.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ],
        );
    }
  }

  Widget _buildPhotosSection() {
    final controller = widget.photoUploadController;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Fotos',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: controller.isRunning
              ? null
              : () => controller.pickAndUploadPhotos(),
          child: Text(controller.isRunning ? 'Subiendo...' : 'Agregar fotos'),
        ),
        if (controller.items.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...controller.items.map(_buildPhotoItemRow),
          const SizedBox(height: 8),
          if (!controller.isRunning) Text(_summaryText(controller)),
        ],
        if (controller.batchErrorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.batchErrorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
        if (controller.hasDriveReauthFailures) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: controller.isRunning ? null : _reconnectDriveForPhotos,
            child: const Text('Reconectar Google Drive'),
          ),
        ],
      ],
    );
  }

  /// Offers to reconnect Google Drive (spec06-sesion-y-reauth-drive.md,
  /// A1.6) and, on success, retries only the photos that failed with
  /// `DRIVE_REAUTHORIZATION_REQUIRED` in the last batch.
  Future<void> _reconnectDriveForPhotos() async {
    final reconnected = await promptDriveReconnect(
      context,
      widget.authController,
    );
    if (!reconnected || !mounted) return;
    await widget.photoUploadController.retryAfterDriveReconnect();
  }

  Widget _buildPhotoItemRow(PhotoUploadItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: switch (item.status) {
              PhotoUploadStatus.done => const Icon(
                Icons.check,
                size: 16,
                color: Colors.green,
              ),
              PhotoUploadStatus.error => const Icon(
                Icons.error_outline,
                size: 16,
                color: Colors.red,
              ),
              _ => const CircularProgressIndicator(strokeWidth: 2),
            },
          ),
          const SizedBox(width: 8),
          Text(_statusLabel(item), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _statusLabel(PhotoUploadItem item) {
    switch (item.status) {
      case PhotoUploadStatus.queued:
        return 'En espera';
      case PhotoUploadStatus.optimizing:
        return 'Optimizando...';
      case PhotoUploadStatus.uploading:
        return 'Subiendo...';
      case PhotoUploadStatus.registering:
        return 'Registrando...';
      case PhotoUploadStatus.done:
        return 'Lista';
      case PhotoUploadStatus.error:
        return item.errorMessage ?? 'Error';
    }
  }

  String _summaryText(PhotoUploadController controller) {
    final done = controller.items
        .where((item) => item.status == PhotoUploadStatus.done)
        .length;
    final failed = controller.items
        .where((item) => item.status == PhotoUploadStatus.error)
        .length;
    return '$done foto(s) subida(s), $failed con error';
  }
}
