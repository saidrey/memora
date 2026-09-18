import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'albums/albums_api.dart';
import 'albums/albums_controller.dart';
import 'albums/collaborators_api.dart';
import 'albums/drive_thumbnail_service.dart';
import 'albums/sharing_api.dart';
import 'api/api_client.dart';
import 'api/health_api.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/google_auth_service.dart';
import 'auth/session_storage.dart';
import 'design/memora_theme.dart';
import 'photos/drive_token_api.dart';
import 'photos/drive_upload_service.dart';
import 'photos/photo_optimizer.dart';
import 'photos/photo_upload_controller.dart';
import 'photos/photos_api.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MemoraApp());
}

class MemoraApp extends StatelessWidget {
  const MemoraApp({
    super.key,
    this.apiClient,
    this.authController,
    this.photoUploadController,
    this.albumsController,
    this.driveThumbnailService,
  });

  /// Overridable for tests; defaults to a real, shared backend-backed
  /// instance so the auth layer and health checks share one ApiClient
  /// (needed so the Authorization header set after login applies
  /// everywhere).
  final ApiClient? apiClient;
  final AuthController? authController;
  final PhotoUploadController? photoUploadController;
  final AlbumsController? albumsController;
  final DriveThumbnailService? driveThumbnailService;

  @override
  Widget build(BuildContext context) {
    final apiClient = this.apiClient ?? ApiClient();
    final authController =
        this.authController ??
        AuthController(
          authApi: AuthApi(apiClient),
          googleAuthService: GoogleAuthService(),
          sessionStorage: SessionStorage(),
          apiClient: apiClient,
        );
    // Shared by the photo-upload flow and the album thumbnails below — it's
    // a thin, stateless wrapper around ApiClient (see DriveTokenApi), so
    // sharing the instance is free. What is deliberately NOT shared is
    // each caller's cached DriveToken: see DriveThumbnailService's doc
    // comment for why.
    final driveTokenApi = DriveTokenApi(apiClient);
    final photoUploadController =
        this.photoUploadController ??
        PhotoUploadController(
          imagePicker: ImagePicker(),
          photoOptimizer: const PhotoOptimizer(),
          driveTokenApi: driveTokenApi,
          // Long-lived on purpose: the "Memora" Drive folder is the same
          // for the whole session, so caching its fileId beyond a single
          // batch (spec03-fotografias.md decision 1's minimum) saves a
          // repeat search/create on every subsequent "Agregar fotos" tap.
          driveUploadService: DriveUploadService(),
          photosApi: PhotosApi(apiClient),
        );
    final albumsController =
        this.albumsController ??
        AlbumsController(
          AlbumsApi(apiClient),
          CollaboratorsApi(apiClient),
          SharingApi(apiClient),
        );
    final driveThumbnailService =
        this.driveThumbnailService ??
        DriveThumbnailService(driveTokenApi: driveTokenApi);

    return MaterialApp(
      title: 'Memora',
      theme: MemoraTheme.theme,
      home: HomeScreen(
        healthApi: HealthApi(apiClient),
        authController: authController,
        photoUploadController: photoUploadController,
        albumsController: albumsController,
        driveThumbnailService: driveThumbnailService,
      ),
    );
  }
}
