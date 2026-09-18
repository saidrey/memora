import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/albums/albums_controller.dart';
import 'package:memora_app/albums/collaborators_api.dart';
import 'package:memora_app/albums/drive_thumbnail_service.dart';
import 'package:memora_app/albums/sharing_api.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/api/health_api.dart';
import 'package:memora_app/auth/auth_api.dart';
import 'package:memora_app/auth/auth_controller.dart';
import 'package:memora_app/auth/auth_models.dart';
import 'package:memora_app/auth/google_auth_service.dart';
import 'package:memora_app/auth/session_storage.dart';
import 'package:memora_app/photos/drive_token_api.dart';
import 'package:memora_app/photos/drive_upload_service.dart';
import 'package:memora_app/photos/photo_optimizer.dart';
import 'package:memora_app/photos/photo_upload_controller.dart';
import 'package:memora_app/photos/photos_api.dart';
import 'package:memora_app/screens/home_screen.dart';

ApiClient _healthyApiClient() {
  return ApiClient(
    httpClient: MockClient(
      (request) async => http.Response(
        '{"status":"ok"}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

/// AuthController wired to real collaborators, but its status/user are set
/// directly by the test and `bootstrap()` is never triggered (see
/// HomeScreen's "only bootstrap when status == unknown" guard) — so no
/// secure-storage plugin channel or network call happens in these tests.
AuthController _authController(ApiClient apiClient) {
  return AuthController(
    authApi: AuthApi(apiClient),
    googleAuthService: GoogleAuthService(),
    sessionStorage: SessionStorage(),
    apiClient: apiClient,
  );
}

AlbumsController _albumsController(ApiClient apiClient) {
  return AlbumsController(
    AlbumsApi(apiClient),
    CollaboratorsApi(apiClient),
    SharingApi(apiClient),
  );
}

DriveThumbnailService _driveThumbnailService(ApiClient apiClient) {
  return DriveThumbnailService(driveTokenApi: DriveTokenApi(apiClient));
}

/// A PhotoUploadController wired to real collaborators. These tests never
/// trigger `pickAndUploadPhotos`/`uploadPickedFiles`, so none of its
/// plugin-backed collaborators (ImagePicker, PhotoOptimizer) ever run —
/// see photo_upload_controller_test.dart for the orchestration logic itself.
PhotoUploadController _photoUploadController(ApiClient apiClient) {
  return PhotoUploadController(
    imagePicker: ImagePicker(),
    photoOptimizer: const PhotoOptimizer(),
    driveTokenApi: DriveTokenApi(apiClient),
    driveUploadService: DriveUploadService(),
    photosApi: PhotosApi(apiClient),
  );
}

void main() {
  testWidgets('shows the Google login composition when unauthenticated', (
    tester,
  ) async {
    final apiClient = _healthyApiClient();
    final auth = _authController(apiClient)
      ..status = AuthStatus.unauthenticated;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          healthApi: HealthApi(apiClient),
          authController: auth,
          photoUploadController: _photoUploadController(apiClient),
          albumsController: _albumsController(apiClient),
          driveThumbnailService: _driveThumbnailService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Pequeños momentos,'), findsOneWidget);
    expect(find.text('grandes recuerdos'), findsOneWidget);
  });

  testWidgets('shows user info and a logout button when authenticated', (
    tester,
  ) async {
    final apiClient = _healthyApiClient();
    final auth = _authController(apiClient)
      ..status = AuthStatus.authenticated
      ..user = const AuthUser(id: '1', email: 'user@example.com', name: 'Ada');

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          healthApi: HealthApi(apiClient),
          authController: auth,
          photoUploadController: _photoUploadController(apiClient),
          albumsController: _albumsController(apiClient),
          driveThumbnailService: _driveThumbnailService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    // "Cerrar sesión" moved out of the main content flow into a small
    // account-action icon button (see home_screen.dart) — found by its
    // tooltip, not as a full-width text button anymore.
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('shows a clear message after a failed/cancelled login attempt', (
    tester,
  ) async {
    final apiClient = _healthyApiClient();
    final auth = _authController(apiClient)
      ..status = AuthStatus.unauthenticated
      ..errorMessage = 'Inicio de sesión cancelado.';

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          healthApi: HealthApi(apiClient),
          authController: auth,
          photoUploadController: _photoUploadController(apiClient),
          albumsController: _albumsController(apiClient),
          driveThumbnailService: _driveThumbnailService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inicio de sesión cancelado.'), findsOneWidget);
  });
}
