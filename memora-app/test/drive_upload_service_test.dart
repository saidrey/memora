import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/photos/drive_upload_service.dart';

void main() {
  group('DriveUploadService', () {
    test('searches for the "Memora" folder, creates it if missing, then '
        'uploads into it — and caches the folder id across uploads', () async {
      var searchCalls = 0;
      var createCalls = 0;
      var uploadCalls = 0;

      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/drive/v3/files') {
          searchCalls++;
          expect(request.headers['Authorization'], 'Bearer fake-token');
          expect(request.url.queryParameters['q'], contains('Memora'));
          return http.Response(
            jsonEncode({'files': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/drive/v3/files') {
          createCalls++;
          return http.Response(
            jsonEncode({'id': 'folder-123'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/upload/drive/v3/files') {
          uploadCalls++;
          final bodyText = utf8.decode(request.bodyBytes);
          expect(bodyText, contains('"parents":["folder-123"]'));
          return http.Response(
            jsonEncode({'id': 'file-${uploadCalls == 1 ? 1 : 2}'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });

      final service = DriveUploadService(httpClient: client);

      final fileId1 = await service.uploadFile(
        accessToken: 'fake-token',
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'photo1.jpg',
        mimeType: 'image/jpeg',
      );
      final fileId2 = await service.uploadFile(
        accessToken: 'fake-token',
        bytes: Uint8List.fromList([4, 5, 6]),
        fileName: 'photo2.jpg',
        mimeType: 'image/jpeg',
      );

      expect(fileId1, 'file-1');
      expect(fileId2, 'file-2');
      expect(searchCalls, 1, reason: 'folder lookup should be cached');
      expect(createCalls, 1, reason: 'folder should be created once');
      expect(uploadCalls, 2);
    });

    test(
      'reuses an existing "Memora" folder instead of creating one',
      () async {
        var createCalls = 0;
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'existing-folder', 'name': 'Memora'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/drive/v3/files') {
            createCalls++;
          }
          return http.Response(
            jsonEncode({'id': 'file-1'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = DriveUploadService(httpClient: client);
        await service.uploadFile(
          accessToken: 'fake-token',
          bytes: Uint8List.fromList([1]),
          fileName: 'a.jpg',
          mimeType: 'image/jpeg',
        );

        expect(createCalls, 0);
      },
    );

    test('throws DriveUploadException on a non-2xx response', () async {
      final client = MockClient(
        (request) async => http.Response('server error', 500),
      );
      final service = DriveUploadService(httpClient: client);

      expect(
        () => service.uploadFile(
          accessToken: 'fake-token',
          bytes: Uint8List.fromList([1]),
          fileName: 'a.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<DriveUploadException>()),
      );
    });
  });
}
