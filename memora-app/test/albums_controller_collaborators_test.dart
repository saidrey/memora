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

/// Extension of `test/albums_controller_test.dart` covering
/// spec05-ui-colaboradores.md's collaborators/invitations state — kept in
/// its own file rather than growing that one further.
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
  group('AlbumsController.loadCollaboratorsAndInvitations', () {
    test('is a no-op without a currently open album', () async {
      final controller = _controllerFor(
        _routedClient({}, fallback: (_) {
          throw StateError('should not call the backend without an open album');
        }),
      );

      await controller.loadCollaboratorsAndInvitations();

      expect(controller.collaborators, isEmpty);
      expect(controller.invitations, isEmpty);
    });

    test('populates both lists for the currently open album', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'GET /albums/album-1/collaborators': (_) => _json([
          {
            'userId': 'user-2',
            'role': 'collaborator',
            'joinedAt': '2026-01-10T00:00:00.000Z',
          },
        ]),
        'GET /albums/album-1/invitations': (_) => _json([
          {
            'id': 'inv-1',
            'status': 'pending',
            'createdBy': 'owner-1',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'expiresAt': '2026-02-01T00:00:00.000Z',
            'token': 'tok-1',
            'url': 'https://memora.app/invite/tok-1',
          },
        ]),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      await controller.loadCollaboratorsAndInvitations();

      expect(controller.collaborators, hasLength(1));
      expect(controller.collaborators.single.userId, 'user-2');
      expect(controller.invitations, hasLength(1));
      expect(controller.invitations.single.isPending, isTrue);
      expect(controller.collaboratorsErrorMessage, isNull);
    });

    test('a 404 sets the generic "not available" message', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'GET /albums/album-1/collaborators': (_) =>
            _json({'code': 'NOT_FOUND', 'message': 'No encontrado'}, 404),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      await controller.loadCollaboratorsAndInvitations();

      expect(controller.collaboratorsErrorMessage, 'Este álbum no está disponible.');
    });
  });

  group('AlbumsController.createInvitation', () {
    test('creates the invitation and refreshes both lists', () async {
      var invitationsListCalls = 0;
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'POST /albums/album-1/invitations': (_) => _json({
          'id': 'inv-1',
          'token': 'tok-1',
          'url': 'https://memora.app/invite/tok-1',
          'status': 'pending',
          'expiresAt': '2026-02-01T00:00:00.000Z',
          'createdAt': '2026-01-01T00:00:00.000Z',
        }, 201),
        'GET /albums/album-1/collaborators': (_) => _json(<dynamic>[]),
        'GET /albums/album-1/invitations': (_) {
          invitationsListCalls++;
          return _json(<dynamic>[]);
        },
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final created = await controller.createInvitation();

      expect(created?.url, 'https://memora.app/invite/tok-1');
      expect(invitationsListCalls, 1);
      expect(controller.mutationErrorMessage, isNull);
      expect(controller.isMutating, isFalse);
    });

    test('is a no-op without a currently open album', () async {
      final controller = _controllerFor(
        _routedClient({}, fallback: (_) {
          throw StateError('should not call the backend without an open album');
        }),
      );

      final created = await controller.createInvitation();

      expect(created, isNull);
    });
  });

  group('AlbumsController.revokeInvitation', () {
    test('revokes and refreshes the invitations list', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'DELETE /albums/album-1/invitations/inv-1': (_) =>
            http.Response('', 204),
        'GET /albums/album-1/collaborators': (_) => _json(<dynamic>[]),
        'GET /albums/album-1/invitations': (_) => _json(<dynamic>[]),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final ok = await controller.revokeInvitation('inv-1');

      expect(ok, isTrue);
      expect(controller.mutationErrorMessage, isNull);
    });
  });

  group('AlbumsController.removeCollaborator', () {
    test('removes and refreshes the collaborators list', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'DELETE /albums/album-1/collaborators/user-2': (_) =>
            http.Response('', 204),
        'GET /albums/album-1/collaborators': (_) => _json(<dynamic>[]),
        'GET /albums/album-1/invitations': (_) => _json(<dynamic>[]),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final ok = await controller.removeCollaborator('user-2');

      expect(ok, isTrue);
      expect(controller.mutationErrorMessage, isNull);
    });

    test('a 400 CANNOT_REMOVE_OWNER sets a clear message, not the raw code', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'DELETE /albums/album-1/collaborators/owner-1': (_) => _json({
          'code': 'CANNOT_REMOVE_OWNER',
          'message': 'El owner no puede quitarse a sí mismo del álbum',
        }, 400),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final ok = await controller.removeCollaborator('owner-1');

      expect(ok, isFalse);
      expect(controller.mutationErrorMessage, 'No puedes quitar al owner del álbum.');
    });
  });

  group('AlbumsController.leaveCurrentAlbum', () {
    test('on success, clears the open detail and refreshes the albums list', () async {
      var albumsListCalls = 0;
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'DELETE /albums/album-1/collaborators/me': (_) =>
            http.Response('', 204),
        'GET /albums': (_) {
          albumsListCalls++;
          return _json(<dynamic>[]);
        },
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.collaborator);

      final ok = await controller.leaveCurrentAlbum();

      expect(ok, isTrue);
      expect(controller.albumDetail, isNull);
      expect(controller.currentAlbumId, isNull);
      expect(albumsListCalls, 1);
    });

    test('a 400 CANNOT_LEAVE_AS_OWNER sets a clear message', () async {
      final client = _routedClient({
        'GET /albums/album-1': (_) =>
            _json({..._summaryJson(), 'photos': <dynamic>[]}),
        'DELETE /albums/album-1/collaborators/me': (_) => _json({
          'code': 'CANNOT_LEAVE_AS_OWNER',
          'message': 'El owner no puede abandonar su propio álbum',
        }, 400),
      });
      final controller = _controllerFor(client);
      await controller.loadAlbumDetail('album-1', role: AlbumRole.owner);

      final ok = await controller.leaveCurrentAlbum();

      expect(ok, isFalse);
      expect(
        controller.mutationErrorMessage,
        'El owner no puede abandonar su propio álbum.',
      );
      // Never cleared on failure — the album is still open.
      expect(controller.currentAlbumId, 'album-1');
    });
  });

  group('AlbumsController.acceptInvitation', () {
    test('on success, refreshes the albums list — independent of currentAlbumId', () async {
      var albumsListCalls = 0;
      late String acceptedPath;
      final client = _routedClient({
        'POST /invitations/tok-1/accept': (request) {
          acceptedPath = request.url.path;
          return http.Response('', 204);
        },
        'GET /albums': (_) {
          albumsListCalls++;
          return _json([
            {..._summaryJson(id: 'joined-album'), 'role': 'collaborator'},
          ]);
        },
      });
      final controller = _controllerFor(client);

      final ok = await controller.acceptInvitation('tok-1');

      expect(ok, isTrue);
      expect(acceptedPath, endsWith('/invitations/tok-1/accept'));
      expect(albumsListCalls, 1);
      expect(controller.albums.single.id, 'joined-album');
      expect(controller.isAcceptingInvitation, isFalse);
      expect(controller.acceptInvitationErrorMessage, isNull);
    });

    test('a 410 (invalid/used/expired) sets a clear message, never the raw code', () async {
      final client = _routedClient({
        'POST /invitations/tok-dead/accept': (_) => _json({
          'code': 'INVITATION_NOT_USABLE',
          'message': 'Esta invitación ya no se puede usar',
        }, 410),
      });
      final controller = _controllerFor(client);

      final ok = await controller.acceptInvitation('tok-dead');

      expect(ok, isFalse);
      expect(
        controller.acceptInvitationErrorMessage,
        'Esta invitación no es válida, ya fue usada o expiró.',
      );
    });

    test('accepts a full URL by extracting its token', () async {
      late String acceptedPath;
      final client = _routedClient({
        'POST /invitations/tok-1/accept': (request) {
          acceptedPath = request.url.path;
          return http.Response('', 204);
        },
        'GET /albums': (_) => _json(<dynamic>[]),
      });
      final controller = _controllerFor(client);

      final ok = await controller.acceptInvitation(
        'https://memora.app/invite/tok-1',
      );

      expect(ok, isTrue);
      expect(acceptedPath, endsWith('/invitations/tok-1/accept'));
    });
  });
}
