import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/photos/drive_token_api.dart';

ApiClient _clientReturning(int statusCode, Map<String, dynamic> body) {
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

void main() {
  group('DriveTokenApi', () {
    test(
      'requests album-scoped authorization from the exact endpoint',
      () async {
        String? requestedPath;
        final api = DriveTokenApi(
          ApiClient(
            httpClient: MockClient((request) async {
              requestedPath = request.url.path;
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode({
                  'provider': 'google-drive',
                  'accessToken': 'ya29.album-token',
                  'expiresInSeconds': 3600,
                  'folderId': 'album-folder-1',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
            baseUrl: 'http://localhost:3000/api/v1',
          ),
        );

        final authorization = await api.getAlbumUploadAuthorization('album-1');

        expect(requestedPath, '/api/v1/photos/upload-authorization/album-1');
        expect(authorization.accessToken, 'ya29.album-token');
        expect(authorization.folderId, 'album-folder-1');
        expect(authorization.isExpired, isFalse);
      },
    );

    test('returns a DriveToken with a computed expiry on success', () async {
      final api = DriveTokenApi(
        _clientReturning(200, {
          'driveAccessToken': 'ya29.fake-drive-token',
          'expiresIn': 3600,
        }),
      );

      final before = DateTime.now();
      final token = await api.getDriveToken();
      final after = DateTime.now();

      expect(token.accessToken, 'ya29.fake-drive-token');
      expect(token.isExpired, isFalse);
      // expiresAt should land ~3600s minus the safety margin from now.
      expect(
        token.expiresAt.isAfter(before.add(const Duration(seconds: 3500))),
        isTrue,
      );
      expect(
        token.expiresAt.isBefore(after.add(const Duration(seconds: 3600))),
        isTrue,
      );
    });

    test(
      'maps a 401 DRIVE_REAUTHORIZATION_REQUIRED to the typed exception',
      () async {
        final api = DriveTokenApi(
          _clientReturning(401, {
            'code': 'DRIVE_REAUTHORIZATION_REQUIRED',
            'message': 'Drive authorization expired',
          }),
        );

        expect(
          () => api.getDriveToken(),
          throwsA(isA<DriveReauthorizationRequiredException>()),
        );
      },
    );

    test('lets any other error propagate as ApiException', () async {
      final api = DriveTokenApi(
        _clientReturning(500, {'code': 'INTERNAL_ERROR', 'message': 'boom'}),
      );

      expect(() => api.getDriveToken(), throwsA(isA<Exception>()));
    });
  });
}
