import 'api_client.dart';

class HealthStatus {
  const HealthStatus({required this.status});

  final String status;

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(status: json['status'] as String? ?? 'unknown');
  }
}

/// GET /api/v1/health through the shared [ApiClient].
class HealthApi {
  const HealthApi(this._client);

  final ApiClient _client;

  Future<HealthStatus> getHealth() async {
    final json = await _client.getJson('/health');
    return HealthStatus.fromJson(json);
  }
}
