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
    return const AppConfig(
      backendBaseUrl: 'http://10.0.2.2:8000', // Android emulator
      debugMode: true,
      environment: 'dev',
    );
  }

  /// Production configuration
  factory AppConfig.prod() {
    return const AppConfig(
      backendBaseUrl: 'https://api.shazapiano.com', // TODO: Update with real URL
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

