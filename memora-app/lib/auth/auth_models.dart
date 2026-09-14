class AuthUser {
  const AuthUser({required this.id, required this.email, this.name});

  final String id;
  final String email;
  final String? name;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    if (name != null) 'name': name,
  };
}

/// Memora's own session (never Google's tokens — those stay backend-side).
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory AuthSession.fromLoginResponse(Map<String, dynamic> json) =>
      AuthSession(
        accessToken: json['sessionAccessToken'] as String,
        refreshToken: json['sessionRefreshToken'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  factory AuthSession.fromStorageJson(Map<String, dynamic> json) =>
      AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toStorageJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'user': user.toJson(),
  };
}
