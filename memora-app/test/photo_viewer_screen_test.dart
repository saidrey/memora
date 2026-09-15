import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:memora_app/albums/drive_thumbnail_service.dart';
import 'package:memora_app/albums/screens/photo_viewer_screen.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/auth/auth_api.dart';
import 'package:memora_app/auth/auth_controller.dart';
import 'package:memora_app/auth/google_auth_service.dart';
import 'package:memora_app/auth/session_storage.dart';
import 'package:memora_app/photos/drive_token_api.dart';
import 'package:memora_app/photos/photo_models.dart';

/// Stands in for the real [DriveThumbnailService]: never touches the
/// network/`driveTokenApi` (its constructor is fed a client that fails
/// loudly if ever called), records every `fileId` it was asked for, and
/// lets each test script per-fileId success/failure — same pattern as the
/// `_Fake*` collaborators in auth_controller_test.dart.
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

  final List<String> requestedFileIds = [];
  final Map<String, Object> throwForFileId = {};
  final Map<String, Uint8List> bytesForFileId = {};
  int clearCacheCalls = 0;

  @override
  Future<Uint8List> getThumbnail(String fileId) async {
    requestedFileIds.add(fileId);
    final error = throwForFileId[fileId];
    if (error != null) throw error;
    return bytesForFileId[fileId] ?? Uint8List.fromList([1, 2, 3]);
  }

  @override
  void clearCache() {
    clearCacheCalls++;
  }
}

/// Real `AuthController` wired to non-network collaborators (mirrors
/// widget_test.dart's `_authController`) — never bootstrapped/signed in by
/// these tests, so no plugin channel or network call happens; it only needs
/// to exist for `PhotoViewerScreen`'s required parameter.
AuthController _authController() {
  final apiClient = ApiClient(
    httpClient: MockClient(
      (request) async =>
          throw StateError('unexpected network call: ${request.url}'),
    ),
    baseUrl: 'http://localhost:3000/api/v1',
  );
  return AuthController(
    authApi: AuthApi(apiClient),
    googleAuthService: GoogleAuthService(),
    sessionStorage: SessionStorage(),
    apiClient: apiClient,
  );
}

Photo _photo(String id, {PhotoAvailability availability = PhotoAvailability.available}) {
  return Photo(
    id: id,
    storageRef: StorageRef(provider: 'google-drive', fileId: 'file-$id'),
    availability: availability,
  );
}

void main() {
  testWidgets(
    'builds the gallery at the given initial index and requests that '
    "photo's file from the thumbnail service",
    (tester) async {
      final photos = [_photo('a'), _photo('b'), _photo('c')];
      final service = _FakeDriveThumbnailService()
        // Generic (non-reauth) failure for every file: avoids needing real
        // decodable image bytes for this test, which only cares about
        // which fileId got requested for the given initialIndex.
        ..throwForFileId['file-b'] = const DriveThumbnailException('boom');

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewerScreen(
            photos: photos,
            initialIndex: 1,
            thumbnailService: service,
            authController: _authController(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.requestedFileIds, contains('file-b'));
      expect(service.requestedFileIds, isNot(contains('file-a')));
      expect(service.requestedFileIds, isNot(contains('file-c')));
    },
  );

  testWidgets(
    'shows "Foto no disponible" for an unavailable photo without ever '
    'calling getThumbnail',
    (tester) async {
      final photos = [
        _photo('a', availability: PhotoAvailability.unavailable),
      ];
      final service = _FakeDriveThumbnailService();

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewerScreen(
            photos: photos,
            initialIndex: 0,
            thumbnailService: service,
            authController: _authController(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Foto no disponible'), findsOneWidget);
      expect(service.requestedFileIds, isEmpty);
    },
  );

  testWidgets(
    'a DRIVE_REAUTHORIZATION_REQUIRED failure offers a "Reconectar Google '
    'Drive" action instead of the generic retry',
    (tester) async {
      final photos = [_photo('a')];
      final service = _FakeDriveThumbnailService()
        ..throwForFileId['file-a'] = const DriveReauthorizationRequiredException();

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewerScreen(
            photos: photos,
            initialIndex: 0,
            thumbnailService: service,
            authController: _authController(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reconectar Google Drive'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    },
  );

  testWidgets(
    'a generic load error offers "Reintentar", and tapping it asks the '
    'thumbnail service again (never stuck on the first failed attempt)',
    (tester) async {
      final photos = [_photo('a')];
      final service = _FakeDriveThumbnailService()
        ..throwForFileId['file-a'] = const DriveThumbnailException('boom');

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewerScreen(
            photos: photos,
            initialIndex: 0,
            thumbnailService: service,
            authController: _authController(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reintentar'), findsOneWidget);
      expect(
        service.requestedFileIds.where((id) => id == 'file-a').length,
        1,
      );

      await tester.tap(find.text('Reintentar'));
      // photo_view always registers a DoubleTapGestureRecognizer on its
      // gesture detector (double-tap-to-zoom), even though this screen
      // never sets an onDoubleTap handler of its own. That recognizer
      // competes in the same gesture arena as this button's tap and only
      // rejects itself after Flutter's built-in double-tap window
      // (`kDoubleTapTimeout`, 300ms) elapses without a second tap — so a
      // single tap on any widget nested inside a photo_view customChild is
      // real, but delayed by up to that window before onPressed actually
      // fires. `pumpAndSettle` alone isn't enough here since it doesn't
      // reliably advance the fake clock past the pending timer; pumping
      // past `kDoubleTapTimeout` first does. Not a bug in this screen —
      // documented as a gotcha in CLAUDE.md for the next person who adds
      // interactive controls inside a photo_view page.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(
        service.requestedFileIds.where((id) => id == 'file-a').length,
        2,
      );
    },
  );
}
