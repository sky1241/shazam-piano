/// ShazaPiano App Configuration
/// Manages environment-specific settings
class AppConfig {
  final String backendBaseUrl;
  final bool debugMode;
  final String environment;

  const AppConfig({
    required this.backendBaseUrl,
    required this.debugMode,
    required this.environment,
  });

  /// Development configuration
  factory AppConfig.dev() {
    const backendFromEnv = String.fromEnvironment(
      'BACKEND_BASE',
      // Local backend by default; override with --dart-define=BACKEND_BASE=...
      defaultValue: 'http://127.0.0.1:8000',
    );
    return const AppConfig(
      backendBaseUrl: backendFromEnv, // Device + adb reverse if provided
      debugMode: true,
      environment: 'dev',
    );
  }

  /// Production configuration
  factory AppConfig.prod() {
    const backendFromEnv = String.fromEnvironment(
      'BACKEND_BASE',
      defaultValue: 'https://api.shazapiano.com',
    );
    return const AppConfig(
      backendBaseUrl: backendFromEnv,
      debugMode: false,
      environment: 'prod',
    );
  }

  /// Get config from environment
  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'prod':
        return AppConfig.prod();
      case 'dev':
      default:
        return AppConfig.dev();
    }
  }
}
