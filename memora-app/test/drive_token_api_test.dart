import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/photos/drive_token_api.dart';

ApiClient _clientReturning(int statusCode, Map<String, dynamic> body) {
  return ApiClient(
    httpClient: MockClient(
      (request) async => http.Response(
        jsonEncode(body),
        statusCode,
        headers: {'content-type': 'application/json'},
      ),
    ),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

void main() {
  group('DriveTokenApi', () {
    test('returns a DriveToken with a computed expiry on success', () async {
      final api = DriveTokenApi(
        _clientReturning(200, {
          'driveAccessToken': 'ya29.fake-drive-token',
          'expiresIn': 3600,
        }),
      );

      final before = DateTime.now();
      final token = await api.getDriveToken();
      final after = DateTime.now();

      expect(token.accessToken, 'ya29.fake-drive-token');
      expect(token.isExpired, isFalse);
      // expiresAt should land ~3600s minus the safety margin from now.
      expect(
        token.expiresAt.isAfter(before.add(const Duration(seconds: 3500))),
        isTrue,
      );
      expect(
        token.expiresAt.isBefore(after.add(const Duration(seconds: 3600))),
        isTrue,
      );
    });

    test(
      'maps a 401 DRIVE_REAUTHORIZATION_REQUIRED to the typed exception',
      () async {
        final api = DriveTokenApi(
          _clientReturning(401, {
            'code': 'DRIVE_REAUTHORIZATION_REQUIRED',
            'message': 'Drive authorization expired',
          }),
        );

        expect(
          () => api.getDriveToken(),
          throwsA(isA<DriveReauthorizationRequiredException>()),
        );
      },
    );

    test('lets any other error propagate as ApiException', () async {
      final api = DriveTokenApi(
        _clientReturning(500, {'code': 'INTERNAL_ERROR', 'message': 'boom'}),
      );

      expect(() => api.getDriveToken(), throwsA(isA<Exception>()));
    });
  });
}
