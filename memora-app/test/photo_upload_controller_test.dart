import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/photos/drive_token_api.dart';
import 'package:memora_app/photos/drive_upload_service.dart';
import 'package:memora_app/photos/photo_optimizer.dart';
import 'package:memora_app/photos/photo_upload_controller.dart';
import 'package:memora_app/photos/photos_api.dart';

/// Stands in for the real (platform-channel-backed) PhotoOptimizer: returns
/// fixed, made-up "optimized" bytes/dimensions without touching
/// flutter_image_compress or dart:ui, so the orchestration logic can run in
/// a plain `flutter test`.
class _FakePhotoOptimizer extends PhotoOptimizer {
  const _FakePhotoOptimizer();

  @override
  Future<OptimizedPhoto> optimize(Uint8List sourceBytes) async {
    return OptimizedPhoto(
      bytes: Uint8List.fromList([...sourceBytes, 0xFF]),
      width: 100,
      height: 80,
    );
  }
}

XFile _fakeXFile(String name, {List<int> bytes = const [1, 2, 3]}) {
  return XFile.fromData(
    Uint8List.fromList(bytes),
    name: name,
    mimeType: 'image/jpeg',
  );
}

/// Builds an ApiClient whose backend responses are driven by [onDriveToken]
/// (for POST /auth/drive-token) and [onRegisterPhoto] (for POST /photos).
ApiClient _backendClient({
  required http.Response Function() onDriveToken,
  required http.Response Function(Map<String, dynamic> body) onRegisterPhoto,
}) {
  return ApiClient(
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/auth/drive-token')) {
        return onDriveToken();
      }
      if (request.url.path.endsWith('/photos')) {
        return onRegisterPhoto(
          jsonDecode(request.body) as Map<String, dynamic>,
        );
      }
      fail('Unexpected backend request: ${request.url}');
    }),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

