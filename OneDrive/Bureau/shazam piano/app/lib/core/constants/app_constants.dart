/// ShazaPiano Application Constants
class AppConstants {
  // API
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE',
    defaultValue: 'http://10.0.2.2:8000', // Android emulator
  );

  // Recording
  static const int maxRecordingDurationSec = 15;
  static const int recommendedRecordingDurationSec = 8;

  // Upload
  static const int maxUploadSizeMB = 10;

  // Video
  static const int previewDurationSec = 16;

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

  // Spacing
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;

  // Radius
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


