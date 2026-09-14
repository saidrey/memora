/// Base URL of memora-backend's API, including the versioned prefix.
///
/// Configurable per build/run via `--dart-define=API_BASE_URL=...`. Defaults
/// to memora-backend's own local default (`PORT ?? 3000`).
///
/// NOTE: on the Android emulator, `localhost` refers to the emulator itself,
/// not the host machine — override there with:
///   --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
/// The default below works as-is for iOS simulator, desktop and web.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api/v1',
);
