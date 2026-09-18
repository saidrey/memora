import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'package:memora_app/albums/album_models.dart';
import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/albums/albums_controller.dart';
import 'package:memora_app/albums/collaborators_api.dart';
import 'package:memora_app/albums/drive_thumbnail_service.dart';
import 'package:memora_app/albums/screens/album_detail_screen.dart';
import 'package:memora_app/albums/sharing_api.dart';
import 'package:memora_app/api/api_client.dart';
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

const _albumId = 'album-1';
const _photoId = 'photo-1';

/// Never actually fetches bytes — this test only cares about the "×"
/// button's confirmation step, not about thumbnail rendering, so it always
/// fails fast with a generic (non-reauth) error, same pattern as
/// `photo_viewer_screen_test.dart`'s fake.
class _FakeDriveThumbnailService extends DriveThumbnailService {
  _FakeDriveThumbnailService()
    : super(
        driveTokenApi: DriveTokenApi(
          ApiClient(
            httpClient: MockClient(
              (request) async =>
                  throw StateError('unexpected network call: ${request.url}'),
            ),
            baseUrl: 'http://localhost:3000/api/v1',
          ),
        ),
      );

  @override
  Future<Uint8List> getThumbnail(String fileId) async {
    throw const DriveThumbnailException('not needed for this test');
  }
}

/// Real `AlbumsController` wired to a `MockClient` that only answers this
/// screen's initial `GET /albums/:id` load — `removePhotoFromCurrentAlbum`
/// is overridden to just record whether/how many times it was called
/// instead of hitting the network for the DELETE + follow-up refetch. The
/// whole point of the bug fix under test is "does the UI call this at all
/// before the user confirms", not the mutation's own network behavior
/// (already covered by `albums_controller_test.dart`).
class _TrackingAlbumsController extends AlbumsController {
  _TrackingAlbumsController(super.api, super.collaboratorsApi, super.sharingApi);

  int removeCalls = 0;

  @override
  Future<void> removePhotoFromCurrentAlbum(String photoId) async {
    removeCalls++;
  }
}

