import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/albums/album_models.dart';
import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/albums/albums_controller.dart';
import 'package:memora_app/albums/collaborators_api.dart';
import 'package:memora_app/albums/sharing_api.dart';
import 'package:memora_app/albums/sharing_models.dart';
import 'package:memora_app/api/api_client.dart';

/// Extension of `test/albums_controller_test.dart` covering
/// spec07-compartir-nfc-qr.md's share-link + NFC/QR-tags state.
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

Map<String, dynamic> _tagJson({
  String id = 'tag-1',
  String albumId = 'album-1',
  String type = 'QR',
  String status = 'enabled',
}) => {
  'id': id,
  'albumId': albumId,
  'type': type,
  'token': 'tag-token-1',
  'status': status,
  'url': 'https://memora.app/n/tag-token-1',
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

/// Same tiny router as `albums_controller_test.dart`.
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

AlbumsController _controllerFor(ApiClient client) => AlbumsController(
  AlbumsApi(client),
  CollaboratorsApi(client),
  SharingApi(client),
);

void main() {
  group('AlbumsController.loadOrCreateShareLink', () {
    test('is a no-op without a currently open album', () async {
      final controller = _controllerFor(
        _routedClient({}, fallback: (_) {
          throw StateError('should not call the backend without an open album');
        }),
      );

      await controller.loadOrCreateShareLink();

      expect(controller.shareLink, isNull);
    });

    test('populates shareLink on success', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/share-link': (_) => _json({
          'token': 'share-tok-1',
          'url': 'https://memora.app/s/share-tok-1',
        }),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      await controller.loadOrCreateShareLink();

      expect(controller.shareLink?.url, 'https://memora.app/s/share-tok-1');
      expect(controller.shareLinkErrorMessage, isNull);
      expect(controller.isLoadingShareLink, isFalse);
    });

    test('a 404 sets the generic "not available" message', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/share-link': (_) =>
            _json({'code': 'NOT_FOUND', 'message': 'No encontrado'}, 404),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      await controller.loadOrCreateShareLink();

      expect(controller.shareLinkErrorMessage, 'Este álbum no está disponible.');
      expect(controller.shareLink, isNull);
    });
  });

  group('AlbumsController.revokeShareLink', () {
    test('clears shareLink on success', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/share-link': (_) => _json({
          'token': 'share-tok-1',
          'url': 'https://memora.app/s/share-tok-1',
        }),
        'DELETE /albums/album-1/share-link': (_) => http.Response('', 204),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);
      await controller.loadOrCreateShareLink();
      expect(controller.shareLink, isNotNull);

      final ok = await controller.revokeShareLink();

      expect(ok, isTrue);
      expect(controller.shareLink, isNull);
      expect(controller.mutationErrorMessage, isNull);
    });

    test('is a no-op without a currently open album', () async {
      final controller = _controllerFor(
        _routedClient({}, fallback: (_) {
          throw StateError('should not call the backend without an open album');
        }),
      );

      final ok = await controller.revokeShareLink();

      expect(ok, isFalse);
    });
  });

  group('AlbumsController.createNfcQrTag', () {
    test('on success, appends the created tag to nfcQrTags', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/nfc-qr-tags': (_) =>
            _json(_tagJson(id: 'tag-1', type: 'QR'), 201),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final created = await controller.createNfcQrTag(NfcQrTagType.qr);

      expect(created?.id, 'tag-1');
      expect(controller.nfcQrTags, hasLength(1));
      expect(controller.nfcQrTags.single.type, NfcQrTagType.qr);
      expect(controller.mutationErrorMessage, isNull);
    });

    test('creating a second tag appends rather than replacing the first', () async {
      var callCount = 0;
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/nfc-qr-tags': (_) {
          callCount++;
          return _json(
            _tagJson(
              id: 'tag-$callCount',
              type: callCount == 1 ? 'QR' : 'NFC',
            ),
            201,
          );
        },
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      await controller.createNfcQrTag(NfcQrTagType.qr);
      await controller.createNfcQrTag(NfcQrTagType.nfc);

      expect(controller.nfcQrTags.map((tag) => tag.id), ['tag-1', 'tag-2']);
    });

    test('is a no-op without a currently open album', () async {
      final controller = _controllerFor(
        _routedClient({}, fallback: (_) {
          throw StateError('should not call the backend without an open album');
        }),
      );

      final created = await controller.createNfcQrTag(NfcQrTagType.qr);

      expect(created, isNull);
      expect(controller.nfcQrTags, isEmpty);
    });
  });

  group('AlbumsController.disableNfcQrTag', () {
    test('on success, marks the matching tag as disabled in place', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/nfc-qr-tags': (_) =>
            _json(_tagJson(id: 'tag-1', type: 'QR'), 201),
        'PATCH /nfc-qr-tags/tag-1/disable': (_) => http.Response('', 204),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);
      await controller.createNfcQrTag(NfcQrTagType.qr);

      final ok = await controller.disableNfcQrTag('tag-1');

      expect(ok, isTrue);
      expect(controller.nfcQrTags.single.isDisabled, isTrue);
      expect(controller.mutationErrorMessage, isNull);
    });

    test('a 404 sets the generic "not available" message and leaves the tag untouched', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/nfc-qr-tags': (_) =>
            _json(_tagJson(id: 'tag-1', type: 'QR'), 201),
        'PATCH /nfc-qr-tags/tag-1/disable': (_) =>
            _json({'code': 'NOT_FOUND', 'message': 'No encontrado'}, 404),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);
      await controller.createNfcQrTag(NfcQrTagType.qr);

      final ok = await controller.disableNfcQrTag('tag-1');

      expect(ok, isFalse);
      expect(controller.mutationErrorMessage, 'Este álbum no está disponible.');
      expect(controller.nfcQrTags.single.isDisabled, isFalse);
    });
  });

  group('opening a different album resets sharing state', () {
    test('shareLink and nfcQrTags reset when navigating to a different album, not on refresh', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(id: 'album-1'), 'photos': <dynamic>[]}),
        'GET /albums/album-2': (_) =>
            _json({..._summaryJson(id: 'album-2'), 'photos': <dynamic>[]}),
        'POST /albums/album-1/share-link': (_) => _json({
          'token': 'share-tok-1',
          'url': 'https://memora.app/s/share-tok-1',
        }),
        'POST /albums/album-1/nfc-qr-tags': (_) =>
            _json(_tagJson(id: 'tag-1'), 201),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);
      await controller.loadOrCreateShareLink();
      await controller.createNfcQrTag(NfcQrTagType.qr);
      expect(controller.shareLink, isNotNull);
      expect(controller.nfcQrTags, hasLength(1));

      // Refreshing the SAME album must not wipe the in-memory sharing state.
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);
      expect(controller.shareLink, isNotNull);
      expect(controller.nfcQrTags, hasLength(1));

      // Opening a DIFFERENT album resets it.
      await controller.loadAlbumDetail('album-2', role: AlbumRole.owner);
      expect(controller.shareLink, isNull);
      expect(controller.nfcQrTags, isEmpty);
    });
  });
}
