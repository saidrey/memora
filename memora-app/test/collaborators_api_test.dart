import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/albums/album_models.dart';
import 'package:memora_app/albums/albums_api.dart';
import 'package:memora_app/albums/collaborator_models.dart';
import 'package:memora_app/albums/collaborators_api.dart';
import 'package:memora_app/api/api_client.dart';

ApiClient _clientReturning(
  int statusCode,
  Object body, {
  void Function(http.Request request)? onRequest,
}) {
  return ApiClient(
    httpClient: MockClient((request) async {
      onRequest?.call(request);
      // Mirrors a real 204/410-with-no-body: no encoded empty string.
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

Map<String, dynamic> _invitationCreatedJson() => {
  'id': 'inv-1',
  'token': 'tok-abc123',
  'url': 'https://memora.app/invite/tok-abc123',
  'status': 'pending',
  'expiresAt': '2026-02-01T00:00:00.000Z',
  'createdAt': '2026-01-25T00:00:00.000Z',
};

void main() {
  group('CollaboratorsApi.createInvitation', () {
    test('POSTs to the invitations endpoint and parses the response', () async {
      late String path;
      final api = CollaboratorsApi(
        _clientReturning(
          201,
          _invitationCreatedJson(),
          onRequest: (request) => path = request.url.path,
        ),
      );

      final invitation = await api.createInvitation('album-1');

      expect(path, endsWith('/albums/album-1/invitations'));
      expect(invitation.id, 'inv-1');
      expect(invitation.token, 'tok-abc123');
      expect(invitation.url, 'https://memora.app/invite/tok-abc123');
      expect(invitation.status, InvitationStatus.pending);
    });

    test('maps a 404 (not owner) to AlbumNotAvailableException', () async {
      final api = CollaboratorsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.createInvitation('album-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('CollaboratorsApi.listInvitations', () {
    test('decodes the bare array, keeping token/url only for pending ones', () async {
      final api = CollaboratorsApi(
        _clientReturning(200, [
          {
            'id': 'inv-1',
            'status': 'pending',
            'createdBy': 'user-1',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'expiresAt': '2026-02-01T00:00:00.000Z',
            'token': 'tok-1',
            'url': 'https://memora.app/invite/tok-1',
          },
          {
            'id': 'inv-2',
            'status': 'accepted',
            'createdBy': 'user-1',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'expiresAt': '2026-02-01T00:00:00.000Z',
            'acceptedByUserId': 'user-2',
          },
        ]),
      );

      final invitations = await api.listInvitations('album-1');

      expect(invitations, hasLength(2));
      expect(invitations[0].isPending, isTrue);
      expect(invitations[0].token, 'tok-1');
      expect(invitations[1].isPending, isFalse);
      expect(invitations[1].token, isNull);
      expect(invitations[1].url, isNull);
      expect(invitations[1].acceptedByUserId, 'user-2');
    });
  });

  group('CollaboratorsApi.revokeInvitation', () {
    test('sends a DELETE to the invitation endpoint', () async {
      late String method;
      late String path;
      final api = CollaboratorsApi(
        _clientReturning(
          204,
          '',
          onRequest: (request) {
            method = request.method;
            path = request.url.path;
          },
        ),
      );

      await api.revokeInvitation('album-1', 'inv-1');

      expect(method, 'DELETE');
      expect(path, endsWith('/albums/album-1/invitations/inv-1'));
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = CollaboratorsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.revokeInvitation('album-1', 'inv-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('CollaboratorsApi.acceptInvitation', () {
    test('accepts a bare token as-is', () async {
      late String path;
      final api = CollaboratorsApi(
        _clientReturning(204, '', onRequest: (request) => path = request.url.path),
      );

      await api.acceptInvitation('tok-abc123');

      expect(path, endsWith('/invitations/tok-abc123/accept'));
    });

    test('extracts the token from a full invitation URL', () async {
      late String path;
      final api = CollaboratorsApi(
        _clientReturning(204, '', onRequest: (request) => path = request.url.path),
      );

      await api.acceptInvitation('https://memora.app/invite/tok-abc123');

      expect(path, endsWith('/invitations/tok-abc123/accept'));
    });

    test('trims surrounding whitespace on a bare token', () async {
      late String path;
      final api = CollaboratorsApi(
        _clientReturning(204, '', onRequest: (request) => path = request.url.path),
      );

      await api.acceptInvitation('  tok-abc123  ');

      expect(path, endsWith('/invitations/tok-abc123/accept'));
    });

    test('maps a 410 to InvitationNotUsableException', () async {
      final api = CollaboratorsApi(
        _clientReturning(410, {
          'code': 'INVITATION_NOT_USABLE',
          'message': 'Esta invitación ya no se puede usar',
        }),
      );

      await expectLater(
        api.acceptInvitation('tok-dead'),
        throwsA(isA<InvitationNotUsableException>()),
      );
    });

    test('does not map an unrelated error to InvitationNotUsableException', () async {
      final api = CollaboratorsApi(
        _clientReturning(500, {'code': 'INTERNAL_ERROR', 'message': 'boom'}),
      );

      await expectLater(
        api.acceptInvitation('tok-1'),
        throwsA(isNot(isA<InvitationNotUsableException>())),
      );
    });
  });

  group('CollaboratorsApi.listCollaborators', () {
    test('decodes the bare array', () async {
      final api = CollaboratorsApi(
        _clientReturning(200, [
          {
            'userId': 'user-2',
            'role': 'collaborator',
            'joinedAt': '2026-01-10T00:00:00.000Z',
          },
        ]),
      );

      final collaborators = await api.listCollaborators('album-1');

      expect(collaborators, hasLength(1));
      expect(collaborators.first.userId, 'user-2');
      expect(collaborators.first.role, AlbumRole.collaborator);
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = CollaboratorsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.listCollaborators('album-1'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('CollaboratorsApi.removeCollaborator', () {
    test('sends a DELETE to the collaborator endpoint', () async {
      late String path;
      final api = CollaboratorsApi(
        _clientReturning(204, '', onRequest: (request) => path = request.url.path),
      );

      await api.removeCollaborator('album-1', 'user-2');

      expect(path, endsWith('/albums/album-1/collaborators/user-2'));
    });

    test('maps a 400 CANNOT_REMOVE_OWNER to a clear CollaboratorActionNotAllowedException', () async {
      final api = CollaboratorsApi(
        _clientReturning(400, {
          'code': 'CANNOT_REMOVE_OWNER',
          'message': 'El owner no puede quitarse a sí mismo del álbum',
        }),
      );

      await expectLater(
        api.removeCollaborator('album-1', 'owner-1'),
        throwsA(isA<CollaboratorActionNotAllowedException>()),
      );
    });

    test('maps a 404 to AlbumNotAvailableException', () async {
      final api = CollaboratorsApi(
        _clientReturning(404, {'code': 'NOT_FOUND', 'message': 'No encontrado'}),
      );

      await expectLater(
        api.removeCollaborator('album-1', 'user-2'),
        throwsA(isA<AlbumNotAvailableException>()),
      );
    });
  });

  group('CollaboratorsApi.leaveAlbum', () {
    test('sends a DELETE to the /collaborators/me endpoint', () async {
      late String path;
      final api = CollaboratorsApi(
        _clientReturning(204, '', onRequest: (request) => path = request.url.path),
      );

      await api.leaveAlbum('album-1');

      expect(path, endsWith('/albums/album-1/collaborators/me'));
    });

    test('maps a 400 CANNOT_LEAVE_AS_OWNER to a clear CollaboratorActionNotAllowedException', () async {
      final api = CollaboratorsApi(
        _clientReturning(400, {
          'code': 'CANNOT_LEAVE_AS_OWNER',
          'message': 'El owner no puede abandonar su propio álbum',
        }),
      );

      await expectLater(
        api.leaveAlbum('album-1'),
        throwsA(isA<CollaboratorActionNotAllowedException>()),
      );
    });
  });

  group('CollaboratorsApi.extractToken', () {
    test('returns the last path segment of an absolute URL', () {
      expect(
        CollaboratorsApi.extractToken('https://memora.app/invite/abc-123'),
        'abc-123',
      );
    });

    test('ignores a trailing slash', () {
      expect(
        CollaboratorsApi.extractToken('https://memora.app/invite/abc-123/'),
        'abc-123',
      );
    });

    test('returns a bare token as-is, trimmed', () {
      expect(CollaboratorsApi.extractToken('  abc-123  '), 'abc-123');
    });
  });
}
