/// ShazaPiano Application Constants
class AppConstants {
  // Environment helpers
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const bool _isProdEnv = _env == 'prod';

  // API
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE',
    defaultValue: _isProdEnv
        ? 'https://api.shazapiano.com'
        : 'http://127.0.0.1:8000',
  );

  // Recording
  static const int maxRecordingDurationSec = 15;
  static const int recommendedRecordingDurationSec = 8;

  // Upload
  static const int maxUploadSizeMB = 10;

  // Video
  static const int previewDurationSec = 12;

  // IAP
  static const String iapProductId = 'piano_all_levels_1usd';
  static const String iapPrice = '\$1.00';

  // Levels
  static const int totalLevels = 4;
  static const List<String> levelNames = [
    'Hyper Facile',
    'Facile',
    'Moyen',
    'Pro',
  ];
  static const List<String> levelDescriptions = [
    'Mélodie simple, main droite seule',
    'Mélodie + basse simple',
    'Mélodie + accompagnement triades',
    'Arrangement complet avec arpèges',
  ];

  // Spacing (4px base grid — MOBILE.md §36)
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;

  // Touch targets (MOBILE.md §1 — iOS 44pt / Android 48dp)
  static const double touchTargetMin = 44.0;
  static const double touchTargetAndroid = 48.0;

  // Typography floor (WCAG 1.4.4 — never below 12px)
  static const double fontSizeMin = 12.0;

  // Animation durations (MOBILE.md §59)
  static const int animMicroMs = 200;
  static const int animStandardMs = 300;
  static const int animComplexMs = 400;

  // Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusButton = 24.0;
  static const double radiusCard = 16.0;
  static const double borderRadiusCard = 16.0;

  // Button
  static const double recordButtonSize = 220.0;

  // Shadow
  static const double shadowBlur = 30.0;

  // Private constructor
  AppConstants._();
}