http.Response _driveTokenOk({int expiresIn = 3600}) => http.Response(
  jsonEncode({'driveAccessToken': 'fake-drive-token', 'expiresIn': expiresIn}),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _driveTokenReauthRequired() => http.Response(
  jsonEncode({
    'code': 'DRIVE_REAUTHORIZATION_REQUIRED',
    'message': 'Drive authorization expired',
  }),
  401,
  headers: {'content-type': 'application/json'},
);

/// A 401 from the SESSION guard itself (expired JWT) — distinct from
/// [_driveTokenReauthRequired]'s Drive-specific 401, which carries a
/// different `code`.
http.Response _sessionExpired() => http.Response(
  jsonEncode({'code': 'UNAUTHORIZED', 'message': 'Unauthorized'}),
  401,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('PhotoUploadController.uploadPickedFiles', () {
    test(
      'processes every photo in sequence and reports a success summary',
      () async {
        var driveTokenCalls = 0;
        var registerCalls = 0;

        final apiClient = _backendClient(
          onDriveToken: () {
            driveTokenCalls++;
            return _driveTokenOk();
          },
          onRegisterPhoto: (body) {
            registerCalls++;
            expect(body['storageRef'], isA<Map<String, dynamic>>());
            return http.Response(
              jsonEncode({
                'id': 'photo-$registerCalls',
                'storageRef': {
                  'provider': 'google-drive',
                  'fileId': (body['storageRef'] as Map)['fileId'],
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          },
        );

        var driveUploadCalls = 0;
        final driveClient = MockClient((request) async {
          if (request.url.path == '/drive/v3/files' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'files': <dynamic>[]}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/drive/v3/files' &&
              request.method == 'POST') {
            return http.Response(
              jsonEncode({'id': 'memora-folder'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          driveUploadCalls++;
          return http.Response(
            jsonEncode({'id': 'drive-file-$driveUploadCalls'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final controller = PhotoUploadController(
          imagePicker: ImagePicker(),
          photoOptimizer: const _FakePhotoOptimizer(),
          driveTokenApi: DriveTokenApi(apiClient),
          driveUploadService: DriveUploadService(httpClient: driveClient),
          photosApi: PhotosApi(apiClient),
        );

        await controller.uploadPickedFiles([
          _fakeXFile('a.jpg'),
          _fakeXFile('b.jpg'),
        ]);

        expect(controller.isRunning, isFalse);
        expect(controller.items, hasLength(2));
        expect(
          controller.items.map((i) => i.status),
          everyElement(PhotoUploadStatus.done),
        );
        expect(controller.batchErrorMessage, isNull);
        expect(driveUploadCalls, 2);
        expect(registerCalls, 2);
        // The token is requested once and reused for the whole batch.
        expect(driveTokenCalls, 1);
      },
    );

    test('a photo that fails to upload to Drive is marked as an error without '
        'stopping the rest of the batch', () async {
      final apiClient = _backendClient(
        onDriveToken: () => _driveTokenOk(),
        onRegisterPhoto: (body) => http.Response(
          jsonEncode({
            'id': 'photo-ok',
            'storageRef': {
              'provider': 'google-drive',
              'fileId': (body['storageRef'] as Map)['fileId'],
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        ),
      );

      var driveCallCount = 0;
      final driveClient = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'files': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/drive/v3/files') {
          return http.Response(
            jsonEncode({'id': 'memora-folder'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        driveCallCount++;
        // First upload fails, second succeeds.
        if (driveCallCount == 1) {
          return http.Response('server error', 500);
        }
        return http.Response(
          jsonEncode({'id': 'drive-file-2'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final controller = PhotoUploadController(
        imagePicker: ImagePicker(),
        photoOptimizer: const _FakePhotoOptimizer(),
        driveTokenApi: DriveTokenApi(apiClient),
        driveUploadService: DriveUploadService(httpClient: driveClient),
        photosApi: PhotosApi(apiClient),
      );

      await controller.uploadPickedFiles([
        _fakeXFile('fails.jpg'),
        _fakeXFile('succeeds.jpg'),
      ]);

      expect(controller.items[0].status, PhotoUploadStatus.error);
      expect(controller.items[1].status, PhotoUploadStatus.done);
      expect(controller.isRunning, isFalse);
    });

    test('DRIVE_REAUTHORIZATION_REQUIRED marks remaining photos as failed with '
        'a clear message and stops requesting new tokens, without touching '
        'auth/session state', () async {
      var driveTokenCalls = 0;
      final apiClient = _backendClient(
        onDriveToken: () {
          driveTokenCalls++;
          return _driveTokenReauthRequired();
        },
        onRegisterPhoto: (_) =>
            fail('should never register a photo without a Drive upload'),
      );

      final driveClient = MockClient(
        (request) async =>
            fail('should never call Drive without a valid token'),
      );

      final controller = PhotoUploadController(
        imagePicker: ImagePicker(),
        photoOptimizer: const _FakePhotoOptimizer(),
        driveTokenApi: DriveTokenApi(apiClient),
        driveUploadService: DriveUploadService(httpClient: driveClient),
        photosApi: PhotosApi(apiClient),
      );

      await controller.uploadPickedFiles([
        _fakeXFile('a.jpg'),
        _fakeXFile('b.jpg'),
      ]);

      expect(
        controller.items.map((i) => i.status),
        everyElement(PhotoUploadStatus.error),
      );
      expect(controller.batchErrorMessage, contains('reconectar'));
      for (final item in controller.items) {
        expect(item.errorMessage, contains('reconectar'));
      }
      // Only the first photo actually calls the backend; the second is
      // short-circuited instead of repeating a call that would only fail
      // again the same way.
      expect(driveTokenCalls, 1);
    });

    test('a plain 401 (expired session JWT, not Drive-specific) marks the '
        'photo with a distinct message', () async {
      final apiClient = _backendClient(
        onDriveToken: () => _sessionExpired(),
        onRegisterPhoto: (_) =>
            fail('should never register a photo without a Drive upload'),
      );
      final driveClient = MockClient(
        (request) async =>
            fail('should never call Drive without a valid token'),
      );

      final controller = PhotoUploadController(
        imagePicker: ImagePicker(),
        photoOptimizer: const _FakePhotoOptimizer(),
        driveTokenApi: DriveTokenApi(apiClient),
        driveUploadService: DriveUploadService(httpClient: driveClient),
        photosApi: PhotosApi(apiClient),
      );

      await controller.uploadPickedFiles([_fakeXFile('a.jpg')]);

      expect(controller.items.single.status, PhotoUploadStatus.error);
      expect(
        controller.items.single.errorMessage,
        'Tu sesión expiró. Vuelve a iniciar sesión.',
      );
    });
  });

  group('PhotoUploadController.retryAfterDriveReconnect', () {
    test('retries only the items that failed with '
        'DRIVE_REAUTHORIZATION_REQUIRED, leaving already-done items alone',
        () async {
      // Photo 1's drive-token call succeeds but with a token that's already
      // expired by the time photo 2 needs one (expiresIn: 0) — forcing a
      // SECOND drive-token call within the same original batch, which is
      // configured to fail with DRIVE_REAUTHORIZATION_REQUIRED. This is the
      // only way to get one photo to `done` and a later one to the reauth
      // error within a single batch, since the controller normally caches
      // one token for the whole batch.
      var driveTokenCalls = 0;
      final apiClient = _backendClient(
        onDriveToken: () {
          driveTokenCalls++;
          if (driveTokenCalls == 1) return _driveTokenOk(expiresIn: 0);
          if (driveTokenCalls == 2) return _driveTokenReauthRequired();
          // Third call onward: simulates the token obtained after a
          // successful Drive reconnect.
          return _driveTokenOk();
        },
        onRegisterPhoto: (body) => http.Response(
          jsonEncode({
            'id': 'photo-${(body['storageRef'] as Map)['fileId']}',
            'storageRef': {
              'provider': 'google-drive',
              'fileId': (body['storageRef'] as Map)['fileId'],
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        ),
      );

      var driveUploadCalls = 0;
      final driveClient = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'files': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/drive/v3/files') {
          return http.Response(
            jsonEncode({'id': 'memora-folder'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        driveUploadCalls++;
        return http.Response(
          jsonEncode({'id': 'drive-file-$driveUploadCalls'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final controller = PhotoUploadController(
        imagePicker: ImagePicker(),
        photoOptimizer: const _FakePhotoOptimizer(),
        driveTokenApi: DriveTokenApi(apiClient),
        driveUploadService: DriveUploadService(httpClient: driveClient),
        photosApi: PhotosApi(apiClient),
      );

      await controller.uploadPickedFiles([
        _fakeXFile('a.jpg'),
        _fakeXFile('b.jpg'),
      ]);

      expect(controller.items[0].status, PhotoUploadStatus.done);
      expect(controller.items[1].status, PhotoUploadStatus.error);
      expect(controller.items[1].failedDueToDriveReauth, isTrue);
      expect(controller.hasDriveReauthFailures, isTrue);

      // Simulate a successful reconnect: every subsequent drive-token call
      // now succeeds.
      await controller.retryAfterDriveReconnect();

      expect(controller.items[0].status, PhotoUploadStatus.done);
      expect(controller.items[1].status, PhotoUploadStatus.done);
      expect(controller.items[1].failedDueToDriveReauth, isFalse);
      expect(controller.hasDriveReauthFailures, isFalse);
      expect(controller.isRunning, isFalse);
      // The first (already-done) item's photo must be untouched/unchanged —
      // retryAfterDriveReconnect never re-processes it.
      expect(controller.items[0].photo?.id, isNotNull);
    });

    test('is a no-op when nothing failed due to Drive reauthorization',
        () async {
      final apiClient = _backendClient(
        onDriveToken: () => _driveTokenOk(),
        onRegisterPhoto: (body) => http.Response(
          jsonEncode({
            'id': 'photo-ok',
            'storageRef': {
              'provider': 'google-drive',
              'fileId': (body['storageRef'] as Map)['fileId'],
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        ),
      );
      final driveClient = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'files': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/drive/v3/files') {
          return http.Response(
            jsonEncode({'id': 'memora-folder'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'id': 'drive-file'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final controller = PhotoUploadController(
        imagePicker: ImagePicker(),
        photoOptimizer: const _FakePhotoOptimizer(),
        driveTokenApi: DriveTokenApi(apiClient),
        driveUploadService: DriveUploadService(httpClient: driveClient),
        photosApi: PhotosApi(apiClient),
      );

      await controller.uploadPickedFiles([_fakeXFile('a.jpg')]);
      expect(controller.items.single.status, PhotoUploadStatus.done);

      await controller.retryAfterDriveReconnect();

      // Nothing re-processed: still just the one done item, unchanged.
      expect(controller.items, hasLength(1));
      expect(controller.items.single.status, PhotoUploadStatus.done);
      expect(controller.isRunning, isFalse);
    });
  });
}
