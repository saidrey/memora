import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/testing.dart';
import 'package:memora_app/api/api_client.dart';
import 'package:memora_app/api/api_exception.dart';
import 'package:memora_app/auth/auth_api.dart';
import 'package:memora_app/auth/auth_controller.dart';
import 'package:memora_app/auth/auth_models.dart';
import 'package:memora_app/auth/google_auth_service.dart';
import 'package:memora_app/auth/session_storage.dart';

/// In-memory stand-in for the real (secure-storage-plugin-backed)
/// SessionStorage, same spirit as the other `_Fake*` collaborators in this
/// test suite: subclasses the real class and overrides every method so no
/// platform channel is ever touched, while also recording what was written
/// so tests can assert on it.
class _FakeSessionStorage extends SessionStorage {
  AuthSession? stored;
  int saveCalls = 0;
  int clearCalls = 0;

  @override
  Future<AuthSession?> read() async => stored;

  @override
  Future<void> save(AuthSession session) async {
    saveCalls++;
    stored = session;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    stored = null;
  }
}

/// Stands in for the real (platform-channel-backed) GoogleAuthService: never
/// touches `GoogleSignIn.instance`.
class _FakeGoogleAuthService extends GoogleAuthService {
  Object? throwOnAuthorize;
  int signOutCalls = 0;

  @override
  Future<String> signInAndAuthorizeServer() async {
    if (throwOnAuthorize != null) throw throwOnAuthorize!;
    return 'fake-server-auth-code';
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

/// Stands in for the real AuthApi: never touches the network. Constructed
/// with a throwing ApiClient so any accidental fallthrough to the real
/// implementation fails loudly instead of silently succeeding.
class _FakeAuthApi extends AuthApi {
  _FakeAuthApi()
    : super(
        ApiClient(
          httpClient: MockClient(
            (request) async =>
                throw StateError('unexpected network call: ${request.url}'),
          ),
          baseUrl: 'http://localhost:3000/api/v1',
        ),
      );

  AuthSession? Function(String serverAuthCode)? onLogin;
  Object? throwOnLogin;
  int logoutCalls = 0;

  @override
  Future<AuthSession> loginWithGoogle(String serverAuthCode) async {
    if (throwOnLogin != null) throw throwOnLogin!;
    return onLogin?.call(serverAuthCode) ??
        AuthSession(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          user: const AuthUser(id: 'u1', email: 'user@example.com'),
        );
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

AuthController _buildController({
  _FakeAuthApi? authApi,
  _FakeGoogleAuthService? googleAuthService,
  _FakeSessionStorage? sessionStorage,
  ApiClient? apiClient,
}) {
  return AuthController(
    authApi: authApi ?? _FakeAuthApi(),
    googleAuthService: googleAuthService ?? _FakeGoogleAuthService(),
    sessionStorage: sessionStorage ?? _FakeSessionStorage(),
    apiClient: apiClient ?? ApiClient(baseUrl: 'http://localhost:3000/api/v1'),
  );
}

void main() {
  group('AuthController.reconnectDrive', () {
    test('on success, updates tokens/user, persists the session, and leaves '
        'status untouched (D10)', () async {
      final authApi = _FakeAuthApi();
      final apiClient = ApiClient(baseUrl: 'http://localhost:3000/api/v1');
      final sessionStorage = _FakeSessionStorage();
      final controller = _buildController(
        authApi: authApi,
        apiClient: apiClient,
        sessionStorage: sessionStorage,
      )
        ..status = AuthStatus.authenticated
        ..user = const AuthUser(id: 'old', email: 'old@example.com');

      final result = await controller.reconnectDrive();

      expect(result, isTrue);
      expect(controller.status, AuthStatus.authenticated);
      expect(controller.user?.id, 'u1');
      expect(controller.driveReconnectErrorMessage, isNull);
      expect(sessionStorage.saveCalls, 1);
      expect(sessionStorage.stored?.accessToken, 'new-access');
    });

    test('a cancelled Google picker leaves the session completely intact '
        'and returns false', () async {
      final sessionStorage = _FakeSessionStorage();
      final googleAuthService = _FakeGoogleAuthService()
        ..throwOnAuthorize = const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        );
      final controller = _buildController(
        googleAuthService: googleAuthService,
        sessionStorage: sessionStorage,
      )
        ..status = AuthStatus.authenticated
        ..user = const AuthUser(id: 'old', email: 'old@example.com');

      final result = await controller.reconnectDrive();

      expect(result, isFalse);
      expect(controller.status, AuthStatus.authenticated);
      expect(controller.user?.id, 'old');
      expect(controller.driveReconnectErrorMessage, contains('cancelada'));
      expect(sessionStorage.saveCalls, 0);
    });

    test('a backend failure (ApiException) leaves the session intact and '
        'returns false', () async {
      final authApi = _FakeAuthApi()
        ..throwOnLogin = const ApiException(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: 'boom',
        );
      final sessionStorage = _FakeSessionStorage();
      final controller = _buildController(
        authApi: authApi,
        sessionStorage: sessionStorage,
      )
        ..status = AuthStatus.authenticated
        ..user = const AuthUser(id: 'old', email: 'old@example.com');

      final result = await controller.reconnectDrive();

      expect(result, isFalse);
      expect(controller.status, AuthStatus.authenticated);
      expect(controller.user?.id, 'old');
      expect(controller.driveReconnectErrorMessage, isNotNull);
      expect(sessionStorage.saveCalls, 0);
    });
  });

  group('ApiClient session-refresh hooks wired by AuthController', () {
    test('onSessionRefreshed persists the new tokens under the current user '
        'without changing status', () async {
      final apiClient = ApiClient(baseUrl: 'http://localhost:3000/api/v1');
      final sessionStorage = _FakeSessionStorage();
      final controller = _buildController(
        apiClient: apiClient,
        sessionStorage: sessionStorage,
      )
        ..status = AuthStatus.authenticated
        ..user = const AuthUser(id: 'u1', email: 'user@example.com');

      await apiClient.onSessionRefreshed?.call('refreshed-access', 'refreshed-refresh');

      expect(sessionStorage.saveCalls, 1);
      expect(sessionStorage.stored?.accessToken, 'refreshed-access');
      expect(sessionStorage.stored?.refreshToken, 'refreshed-refresh');
      expect(sessionStorage.stored?.user.id, 'u1');
      expect(controller.status, AuthStatus.authenticated);
    });

    test('onSessionInvalidated clears the session and signs the user out '
        'locally, without calling logout()', () async {
      final apiClient = ApiClient(baseUrl: 'http://localhost:3000/api/v1')
        ..setAccessToken('old-access')
        ..setRefreshToken('old-refresh');
      final sessionStorage = _FakeSessionStorage();
      final authApi = _FakeAuthApi();
      final controller = _buildController(
        apiClient: apiClient,
        sessionStorage: sessionStorage,
        authApi: authApi,
      )
        ..status = AuthStatus.authenticated
        ..user = const AuthUser(id: 'u1', email: 'user@example.com');

      await apiClient.onSessionInvalidated?.call();

      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.user, isNull);
      expect(controller.errorMessage, isNotNull);
      expect(sessionStorage.clearCalls, 1);
      // Backend session is already dead; calling logout() would be a
      // pointless network call.
      expect(authApi.logoutCalls, 0);
    });
  });
}
