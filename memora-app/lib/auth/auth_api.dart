import '../api/api_client.dart';
import 'auth_models.dart';

/// Backend calls for spec02-autenticacion-google, through the shared
/// [ApiClient] — never a bare `http` call.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<AuthSession> loginWithGoogle(String serverAuthCode) async {
    final json = await _client.postJson('/auth/google', {
      'serverAuthCode': serverAuthCode,
    });
    return AuthSession.fromLoginResponse(json);
  }

  Future<void> logout() => _client.postJson('/auth/logout');
}
