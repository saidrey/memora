import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/api/health_api.dart';
import 'package:memora_app/auth/auth_api.dart';
import 'package:memora_app/auth/auth_controller.dart';
import 'package:memora_app/auth/auth_models.dart';
import 'package:memora_app/auth/google_auth_service.dart';
import 'package:memora_app/auth/session_storage.dart';
import 'package:memora_app/screens/home_screen.dart';

ApiClient _healthyApiClient() {
  return ApiClient(
    httpClient: MockClient(
      (request) async => http.Response(
        '{"status":"ok"}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
    baseUrl: 'http://localhost:3000/api/v1',
  );
}

/// AuthController wired to real collaborators, but its status/user are set
/// directly by the test and `bootstrap()` is never triggered (see
/// HomeScreen's "only bootstrap when status == unknown" guard) — so no
/// secure-storage plugin channel or network call happens in these tests.
AuthController _authController(ApiClient apiClient) {
  return AuthController(
    authApi: AuthApi(apiClient),
    googleAuthService: GoogleAuthService(),
    sessionStorage: SessionStorage(),
    apiClient: apiClient,
  );
}

void main() {
  testWidgets('shows the login button and backend status when unauthenticated', (
    tester,
  ) async {
    final apiClient = _healthyApiClient();
    final auth = _authController(apiClient)..status = AuthStatus.unauthenticated;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(healthApi: HealthApi(apiClient), authController: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión con Google'), findsOneWidget);
    expect(find.text('Backend: ok'), findsOneWidget);
  });

  testWidgets('shows user info and a logout button when authenticated', (
    tester,
  ) async {
    final apiClient = _healthyApiClient();
    final auth = _authController(apiClient)
      ..status = AuthStatus.authenticated
      ..user = const AuthUser(id: '1', email: 'user@example.com', name: 'Ada');

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(healthApi: HealthApi(apiClient), authController: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('shows a clear message after a failed/cancelled login attempt', (
    tester,
  ) async {
    final apiClient = _healthyApiClient();
    final auth = _authController(apiClient)
      ..status = AuthStatus.unauthenticated
      ..errorMessage = 'Inicio de sesión cancelado.';

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(healthApi: HealthApi(apiClient), authController: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inicio de sesión cancelado.'), findsOneWidget);
  });
}
