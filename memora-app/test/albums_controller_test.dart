import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/albums/album_models.dart';
import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/albums/albums_controller.dart';
import 'package:memora_app/albums/collaborators_api.dart';
import 'package:memora_app/albums/sharing_api.dart';
import 'package:memora_app/api/api_client.dart';

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

/// A tiny router so each test only has to describe the responses it cares
/// about — same spirit as the `_backendClient` helper in
/// photo_upload_controller_test.dart.
ApiClient _routedClient(
  Map<String, http.Response Function(http.Request)> routes, {
  http.Response Function(http.Request)? fallback,
}) {
  return ApiClient(
    httpClient: MockClient((request) async {
      for (final entry in routes.entries) {
        if (request.method == entry.key.split(' ')[0] &&
            request.url.path.endsWith(entry.key.split(' ')[1])) {
          return entry.value(request);
        }
      }
      if (fallback != null) return fallback(request);
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    }),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('AlbumsController.loadAlbums', () {
    test('populates albums on success', () async {
      final client = _routedClient({
        'GET /albums': (_) => _json([
          {..._summaryJson(id: 'a1'), 'role': 'owner'},
        ]),
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );

      await controller.loadAlbums();

      expect(controller.isLoadingList, isFalse);
      expect(controller.albums, hasLength(1));
      expect(controller.listErrorMessage, isNull);
    });

    test('sets a generic error message on failure', () async {
      final client = _routedClient({
        'GET /albums': (_) => _json({'code': 'INTERNAL_ERROR'}, 500),
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );

      await controller.loadAlbums();

      expect(controller.albums, isEmpty);
      expect(controller.listErrorMessage, isNotNull);
    });

    test('a 401 (expired session JWT) sets a distinct message', () async {
      final client = _routedClient({
        'GET /albums': (_) =>
            _json({'code': 'UNAUTHORIZED', 'message': 'Unauthorized'}, 401),
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );

      await controller.loadAlbums();

      expect(
        controller.listErrorMessage,
        'Tu sesión expiró. Vuelve a iniciar sesión.',
      );
    });
  });

  group('AlbumsController.createAlbum', () {
    test('on success, refreshes the list and returns the created album', () async {
      var listCalls = 0;
      final client = _routedClient({
        'POST /albums': (_) => _json(_summaryJson(id: 'new-album'), 201),
        'GET /albums': (_) {
          listCalls++;
          return _json([
            {..._summaryJson(id: 'new-album'), 'role': 'owner'},
          ]);
        },
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );

      final created = await controller.createAlbum('Vacaciones');

      expect(created?.id, 'new-album');
      expect(listCalls, 1);
      expect(controller.albums.single.id, 'new-album');
      expect(controller.mutationErrorMessage, isNull);
      expect(controller.isMutating, isFalse);
    });

    test('a validation failure never touches the network and sets a clear message', () async {
      final client = _routedClient({}, fallback: (_) {
        throw StateError('should not call the backend with an invalid name');
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );

      final created = await controller.createAlbum('');

      expect(created, isNull);
      expect(controller.mutationErrorMessage, isNotNull);
    });
  });

  group('AlbumsController.loadAlbumDetail', () {
    test('stores the role passed in (not part of the AlbumDetail response)', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) => _json({
          ..._summaryJson(),
          'photos': <dynamic>[],
        }),
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );

      await controller.loadAlbumDetail('album-1', role: AlbumRole.collaborator);

      expect(controller.albumDetail, isNotNull);
      expect(controller.currentAlbumRole, AlbumRole.collaborator);
      expect(controller.isCurrentAlbumOwner, isFalse);
    });

    test('a 404 becomes a generic "not available" message, not the backend detail', () async {
      final client = _routedClient({
        'GET /albums/someone-elses': (_) =>
            _json({'code': 'NOT_FOUND', 'message': 'No encontrado'}, 404),
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );

      await controller.loadAlbumDetail('someone-elses', role: AlbumRole.owner);

      expect(controller.albumDetail, isNull);
      expect(controller.detailErrorMessage, 'Este álbum no está disponible.');
    });
  });

  group('AlbumsController owner-only mutations', () {
    test('renameCurrentAlbum succeeds and reloads the detail', () async {
      var patchCalls = 0;
      final client = _routedClient({
        'GET /albums/album-1': (_) => _json({
          ..._summaryJson(name: patchCalls == 0 ? 'Antes' : 'Después'),
          'photos': <dynamic>[],
        }),
        'PATCH /albums/album-1': (_) {
          patchCalls++;
          return _json(_summaryJson(name: 'Después'));
        },
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final ok = await controller.renameCurrentAlbum('Después');

      expect(ok, isTrue);
      expect(patchCalls, 1);
      expect(controller.albumDetail?.name, 'Después');
    });

    test('deleteCurrentAlbum succeeds and clears the detail state', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) => _json({
          ..._summaryJson(),
          'photos': <dynamic>[],
        }),
        'DELETE /albums/album-1': (_) => http.Response('', 204),
        'GET /albums': (_) => _json(<dynamic>[]),
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final ok = await controller.deleteCurrentAlbum();

      expect(ok, isTrue);
      expect(controller.albumDetail, isNull);
      expect(controller.currentAlbumId, isNull);
    });

    test('removePhotoFromCurrentAlbum calls the relation endpoint and reloads', () async {
      var detailCalls = 0;
      final client = _routedClient({
        'GET /albums/album-1': (_) {
          detailCalls++;
          return _json({..._summaryJson(), 'photos': <dynamic>[]});
        },
        'DELETE /albums/album-1/photos/photo-1': (_) => http.Response('', 204),
      });
      final controller = AlbumsController(
        AlbumsApi(client),
        CollaboratorsApi(client),
        SharingApi(client),
      );
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);
      final callsAfterLoad = detailCalls;

      await controller.removePhotoFromCurrentAlbum('photo-1');

      expect(detailCalls, callsAfterLoad + 1);
      expect(controller.mutationErrorMessage, isNull);
    });
  });
}
