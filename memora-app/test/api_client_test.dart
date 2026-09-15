import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/api/api_exception.dart';

void main() {
  group('ApiClient.patchJson', () {
    test('sends a PATCH with the given body and returns the decoded response', () async {
      late String method;
      late Map<String, dynamic> sentBody;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          method = request.method;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'id': 'a1', 'name': 'Nuevo nombre'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      );

      final result = await client.patchJson('/albums/a1', {
        'name': 'Nuevo nombre',
      });

      expect(method, 'PATCH');
      expect(sentBody, {'name': 'Nuevo nombre'});
      expect(result['id'], 'a1');
    });

    test('maps a non-2xx response to ApiException', () async {
      final client = ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 'INVALID_REQUEST',
              'message': 'Debes indicar name y/o visibility',
              'requestId': 'req-1',
            }),
            400,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrl: 'http://localhost:3000/api/v1',
      );

      await expectLater(
        client.patchJson('/albums/a1', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'INVALID_REQUEST')
              .having((e) => e.requestId, 'requestId', 'req-1'),
        ),
      );
    });
  });

  group('ApiClient.delete', () {
    test('sends a DELETE and tolerates a 204 with an empty body', () async {
      late String method;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          method = request.method;
          return http.Response('', 204);
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      );

      await client.delete('/albums/a1');

      expect(method, 'DELETE');
    });

    test('maps a 404 response to ApiException', () async {
      final client = ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'code': 'NOT_FOUND', 'message': 'No encontrado'}),
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrl: 'http://localhost:3000/api/v1',
      );

      await expectLater(
        client.delete('/albums/does-not-exist'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('ApiClient.getJsonList', () {
    test('decodes a bare JSON array response', () async {
      final client = ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode([
              {'id': 'a1'},
              {'id': 'a2'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrl: 'http://localhost:3000/api/v1',
      );

      final result = await client.getJsonList('/albums');

      expect(result, hasLength(2));
      expect((result[0] as Map)['id'], 'a1');
    });

    test('maps a non-2xx response to ApiException', () async {
      final client = ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'code': 'UNAUTHORIZED', 'message': 'No autorizado'}),
            401,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrl: 'http://localhost:3000/api/v1',
      );

      await expectLater(
        client.getJsonList('/albums'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('ApiClient automatic session refresh (spec06-sesion-y-reauth-drive)', () {
    test('a generic 401 triggers one refresh, then retries the original '
        'request and returns its result', () async {
      var albumsCalls = 0;
      var refreshCalls = 0;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshCalls++;
            expect(
              jsonDecode(request.body),
              {'sessionRefreshToken': 'old-refresh'},
            );
            return http.Response(
              jsonEncode({
                'sessionAccessToken': 'new-access',
                'sessionRefreshToken': 'new-refresh',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          albumsCalls++;
          if (albumsCalls == 1) {
            expect(request.headers['Authorization'], 'Bearer old-access');
            return http.Response(
              jsonEncode({'code': 'UNAUTHORIZED', 'message': 'Unauthorized'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response(
            jsonEncode([]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      )
        ..setAccessToken('old-access')
        ..setRefreshToken('old-refresh');

      String? refreshedAccess;
      String? refreshedRefresh;
      client.onSessionRefreshed = (access, refresh) async {
        refreshedAccess = access;
        refreshedRefresh = refresh;
      };
      var invalidated = false;
      client.onSessionInvalidated = () async => invalidated = true;

      final result = await client.getJsonList('/albums');

      expect(result, isEmpty);
      expect(albumsCalls, 2);
      expect(refreshCalls, 1);
      expect(refreshedAccess, 'new-access');
      expect(refreshedRefresh, 'new-refresh');
      expect(invalidated, isFalse);
    });

    test('when the refresh itself also fails, the session is invalidated and '
        'the ORIGINAL 401 is propagated', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return http.Response(
              jsonEncode({
                'code': 'SESSION_REFRESH_INVALID',
                'message': 'invalid refresh token',
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'code': 'UNAUTHORIZED', 'message': 'Unauthorized'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      )
        ..setAccessToken('old-access')
        ..setRefreshToken('old-refresh');

      var invalidated = false;
      client.onSessionInvalidated = () async => invalidated = true;
      var refreshedCalled = false;
      client.onSessionRefreshed = (_, _) async => refreshedCalled = true;

      await expectLater(
        client.getJsonList('/albums'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );
      expect(invalidated, isTrue);
      expect(refreshedCalled, isFalse);
    });

    test('a 401 with DRIVE_REAUTHORIZATION_REQUIRED never triggers a refresh',
        () async {
      var refreshCalls = 0;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshCalls++;
          }
          return http.Response(
            jsonEncode({
              'code': 'DRIVE_REAUTHORIZATION_REQUIRED',
              'message': 'Drive authorization expired',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      )
        ..setAccessToken('old-access')
        ..setRefreshToken('old-refresh');

      var invalidated = false;
      client.onSessionInvalidated = () async => invalidated = true;

      await expectLater(
        client.postJson('/auth/drive-token'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'DRIVE_REAUTHORIZATION_REQUIRED',
          ),
        ),
      );
      expect(refreshCalls, 0);
      expect(invalidated, isFalse);
    });

    test('concurrent 401s coalesce into a single POST /auth/refresh call',
        () async {
      var refreshCalls = 0;
      var pendingRequests = 0;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshCalls++;
            // Give both concurrent callers a chance to reach the refresh
            // logic before this resolves, so a bug that didn't coalesce
            // would show up as refreshCalls > 1.
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response(
              jsonEncode({
                'sessionAccessToken': 'new-access',
                'sessionRefreshToken': 'new-refresh',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          pendingRequests++;
          if (request.headers['Authorization'] == 'Bearer old-access') {
            return http.Response(
              jsonEncode({'code': 'UNAUTHORIZED', 'message': 'Unauthorized'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode([]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'http://localhost:3000/api/v1',
      )
        ..setAccessToken('old-access')
        ..setRefreshToken('old-refresh');

      final results = await Future.wait([
        client.getJsonList('/albums'),
        client.getJsonList('/albums'),
      ]);

      expect(results, hasLength(2));
      expect(refreshCalls, 1);
      expect(pendingRequests, 4); // 2 initial 401s + 2 successful retries.
    });
  });
}
