class BuildInfo {
  static const String stamp = String.fromEnvironment(
    'BUILD_STAMP',
    defaultValue: 'dev-unknown',
  );
}
