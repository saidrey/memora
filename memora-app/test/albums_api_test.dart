import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/albums/album_models.dart';
import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/api/api_client.dart';

ApiClient _clientReturning(
  int statusCode,
  Object body, {
  void Function(http.Request request)? onRequest,
}) {
  return ApiClient(
    httpClient: MockClient((request) async {
      onRequest?.call(request);
      // Mirrors a real 204: no body at all, not an encoded empty string.
      final responseBody = body == '' ? '' : jsonEncode(body);
      return http.Response(
        responseBody,
        statusCode,
        headers: {'content-type': 'application/json'},
      );
    }),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

Map<String, dynamic> _summaryJson({
  String id = 'album-1',
  String name = 'Vacaciones',
  String visibility = 'PRIVATE',
  int photoCount = 0,
}) => {
  'id': id,
  'name': name,
  'visibility': visibility,
  'photoCount': photoCount,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

void main() {
  group('AlbumsApi.createAlbum', () {
    test('sends only name (no visibility) by default and parses the response', () async {
      late Map<String, dynamic> sentBody;
      final api = AlbumsApi(
        _clientReturning(
          201,
          _summaryJson(),
          onRequest: (request) =>
              sentBody = jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      final album = await api.createAlbum('Vacaciones');

      expect(sentBody, {'name': 'Vacaciones'});
      expect(album.id, 'album-1');
      expect(album.visibility, AlbumVisibility.private);
    });

    test('rejects an empty name before making a request', () async {
      final api = AlbumsApi(
        _clientReturning(201, _summaryJson(), onRequest: (_) {
          fail('should not call the backend with an invalid name');
        }),
      );

      await expectLater(
        api.createAlbum('   '),
        throwsA(isA<AlbumValidationException>()),
      );
    });

    test('rejects a name over 100 chars before making a request', () async {
      final api = AlbumsApi(
        _clientReturning(201, _summaryJson(), onRequest: (_) {
          fail('should not call the backend with an invalid name');
        }),
      );

      await expectLater(
        api.createAlbum('x' * 101),
        throwsA(isA<AlbumValidationException>()),
      );
    });

    test('maps a 400 from the backend to AlbumValidationException', () async {
      final api = AlbumsApi(
        _clientReturning(400, {
          'code': 'INVALID_REQUEST',
          'message': 'name no es válido',
        }),
      );

      await expectLater(
        api.createAlbum('Nombre válido'),
        throwsA(isA<AlbumValidationException>()),
      );
    });
  });

  group('AlbumsApi.listAlbums', () {
    test('decodes the bare array response into AlbumListItem, including role', () async {
      final api = AlbumsApi(
        _clientReturning(200, [
          {..._summaryJson(id: 'a1'), 'role': 'owner'},
          {..._summaryJson(id: 'a2'), 'role': 'collaborator'},
        ]),
      );

      final albums = await api.listAlbums();

      expect(albums, hasLength(2));
      expect(albums[0].id, 'a1');
      expect(albums[0].role, AlbumRole.owner);
      expect(albums[1].role, AlbumRole.collaborator);
    });
  });

  group('AlbumsApi.getAlbumDetail', () {
    test('decodes the album plus its photos', () async {
      final api = AlbumsApi(
        _clientReturning(200, {
          ..._summaryJson(),
          'photos': [
            {
              'id': 'p1',
              'storageRef': {'provider': 'google-drive', 'fileId': 'f1'},
              'availability': 'unavailable',
            },
          ],
        }),
      );

      final detail = await api.getAlbumDetail('album-1');

      expect(detail.photos, hasLength(1));
      expect(detail.photos.first.id, 'p1');
    });

    test('maps a 404 (ajeno o inexistente) to a generic AlbumNotAvailableException', () async {
      final api = AlbumsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.getAlbumDetail('someone-elses-album'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('AlbumsApi.updateAlbum', () {
    test('rejects a call with neither name nor visibility before requesting', () async {
      final api = AlbumsApi(
        _clientReturning(200, _summaryJson(), onRequest: (_) {
          fail('should not call the backend without any field to update');
        }),
      );

      await expectLater(
        api.updateAlbum('album-1'),
        throwsA(isA<AlbumValidationException>()),
      );
    });

    test('sends only the provided fields', () async {
      late Map<String, dynamic> sentBody;
      final api = AlbumsApi(
        _clientReturning(
          200,
          _summaryJson(visibility: 'PUBLIC'),
          onRequest: (request) =>
              sentBody = jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      await api.updateAlbum('album-1', visibility: AlbumVisibility.public);

      expect(sentBody, {'visibility': 'PUBLIC'});
    });

    test('maps a 404 (not owner) to AlbumNotAvailableException', () async {
      final api = AlbumsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.updateAlbum('album-1', name: 'Nuevo'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });

    test('maps a 400 to AlbumValidationException', () async {
      final api = AlbumsApi(
        _clientReturning(400, {
          'code': 'INVALID_REQUEST',
          'message': 'visibility no es válido',
        }),
      );

      await expectLater(
        api.updateAlbum('album-1', name: 'Nuevo'),
        throwsA(isA<AlbumValidationException>()),
      );
    });
  });

  group('AlbumsApi.deleteAlbum', () {
    test('sends a DELETE and completes on 204', () async {
      late String method;
      final api = AlbumsApi(
        _clientReturning(
          204,
          '',
          onRequest: (request) => method = request.method,
        ),
      );

      await api.deleteAlbum('album-1');

      expect(method, 'DELETE');
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = AlbumsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.deleteAlbum('album-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('AlbumsApi photo association', () {
    test('addPhotoToAlbum posts photoId', () async {
      late Map<String, dynamic> sentBody;
      final api = AlbumsApi(
        _clientReturning(
          204,
          '',
          onRequest: (request) =>
              sentBody = jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      await api.addPhotoToAlbum('album-1', 'photo-1');

      expect(sentBody, {'photoId': 'photo-1'});
    });

    test('removePhotoFromAlbum sends a DELETE to the relation endpoint', () async {
      late String method;
      final api = AlbumsApi(
        _clientReturning(
          204,
          '',
          onRequest: (request) => method = request.method,
        ),
      );

      await api.removePhotoFromAlbum('album-1', 'photo-1');

      expect(method, 'DELETE');
    });

    test('maps a 404 removing a photo to AlbumNotAvailableException', () async {
      final api = AlbumsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.removePhotoFromAlbum('album-1', 'photo-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });
}
