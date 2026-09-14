import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_sign_in_config.dart';

// La autorización de servidor debe incluir los scopes de identidad además de
// drive.file: sin ellos, el access token resultante del canje NO puede leer
// el endpoint userinfo del backend (Google responde 401 "Invalid Credentials").
// Con estos scopes, el backend obtiene la identidad (email/sub) del usuario.
const List<String> _driveScopes = <String>[
  'openid',
  'email',
  'profile',
  'https://www.googleapis.com/auth/drive.file',
];

/// Thrown when Google returns no usable serverAuthCode even though sign-in
/// itself succeeded (rare, but the API allows it).
class GoogleServerAuthorizationException implements Exception {
  const GoogleServerAuthorizationException();
}

/// Wraps `google_sign_in` v7's split authentication/authorization API.
/// Never logs the serverAuthCode or any token it handles.
///
/// v7 replaced the old single `signIn()` call: identity comes from
/// `authenticate()`, and the serverAuthCode (needed for offline/backend
/// access) comes from a separate `authorizationClient.authorizeServer(...)`
/// call — see specs/memora-app/spec02-login-google.md "Notas técnicas".
class GoogleAuthService {
  GoogleAuthService({
    this.serverClientId = googleServerClientId,
    this.iosClientId = googleIosClientId,
  });

  final String serverClientId;
  final String iosClientId;

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      // The iOS client ID only applies on iOS; other platforms resolve
      // their own client from serverClientId / platform registration.
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? iosClientId
          : null,
      serverClientId: serverClientId,
    );
    _initialized = true;
  }

  /// Runs the interactive Google account picker, then requests server
  /// authorization (offline access) for the drive.file scope. Returns the
  /// resulting serverAuthCode, ready to send to
  /// `POST /api/v1/auth/google`.
  ///
  /// Throws [GoogleSignInException] (e.g. `code == canceled` if the user
  /// dismisses the picker) or [GoogleServerAuthorizationException].
  Future<String> signInAndAuthorizeServer() async {
    await _ensureInitialized();

    final GoogleSignInAccount account = await GoogleSignIn.instance
        .authenticate();
    final GoogleSignInServerAuthorization? serverAuth = await account
        .authorizationClient
        .authorizeServer(_driveScopes);

    if (serverAuth == null || serverAuth.serverAuthCode.isEmpty) {
      throw const GoogleServerAuthorizationException();
    }
    return serverAuth.serverAuthCode;
  }

  /// Clears the local Google session on this device.
  Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }
}
