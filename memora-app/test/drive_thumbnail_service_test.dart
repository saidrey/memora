import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/albums/drive_thumbnail_service.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/photos/drive_token_api.dart';

ApiClient _driveTokenClientReturning(int statusCode, Map<String, dynamic> body) {
  return ApiClient(
    httpClient: MockClient(
      (request) async => http.Response(
        jsonEncode(body),
        statusCode,
        headers: {'content-type': 'application/json'},
      ),
    ),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

http.Response _driveTokenOk() => http.Response(
  jsonEncode({'driveAccessToken': 'fake-drive-token', 'expiresIn': 3600}),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('DriveThumbnailService.getThumbnail', () {
    test('downloads bytes from Drive using alt=media and the driveAccessToken', () async {
      late Uri requestedUri;
      late String? authHeader;
      final driveClient = MockClient((request) async {
        requestedUri = request.url;
        authHeader = request.headers['Authorization'];
        return http.Response.bytes([1, 2, 3], 200);
      });

      final service = DriveThumbnailService(
        driveTokenApi: DriveTokenApi(
          _driveTokenClientReturning(200, {
            'driveAccessToken': 'fake-drive-token',
            'expiresIn': 3600,
          }),
        ),
        httpClient: driveClient,
      );

      final bytes = await service.getThumbnail('file-1');

      expect(bytes, Uint8List.fromList([1, 2, 3]));
      expect(
        requestedUri.toString(),
        'https://www.googleapis.com/drive/v3/files/file-1?alt=media',
      );
      expect(authHeader, 'Bearer fake-drive-token');
    });

    test('caches bytes in memory: a second call for the same fileId does not '
        'hit the network again', () async {
      var driveCallCount = 0;
      final driveClient = MockClient((request) async {
        driveCallCount++;
        return http.Response.bytes([9, 9], 200);
      });
      var tokenCallCount = 0;
      final tokenApiClient = ApiClient(
        httpClient: MockClient((request) async {
          tokenCallCount++;
          return _driveTokenOk();
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      );

      final service = DriveThumbnailService(
        driveTokenApi: DriveTokenApi(tokenApiClient),
        httpClient: driveClient,
      );

      await service.getThumbnail('file-1');
      await service.getThumbnail('file-1');

      expect(driveCallCount, 1);
      expect(tokenCallCount, 1);
    });

    test('reuses a non-expired drive token across different files', () async {
      var tokenCallCount = 0;
      final tokenApiClient = ApiClient(
        httpClient: MockClient((request) async {
          tokenCallCount++;
          return _driveTokenOk();
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      );
      final driveClient = MockClient(
        (request) async => http.Response.bytes([1], 200),
      );

      final service = DriveThumbnailService(
        driveTokenApi: DriveTokenApi(tokenApiClient),
        httpClient: driveClient,
      );

      await service.getThumbnail('file-1');
      await service.getThumbnail('file-2');

      expect(tokenCallCount, 1);
    });

    test('lets DRIVE_REAUTHORIZATION_REQUIRED propagate unwrapped', () async {
      final service = DriveThumbnailService(
        driveTokenApi: DriveTokenApi(
          _driveTokenClientReturning(401, {
            'code': 'DRIVE_REAUTHORIZATION_REQUIRED',
            'message': 'Drive authorization expired',
          }),
        ),
        httpClient: MockClient(
          (request) async => fail('should never call Drive without a token'),
        ),
      );

      await expectLater(
        service.getThumbnail('file-1'),
        throwsA(isA<DriveReauthorizationRequiredException>()),
      );
    });

    test('wraps a Drive-side failure as DriveThumbnailException', () async {
      final service = DriveThumbnailService(
        driveTokenApi: DriveTokenApi(
          _driveTokenClientReturning(200, {
            'driveAccessToken': 'fake-drive-token',
            'expiresIn': 3600,
          }),
        ),
        httpClient: MockClient(
          (request) async => http.Response('server error', 500),
        ),
      );

      await expectLater(
        service.getThumbnail('file-1'),
        throwsA(isA<DriveThumbnailException>()),
      );
    });
  });
}
