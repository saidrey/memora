import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/albums/albums_controller.dart';
import 'package:memora_app/albums/collaborators_api.dart';
import 'package:memora_app/albums/sharing_api.dart';
import 'package:memora_app/api/api_client.dart';

/// Extension of `test/albums_controller_test.dart` covering the album-list
/// cover-photo mechanism (ajuste post-feedback "cards con fotos reales tipo
/// montaje", sin spec de Kiro — see CLAUDE.md's "N+1 aceptado" note): after
/// `loadAlbums()`, the controller lazily/non-blockingly fetches each
/// photo-having album's `AlbumDetail` just to cache its first few photos,
/// exposed via `coverPhotosFor(albumId)`.
Map<String, dynamic> _summaryJson({
  required String id,
  String name = 'Vacaciones',
  String visibility = 'PRIVATE',
  required int photoCount,
}) => {
  'id': id,
  'name': name,
  'visibility': visibility,
  'photoCount': photoCount,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> _photoJson(String id, String fileId) => {
  'id': id,
  'storageRef': {'provider': 'google-drive', 'fileId': fileId},
};

/// Same tiny router as `albums_controller_test.dart` — routes are matched by
/// method + path suffix, so per-album-id detail routes (`GET /albums/a1`)
/// coexist fine with the plain list route (`GET /albums`): a detail path
/// never ends with the bare `/albums` suffix.
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

AlbumsController _controller(ApiClient client) => AlbumsController(
  AlbumsApi(client),
  CollaboratorsApi(client),
  SharingApi(client),
);

/// Covers load in a fire-and-forget `Future` kicked off from inside
/// `loadAlbums()` — give the event loop a couple of turns so the `MockClient`
/// responses (themselves resolved via `async`, not a real timer) have a
/// chance to complete before asserting on `coverPhotosFor`.
Future<void> _settleCovers() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('AlbumsController cover photos', () {
    test(
      'loadAlbums fetches a cover only for albums with photoCount > 0',
      () async {
        var detailCalls = 0;
        final client = _routedClient({
          'GET /albums': (_) => _json([
            {..._summaryJson(id: 'a1', photoCount: 2), 'role': 'owner'},
            {..._summaryJson(id: 'a2', photoCount: 0), 'role': 'owner'},
          ]),
          'GET /albums/a1': (_) {
            detailCalls++;
            return _json({
              ..._summaryJson(id: 'a1', photoCount: 2),
              'photos': [
                _photoJson('p1', 'file-1'),
                _photoJson('p2', 'file-2'),
              ],
            });
          },
        });
        final controller = _controller(client);

        await controller.loadAlbums();
        await _settleCovers();

        expect(detailCalls, 1);
        expect(controller.coverPhotosFor('a1'), isNotNull);
        expect(
          controller.coverPhotosFor('a1')!.map((p) => p.id),
          ['p1', 'p2'],
        );
        // Never fetched: photoCount == 0.
        expect(controller.coverPhotosFor('a2'), isNull);
      },
    );

    test('caps a cover at the first 3 photos of the album', () async {
      final client = _routedClient({
        'GET /albums': (_) => _json([
          {..._summaryJson(id: 'a1', photoCount: 5), 'role': 'owner'},
        ]),
        'GET /albums/a1': (_) => _json({
          ..._summaryJson(id: 'a1', photoCount: 5),
          'photos': [
            _photoJson('p1', 'f1'),
            _photoJson('p2', 'f2'),
            _photoJson('p3', 'f3'),
            _photoJson('p4', 'f4'),
            _photoJson('p5', 'f5'),
          ],
        }),
      });
      final controller = _controller(client);

      await controller.loadAlbums();
      await _settleCovers();

      expect(controller.coverPhotosFor('a1'), hasLength(3));
    });

    test(
      'a failed cover fetch leaves coverPhotosFor null and never touches listErrorMessage',
      () async {
        final client = _routedClient({
          'GET /albums': (_) => _json([
            {..._summaryJson(id: 'a1', photoCount: 3), 'role': 'owner'},
          ]),
          'GET /albums/a1': (_) => _json({'code': 'INTERNAL_ERROR'}, 500),
        });
        final controller = _controller(client);

        await controller.loadAlbums();
        await _settleCovers();

        expect(controller.coverPhotosFor('a1'), isNull);
        expect(controller.listErrorMessage, isNull);
        expect(controller.albums, hasLength(1));
      },
    );

    test(
      'a second loadAlbums call does not refetch an already-cached cover',
      () async {
        var detailCalls = 0;
        final client = _routedClient({
          'GET /albums': (_) => _json([
            {..._summaryJson(id: 'a1', photoCount: 1), 'role': 'owner'},
          ]),
          'GET /albums/a1': (_) {
            detailCalls++;
            return _json({
              ..._summaryJson(id: 'a1', photoCount: 1),
              'photos': [_photoJson('p1', 'file-1')],
            });
          },
        });
        final controller = _controller(client);

        await controller.loadAlbums();
        await _settleCovers();
        await controller.loadAlbums();
        await _settleCovers();

        expect(detailCalls, 1);
      },
    );
  });
}
