/// Uniform error body from global/spec02-contrato-api.md, surfaced as a
/// Dart exception by [ApiClient].
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.requestId,
  });

  /// HTTP status code, or 0 for a network-level failure (no response).
  final int statusCode;
  final String code;
  final String message;
  final String? requestId;

  @override
  String toString() => 'ApiException($code, $message)';
}
