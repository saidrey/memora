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
  }) {
    // Wired once, here, rather than left for main.dart to remember: ApiClient
    // knows nothing about SessionStorage or AuthStatus, it only exposes
    // these two minimal hooks (spec06-sesion-y-reauth-drive.md, A1.5).
    apiClient.onSessionRefreshed = _handleSessionRefreshed;
    apiClient.onSessionInvalidated = _handleSessionInvalidated;
  }

  final AuthApi authApi;
  final GoogleAuthService googleAuthService;
  final SessionStorage sessionStorage;
  final ApiClient apiClient;

  AuthStatus status = AuthStatus.unknown;
  AuthUser? user;
  String? errorMessage;

  /// Restores a previously stored session, if any. Per spec01/spec02, this
  /// only checks whether a session is stored — it doesn't validate it
  /// against the backend up front (an expired access token is instead
  /// refreshed transparently on the first request that needs it, via
  /// ApiClient's interceptor — spec06/A1.5).
  Future<void> bootstrap() async {
    final stored = await sessionStorage.read();
    if (stored == null) {
      status = AuthStatus.unauthenticated;
    } else {
      apiClient.setAccessToken(stored.accessToken);
      apiClient.setRefreshToken(stored.refreshToken);
      user = stored.user;
      status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  /// `ApiClient.onSessionRefreshed`: persists the refreshed tokens (keeping
  /// the current `user`, unchanged by a refresh) and re-notifies — this is
  /// NOT a status change, just newer tokens for the same authenticated
  /// session.
  Future<void> _handleSessionRefreshed(
    String accessToken,
    String refreshToken,
  ) async {
    final currentUser = user;
    if (currentUser == null) return;
    await sessionStorage.save(
      AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: currentUser,
      ),
    );
  }

  /// `ApiClient.onSessionInvalidated`: the refresh token itself is
  /// dead/revoked, so the session can't be salvaged — clears the local
  /// session entirely and signs the user out locally. Deliberately NOT the
  /// same as `signOut()`: the backend session is already gone (calling
  /// `authApi.logout()` would be a pointless network call against an
  /// already-invalid session), and there's no reason to also sign the user
  /// out of their Google account on-device for this.
  Future<void> _handleSessionInvalidated() async {
    await sessionStorage.clear();
    apiClient.setAccessToken(null);
    apiClient.setRefreshToken(null);
    user = null;
    status = AuthStatus.unauthenticated;
    errorMessage = 'Tu sesión expiró. Vuelve a iniciar sesión.';
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
      apiClient.setRefreshToken(session.refreshToken);
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
    apiClient.setRefreshToken(null);
    user = null;
    errorMessage = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Message from the most recent [reconnectDrive] attempt, if it failed —
  /// deliberately a separate field from [errorMessage] (the normal
  /// login/logout error slot) so a failed/cancelled Drive reconnect never
  /// overwrites or is overwritten by an unrelated login error. Cleared at
  /// the start of every call.
  String? driveReconnectErrorMessage;

  /// Renews the Google Drive authorization the backend has on file, by
  /// re-running the SAME channel as [signIn] (spec06-sesion-y-reauth-drive,
  /// A1.6): no dedicated "reconnect" endpoint exists — `POST /auth/google`
  /// upserts the user and overwrites the stored Google refresh token, so
  /// calling it again with a fresh `serverAuthCode` (scope `drive.file`) is
  /// how a stale Drive authorization gets renewed.
  ///
  /// D10, respected literally: this NEVER changes [status] or signs the app
  /// session out, on success, cancellation, or failure alike — the app
  /// session and the Drive authorization are independent. Returns `true` on
  /// success; `false` on cancellation or any failure (see
  /// [driveReconnectErrorMessage] for a user-facing message in that case).
  Future<bool> reconnectDrive() async {
    driveReconnectErrorMessage = null;
    notifyListeners();

    try {
      final serverAuthCode = await googleAuthService
          .signInAndAuthorizeServer();
      final session = await authApi.loginWithGoogle(serverAuthCode);
      await sessionStorage.save(session);
      apiClient.setAccessToken(session.accessToken);
      apiClient.setRefreshToken(session.refreshToken);
      user = session.user;
      notifyListeners();
      return true;
    } on GoogleSignInException catch (error) {
      driveReconnectErrorMessage = error.code == GoogleSignInExceptionCode.canceled
          ? 'Reconexión con Google Drive cancelada.'
          : 'No se pudo reconectar Google Drive. Intenta de nuevo.';
    } on GoogleServerAuthorizationException {
      driveReconnectErrorMessage =
          'No se pudo reconectar Google Drive. Intenta de nuevo.';
    } on ApiException {
      driveReconnectErrorMessage =
          'No se pudo reconectar Google Drive. Intenta de nuevo.';
    } catch (_) {
      driveReconnectErrorMessage =
          'No se pudo reconectar Google Drive. Intenta de nuevo.';
    }
    notifyListeners();
    return false;
  }
}