ApiClient _apiClient() {
  return ApiClient(
    httpClient: MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/albums/$_albumId') {
        return http.Response(
          '''
          {
            "id": "$_albumId",
            "name": "Álbum de prueba",
            "visibility": "PRIVATE",
            "photoCount": 1,
            "createdAt": "2026-01-01T00:00:00.000Z",
            "updatedAt": "2026-01-01T00:00:00.000Z",
            "photos": [
              {
                "id": "$_photoId",
                "storageRef": {"provider": "google-drive", "fileId": "file-1"}
              }
            ]
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      throw StateError(
        'unexpected network call: ${request.method} ${request.url}',
      );
    }),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

/// Same shape as `_apiClient()` above, but with a caller-supplied `photos`
/// array — used by the "Fotos" tab sort-order tests, which need more than
/// one photo (some with `capturedAt`, some without) to actually exercise
/// `_sortedPhotos`.
ApiClient _apiClientWithPhotos(String photosJson) {
  return ApiClient(
    httpClient: MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/albums/$_albumId') {
        return http.Response(
          '''
          {
            "id": "$_albumId",
            "name": "Álbum de prueba",
            "visibility": "PRIVATE",
            "photoCount": 3,
            "createdAt": "2026-01-01T00:00:00.000Z",
            "updatedAt": "2026-01-01T00:00:00.000Z",
            "photos": $photosJson
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      throw StateError(
        'unexpected network call: ${request.method} ${request.url}',
      );
    }),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

/// Real `AuthController` wired to non-network collaborators — never
/// bootstrapped/signed in by this test, mirrors
/// `photo_viewer_screen_test.dart`'s helper of the same name.
AuthController _authController(ApiClient apiClient) {
  return AuthController(
    authApi: AuthApi(apiClient),
    googleAuthService: GoogleAuthService(),
    sessionStorage: SessionStorage(),
    apiClient: apiClient,
  );
}

/// Real `PhotoUploadController` wired to real collaborators — this test
/// never triggers `pickAndUploadPhotos`, so none of its plugin-backed
/// collaborators (`ImagePicker`, `PhotoOptimizer`) ever run, same as
/// `widget_test.dart`'s helper of the same name.
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
  testWidgets(
    'removing a photo asks for confirmation first, and only calls '
    'removePhotoFromCurrentAlbum after the user confirms — never on the '
    'first tap of the "×" button',
    (tester) async {
      final apiClient = _apiClient();
      final controller = _TrackingAlbumsController(
        AlbumsApi(apiClient),
        CollaboratorsApi(apiClient),
        SharingApi(apiClient),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumDetailScreen(
            controller: controller,
            photoUploadController: _photoUploadController(apiClient),
            driveThumbnailService: _FakeDriveThumbnailService(),
            authController: _authController(apiClient),
            albumId: _albumId,
            // collaborator (not owner): keeps this test focused on the
            // photo-removal confirmation without also needing to fake the
            // owner-only collaborators/invitations load that
            // `initState` triggers for an owner.
            role: AlbumRole.collaborator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final removeButton = find.byIcon(Icons.close);
      expect(removeButton, findsOneWidget);

      // First tap: must show the confirmation dialog, NOT call the
      // controller directly (the bug being fixed).
      await tester.tap(removeButton);
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar esta foto?'), findsOneWidget);
      expect(controller.removeCalls, 0);

      // Cancelling must not remove the photo either.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(controller.removeCalls, 0);
      expect(find.text('¿Eliminar esta foto?'), findsNothing);

      // Confirming is what finally calls the controller.
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(controller.removeCalls, 1);
    },
  );

  testWidgets(
    'the "Fotos" tab sorts photos by capturedAt, newest first by default, '
    'with a null capturedAt always sinking to the end regardless of sort '
    'direction — a pure client-side presentation choice, never touching '
    'AlbumsController/detail.photos itself',
    (tester) async {
      final apiClient = _apiClientWithPhotos('''
        [
          {
            "id": "photo-old",
            "storageRef": {"provider": "google-drive", "fileId": "file-old"},
            "capturedAt": "2020-01-01T00:00:00.000Z"
          },
          {
            "id": "photo-new",
            "storageRef": {"provider": "google-drive", "fileId": "file-new"},
            "capturedAt": "2022-01-01T00:00:00.000Z"
          },
          {
            "id": "photo-null",
            "storageRef": {"provider": "google-drive", "fileId": "file-null"}
          }
        ]
      ''');
      final controller = AlbumsController(
        AlbumsApi(apiClient),
        CollaboratorsApi(apiClient),
        SharingApi(apiClient),
      );

      // A tall surface so all 3 grid tiles (2 columns -> 2 rows) are laid
      // out without needing to scroll — `SliverGrid.builder` is lazy, and
      // the default test viewport is only tall enough for the first row
      // (hero + tabs + header already eat most of it).
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumDetailScreen(
            controller: controller,
            photoUploadController: _photoUploadController(apiClient),
            driveThumbnailService: _FakeDriveThumbnailService(),
            authController: _authController(apiClient),
            albumId: _albumId,
            role: AlbumRole.collaborator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const ids = ['photo-old', 'photo-new', 'photo-null'];
      List<String> currentOrder() {
        final positions = {
          for (final id in ids)
            id: tester.getTopLeft(find.byKey(ValueKey('$id#0'))),
        };
        final sorted = [...ids]..sort((a, b) {
          final pa = positions[a]!;
          final pb = positions[b]!;
          final dy = pa.dy.compareTo(pb.dy);
          return dy != 0 ? dy : pa.dx.compareTo(pb.dx);
        });
        return sorted;
      }

      // Default ("Más recientes"): newest first, null-capturedAt last.
      expect(currentOrder(), ['photo-new', 'photo-old', 'photo-null']);

      // Toggle the sort control to "Más antiguas".
      await tester.tap(find.text('Más recientes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Más antiguas'));
      await tester.pumpAndSettle();

      // Ascending now, but the null-capturedAt photo STILL sinks to the
      // end — never shuffled to the front just because the direction
      // flipped.
      expect(currentOrder(), ['photo-old', 'photo-new', 'photo-null']);
    },
  );

  testWidgets(
    'tapping the "Colaboradores" app bar icon switches the active tab to '
    'show the collaborator\'s "Abandonar álbum" action inline — replacing '
    'the old bottom-sheet trigger',
    (tester) async {
      final apiClient = _apiClient();
      final controller = AlbumsController(
        AlbumsApi(apiClient),
        CollaboratorsApi(apiClient),
        SharingApi(apiClient),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumDetailScreen(
            controller: controller,
            photoUploadController: _photoUploadController(apiClient),
            driveThumbnailService: _FakeDriveThumbnailService(),
            authController: _authController(apiClient),
            albumId: _albumId,
            role: AlbumRole.collaborator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts on the "Fotos" tab (the default/initial content).
      expect(find.text('Abandonar álbum'), findsNothing);

      await tester.tap(find.byTooltip('Colaboradores'));
      await tester.pumpAndSettle();

      expect(find.text('Abandonar álbum'), findsOneWidget);
    },
  );

  testWidgets(
    'owner view: the "Colaboradores" tab shows the current user\'s own row '
    '(real name, "Tú" tag, "Owner" badge) and one row per other '
    'collaborator (generic "Colaborador" label, never an invented name), '
    'and the "Compartir" tab shows the visibility pill and the "más formas '
    'de compartir" banner — restyle per the colaboradores.png reference '
    '(mockup redesign, sin spec de Kiro)',
    (tester) async {
      final apiClient = ApiClient(
        httpClient: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/albums/$_albumId') {
            return http.Response(
              '''
              {
                "id": "$_albumId",
                "name": "Álbum de prueba",
                "visibility": "PRIVATE",
                "photoCount": 0,
                "createdAt": "2026-01-01T00:00:00.000Z",
                "updatedAt": "2026-01-01T00:00:00.000Z",
                "photos": []
              }
              ''',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' &&
              request.url.path ==
                  '/api/v1/albums/$_albumId/collaborators') {
            return http.Response(
              '''
              [
                {
                  "userId": "user-other-1",
                  "role": "collaborator",
                  "joinedAt": "2026-01-02T00:00:00.000Z"
                }
              ]
              ''',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/albums/$_albumId/invitations') {
            return http.Response('[]', 200,
                headers: {'content-type': 'application/json'});
          }
          throw StateError(
            'unexpected network call: ${request.method} ${request.url}',
          );
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      );
      final controller = AlbumsController(
        AlbumsApi(apiClient),
        CollaboratorsApi(apiClient),
        SharingApi(apiClient),
      );
      final authController = _authController(apiClient)
        ..user = const AuthUser(
          id: 'owner-1',
          email: 'owner@example.com',
          name: 'Ana Owner',
        );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumDetailScreen(
            controller: controller,
            photoUploadController: _photoUploadController(apiClient),
            driveThumbnailService: _FakeDriveThumbnailService(),
            authController: authController,
            albumId: _albumId,
            role: AlbumRole.owner,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Colaboradores'));
      await tester.pumpAndSettle();

      // The owner's own row: real name, "Tú" tag, "Owner" badge.
      expect(find.text('Ana Owner'), findsOneWidget);
      expect(find.text('Tú'), findsOneWidget);
      // "Owner" also appears in the hero's role badge overlay (unrelated,
      // pre-existing) — this row just needs to add one more.
      expect(find.text('Owner'), findsWidgets);
      // The other collaborator's row: generic label, never an invented
      // name — `CollaboratorListItem` only carries `userId`. Appears twice
      // (the row's title AND its trailing role badge both read
      // "Colaborador").
      expect(find.text('Colaborador'), findsNWidgets(2));
      expect(find.text('user-other-1'), findsNothing);

      await tester.tap(find.byTooltip('Compartir'));
      await tester.pumpAndSettle();

      expect(find.text('Álbum privado'), findsOneWidget);
      expect(find.text('Comparte con solo un toque'), findsOneWidget);
      expect(find.text('Crear etiqueta QR'), findsOneWidget);
      expect(find.text('Compartir en otras apps'), findsOneWidget);
    },
  );
}
