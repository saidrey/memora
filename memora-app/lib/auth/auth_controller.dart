import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'auth_api.dart';
import 'auth_models.dart';
import 'google_auth_service.dart';
import 'session_storage.dart';

enum AuthStatus { unknown, authenticating, authenticated, unauthenticated }

/// Owns the app's authentication state. A plain [ChangeNotifier] is enough
/// here (no extra state-management dependency needed for this scope).
class AuthController extends ChangeNotifier {
  AuthController({
    required this.authApi,
    required this.googleAuthService,
    required this.sessionStorage,
    required this.apiClient,
  });

  final AuthApi authApi;
  final GoogleAuthService googleAuthService;
  final SessionStorage sessionStorage;
  final ApiClient apiClient;

  AuthStatus status = AuthStatus.unknown;
  AuthUser? user;
  String? errorMessage;

  /// Restores a previously stored session, if any. Per spec01/spec02, this
  /// only checks whether a session is stored — it doesn't validate or
  /// refresh it against the backend (refresh handling is out of scope).
  Future<void> bootstrap() async {
    final stored = await sessionStorage.read();
    if (stored == null) {
      status = AuthStatus.unauthenticated;
    } else {
      apiClient.setAccessToken(stored.accessToken);
      user = stored.user;
      status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    status = AuthStatus.authenticating;
    errorMessage = null;
    notifyListeners();

    try {
      final serverAuthCode = await googleAuthService
          .signInAndAuthorizeServer();
      final session = await authApi.loginWithGoogle(serverAuthCode);
      await sessionStorage.save(session);
      apiClient.setAccessToken(session.accessToken);
      user = session.user;
      status = AuthStatus.authenticated;
    } on GoogleSignInException catch (error) {
      status = AuthStatus.unauthenticated;
      errorMessage = error.code == GoogleSignInExceptionCode.canceled
          ? 'Inicio de sesión cancelado.'
          : 'No se pudo iniciar sesión con Google. Intenta de nuevo.';
    } on GoogleServerAuthorizationException {
      status = AuthStatus.unauthenticated;
      errorMessage = 'No se pudo iniciar sesión con Google. Intenta de nuevo.';
    } on ApiException {
      status = AuthStatus.unauthenticated;
      errorMessage =
          'No se pudo completar el inicio de sesión. Intenta de nuevo.';
    } catch (_) {
      status = AuthStatus.unauthenticated;
      errorMessage = 'No se pudo iniciar sesión. Intenta de nuevo.';
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await authApi.logout();
    } catch (_) {
      // Best-effort: still clear the local session even if the backend
      // call fails (e.g. offline), so the user isn't stuck signed in on
      // this device.
    }
    await googleAuthService.signOut();
    await sessionStorage.clear();
    apiClient.setAccessToken(null);
    user = null;
    errorMessage = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
