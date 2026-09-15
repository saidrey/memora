import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/photos/photos_api.dart';

void main() {
  group('PhotosApi.registerPhoto', () {
    test(
      'sends storageRef.fileId (never driveFileId) and omits provider/null fields',
      () async {
        late Map<String, dynamic> sentBody;

        final client = ApiClient(
          httpClient: MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'id': 'photo-1',
                'storageRef': {
                  'provider': 'google-drive',
                  'fileId': 'drive-file-1',
                },
                'width': 1024,
                'height': 768,
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
          baseUrl: 'http://localhost:3000/api/v1',
        );
        final api = PhotosApi(client);

        final photo = await api.registerPhoto(
          fileId: 'drive-file-1',
          width: 1024,
          height: 768,
          mimeType: 'image/jpeg',
          sizeBytes: 12345,
        );

        expect(sentBody['storageRef'], {'fileId': 'drive-file-1'});
        expect(sentBody.containsKey('driveFileId'), isFalse);
        expect(sentBody.containsKey('provider'), isFalse);
        expect(sentBody.containsKey('albumId'), isFalse);
        expect(sentBody.containsKey('capturedAt'), isFalse);

        expect(photo.id, 'photo-1');
        expect(photo.storageRef.fileId, 'drive-file-1');
        expect(photo.storageRef.provider, 'google-drive');
        expect(photo.width, 1024);
        expect(photo.height, 768);
      },
    );

    test('includes albumId only when provided', () async {
      late Map<String, dynamic> sentBody;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'photo-2',
              'storageRef': {'provider': 'google-drive', 'fileId': 'f-2'},
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      );
      final api = PhotosApi(client);

      await api.registerPhoto(fileId: 'f-2', albumId: 'album-1');

      expect(sentBody['albumId'], 'album-1');
    });
  });
}
