import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/albums/sharing_api.dart';
import 'package:memora_app/albums/sharing_models.dart';
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

void main() {
  group('SharingApi.createOrGetShareLink', () {
    test('POSTs to /albums/:albumId/share-link and parses token+url', () async {
      late Uri requestedUri;
      late String method;
      final api = SharingApi(
        _clientReturning(
          201,
          {'token': 'share-tok-1', 'url': 'https://memora.app/s/share-tok-1'},
          onRequest: (request) {
            requestedUri = request.url;
            method = request.method;
          },
        ),
      );

      final link = await api.createOrGetShareLink('album-1');

      expect(method, 'POST');
      expect(requestedUri.path, endsWith('/albums/album-1/share-link'));
      expect(link.token, 'share-tok-1');
      expect(link.url, 'https://memora.app/s/share-tok-1');
    });

    test('a second call (idempotent) still parses the same shape', () async {
      final api = SharingApi(
        _clientReturning(200, {
          'token': 'share-tok-1',
          'url': 'https://memora.app/s/share-tok-1',
        }),
      );

      final link = await api.createOrGetShareLink('album-1');

      expect(link.token, 'share-tok-1');
    });

    test('maps a 404 (not owner or album doesn\'t exist) to AlbumNotAvailableException', () async {
      final api = SharingApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.createOrGetShareLink('someone-elses'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('SharingApi.revokeShareLink', () {
    test('DELETEs /albums/:albumId/share-link', () async {
      late Uri requestedUri;
      late String method;
      final api = SharingApi(
        _clientReturning(
          204,
          '',
          onRequest: (request) {
            requestedUri = request.url;
            method = request.method;
          },
        ),
      );

      await api.revokeShareLink('album-1');

      expect(method, 'DELETE');
      expect(requestedUri.path, endsWith('/albums/album-1/share-link'));
    });

    test('succeeds even when there was nothing to revoke (idempotent 204)', () async {
      final api = SharingApi(_clientReturning(204, ''));

      await expectLater(api.revokeShareLink('album-1'), completes);
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = SharingApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.revokeShareLink('album-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('SharingApi.createNfcQrTag', () {
    test('POSTs to /albums/:albumId/nfc-qr-tags with the given type', () async {
      late Uri requestedUri;
      late Map<String, dynamic> sentBody;
      final api = SharingApi(
        _clientReturning(
          201,
          _tagJson(type: 'QR'),
          onRequest: (request) {
            requestedUri = request.url;
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          },
        ),
      );

      final tag = await api.createNfcQrTag('album-1', NfcQrTagType.qr);

      expect(requestedUri.path, endsWith('/albums/album-1/nfc-qr-tags'));
      expect(sentBody, {'type': 'QR'});
      expect(tag.id, 'tag-1');
      expect(tag.type, NfcQrTagType.qr);
      expect(tag.status, NfcQrTagStatus.enabled);
      expect(tag.isDisabled, isFalse);
    });

    test('sends NFC when asked for an NFC tag', () async {
      late Map<String, dynamic> sentBody;
      final api = SharingApi(
        _clientReturning(
          201,
          _tagJson(type: 'NFC'),
          onRequest: (request) =>
              sentBody = jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );

      final tag = await api.createNfcQrTag('album-1', NfcQrTagType.nfc);

      expect(sentBody, {'type': 'NFC'});
      expect(tag.type, NfcQrTagType.nfc);
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = SharingApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.createNfcQrTag('album-1', NfcQrTagType.qr),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('SharingApi.getNfcQrTag', () {
    test('GETs /nfc-qr-tags/:tagId — NOT nested under /albums/:albumId', () async {
      late Uri requestedUri;
      final api = SharingApi(
        _clientReturning(
          200,
          _tagJson(),
          onRequest: (request) => requestedUri = request.url,
        ),
      );

      final tag = await api.getNfcQrTag('tag-1');

      expect(requestedUri.path, endsWith('/nfc-qr-tags/tag-1'));
      expect(requestedUri.path, isNot(contains('/albums/')));
      expect(tag.id, 'tag-1');
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = SharingApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.getNfcQrTag('tag-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('SharingApi.disableNfcQrTag', () {
    test('PATCHes /nfc-qr-tags/:tagId/disable — NOT nested under /albums/:albumId', () async {
      late Uri requestedUri;
      late String method;
      final api = SharingApi(
        _clientReturning(
          204,
          '',
          onRequest: (request) {
            requestedUri = request.url;
            method = request.method;
          },
        ),
      );

      await api.disableNfcQrTag('tag-1');

      expect(method, 'PATCH');
      expect(requestedUri.path, endsWith('/nfc-qr-tags/tag-1/disable'));
      expect(requestedUri.path, isNot(contains('/albums/')));
    });

    test('succeeds even when already disabled (idempotent 204)', () async {
      final api = SharingApi(_clientReturning(204, ''));

      await expectLater(api.disableNfcQrTag('tag-1'), completes);
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = SharingApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.disableNfcQrTag('tag-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });
}
