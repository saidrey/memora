import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/health_api.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/google_auth_service.dart';
import 'auth/session_storage.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MemoraApp());
}

class MemoraApp extends StatelessWidget {
  const MemoraApp({super.key, this.apiClient, this.authController});

  /// Overridable for tests; defaults to a real, shared backend-backed
  /// instance so the auth layer and health checks share one ApiClient
  /// (needed so the Authorization header set after login applies
  /// everywhere).
  final ApiClient? apiClient;
  final AuthController? authController;

  @override
  Widget build(BuildContext context) {
    final apiClient = this.apiClient ?? ApiClient();
    final authController =
        this.authController ??
        AuthController(
          authApi: AuthApi(apiClient),
          googleAuthService: GoogleAuthService(),
          sessionStorage: SessionStorage(),
          apiClient: apiClient,
        );

    return MaterialApp(
      title: 'Memora',
      home: HomeScreen(
        healthApi: HealthApi(apiClient),
        authController: authController,
      ),
    );
  }
}
