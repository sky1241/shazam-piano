import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../device_calibration.dart';

/// Résultat de la détection automatique du device.
class DeviceDetectionResult {
  const DeviceDetectionResult({
    required this.tier,
    required this.deviceModel,
    required this.ramMb,
    required this.confidence,
    required this.detectionMethod,
    this.isEmulator = false,
  });

  /// Tier détecté (lowEnd, midRange, highEnd).
  final DeviceTier tier;

  /// Modèle du device (ex: "Pixel 7", "iPhone 14").
  final String deviceModel;

  /// RAM en MB (0 si non disponible).
  final int ramMb;

  /// Confiance de la détection (0.0-1.0).
  final double confidence;

  /// Méthode utilisée pour la détection.
  final String detectionMethod;

  /// True si c'est un émulateur.
  final bool isEmulator;

  @override
  String toString() {
    return 'DeviceDetectionResult(tier=${tier.name}, model=$deviceModel, '
        'ram=${ramMb}MB, confidence=${confidence.toStringAsFixed(2)}, '
        'method=$detectionMethod, isEmulator=$isEmulator)';
  }
}

/// Service de détection automatique du tier du device.
///
/// Utilise device_info_plus pour récupérer les informations du device
/// et classifier automatiquement en lowEnd/midRange/highEnd.
class DeviceDetector {
  DeviceDetector({DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  /// Détecte le tier du device.
  Future<DeviceDetectionResult> detect() async {
    try {
      if (Platform.isAndroid) {
        return await _detectAndroid();
      } else if (Platform.isIOS) {
        return await _detectIOS();
      } else {
        return _fallbackResult();
      }
    } catch (e) {
      debugPrint('DeviceDetector: Detection failed: $e');
      return _fallbackResult();
    }
  }

  Future<DeviceDetectionResult> _detectAndroid() async {
    final info = await _deviceInfo.androidInfo;

    final model = info.model;
    final brand = info.brand.toLowerCase();
    final sdkInt = info.version.sdkInt;
    final isEmulator = !info.isPhysicalDevice;

    // Essayer d'obtenir la RAM via les supported ABIs (heuristique)
    // Note: device_info_plus ne donne pas directement la RAM
    // On utilise le SDK version comme proxy
    final estimatedRamMb = _estimateRamFromSdk(sdkInt, brand);

    final tier = _classifyAndroid(
      brand: brand,
      model: model,
      sdkInt: sdkInt,
      estimatedRamMb: estimatedRamMb,
    );

    final confidence = isEmulator ? 0.5 : 0.8;

    if (kDebugMode) {
      debugPrint(
        'DeviceDetector: Android detected - $brand $model, SDK $sdkInt, '
        'estimated RAM ${estimatedRamMb}MB -> ${tier.name}',
      );
    }

    return DeviceDetectionResult(
      tier: tier,
      deviceModel: '$brand $model',
      ramMb: estimatedRamMb,
      confidence: confidence,
      detectionMethod: 'device_info_android',
      isEmulator: isEmulator,
    );
  }

  Future<DeviceDetectionResult> _detectIOS() async {
    final info = await _deviceInfo.iosInfo;

    final model = info.utsname.machine;
    final name = info.name;
    final isEmulator = !info.isPhysicalDevice;

    final tier = _classifyIOS(model: model);
    final estimatedRamMb = _estimateRamFromIOSModel(model);
    final confidence = isEmulator ? 0.5 : 0.85;

    if (kDebugMode) {
      debugPrint(
        'DeviceDetector: iOS detected - $name ($model), '
        'estimated RAM ${estimatedRamMb}MB -> ${tier.name}',
      );
    }

    return DeviceDetectionResult(
      tier: tier,
      deviceModel: name,
      ramMb: estimatedRamMb,
      confidence: confidence,
      detectionMethod: 'device_info_ios',
      isEmulator: isEmulator,
    );
  }

  DeviceDetectionResult _fallbackResult() {
    if (kDebugMode) {
      debugPrint('DeviceDetector: Using fallback (lowEnd)');
    }
    return const DeviceDetectionResult(
      tier: DeviceTier.lowEnd,
      deviceModel: 'Unknown',
      ramMb: 0,
      confidence: 0.3,
      detectionMethod: 'fallback',
    );
  }

  /// Classifie un device Android en tier.
  DeviceTier _classifyAndroid({
    required String brand,
    required String model,
    required int sdkInt,
    required int estimatedRamMb,
  }) {
    // Flagship brands/models connus (2022+)
    final isKnownFlagship = _isKnownFlagshipAndroid(brand, model);
    if (isKnownFlagship) {
      return DeviceTier.highEnd;
    }

    // Classification par RAM estimée
    if (estimatedRamMb >= 6144) {
      // >= 6GB
      return DeviceTier.highEnd;
    } else if (estimatedRamMb >= 3072) {
      // 3-6GB
      return DeviceTier.midRange;
    }

    // Classification par SDK (Android version)
    // SDK 33 = Android 13 (2022), SDK 31 = Android 12 (2021)
    if (sdkInt >= 33) {
      // Android 13+ = probablement device récent
      return DeviceTier.midRange;
    }

    return DeviceTier.lowEnd;
  }

  /// Classifie un device iOS en tier.
  DeviceTier _classifyIOS({required String model}) {
    // Format: iPhone14,2 = iPhone 13 Pro, iPhone15,2 = iPhone 14 Pro, etc.
    final match = RegExp(r'iPhone(\d+),').firstMatch(model);
    if (match != null) {
      final generation = int.tryParse(match.group(1) ?? '0') ?? 0;

      // iPhone 15,x = iPhone 14 (2022) → highEnd
      // iPhone 14,x = iPhone 13 (2021) → highEnd
      // iPhone 13,x = iPhone 12 (2020) → midRange
      // iPhone 12,x = iPhone 11 (2019) → midRange
      // Older → lowEnd
      if (generation >= 14) {
        return DeviceTier.highEnd;
      } else if (generation >= 12) {
        return DeviceTier.midRange;
      }
    }

    // iPad ou autre
    if (model.contains('iPad')) {
      // iPads récents sont généralement performants
      return DeviceTier.midRange;
    }

    return DeviceTier.lowEnd;
  }

  /// Vérifie si c'est un flagship Android connu.
  bool _isKnownFlagshipAndroid(String brand, String model) {
    final modelLower = model.toLowerCase();
    final brandLower = brand.toLowerCase();

    // Samsung Galaxy S/Note/Z series (S21+, S22+, S23+, Z Fold/Flip)
    if (brandLower == 'samsung') {
      if (modelLower.contains('sm-s9') || // S23, S24
          modelLower.contains('sm-s8') || // S22
          modelLower.contains('sm-f9') || // Z Fold 5
          modelLower.contains('sm-f7')) {
        // Z Flip 5
        return true;
      }
    }

    // Google Pixel 7+
    if (brandLower == 'google') {
      if (modelLower.contains('pixel 7') ||
          modelLower.contains('pixel 8') ||
          modelLower.contains('pixel 9')) {
        return true;
      }
    }

    // OnePlus 10+
    if (brandLower == 'oneplus') {
      final numMatch = RegExp(r'(\d+)').firstMatch(modelLower);
      if (numMatch != null) {
        final num = int.tryParse(numMatch.group(1) ?? '0') ?? 0;
        if (num >= 10) return true;
      }
    }

    return false;
  }

  /// Estime la RAM basée sur le SDK Android et la marque.
  int _estimateRamFromSdk(int sdkInt, String brand) {
    // Heuristique basée sur les tendances du marché
    // SDK 34 = Android 14 (2023) → devices récents, probablement 4-8GB
    // SDK 33 = Android 13 (2022) → 4-6GB
    // SDK 31-32 = Android 12 (2021) → 3-6GB
    // SDK 30 = Android 11 (2020) → 2-4GB
    // Older → 2-3GB

    final brandLower = brand.toLowerCase();
    final isBudgetBrand = [
      'xiaomi',
      'redmi',
      'realme',
      'poco',
      'oppo',
      'vivo',
    ].contains(brandLower);

    if (sdkInt >= 34) {
      return isBudgetBrand ? 4096 : 6144;
    } else if (sdkInt >= 33) {
      return isBudgetBrand ? 3072 : 4096;
    } else if (sdkInt >= 31) {
      return isBudgetBrand ? 3072 : 4096;
    } else if (sdkInt >= 30) {
      return isBudgetBrand ? 2048 : 3072;
    }
    return 2048;
  }

  /// Estime la RAM basée sur le modèle iOS.
  int _estimateRamFromIOSModel(String model) {
    final match = RegExp(r'iPhone(\d+),').firstMatch(model);
    if (match != null) {
      final generation = int.tryParse(match.group(1) ?? '0') ?? 0;

      // iPhone 15,x = 6GB
      // iPhone 14,x = 4-6GB
      // iPhone 13,x = 4GB
      // iPhone 12,x = 4GB
      // Older = 2-3GB
      if (generation >= 15) return 6144;
      if (generation >= 14) return 4096;
      if (generation >= 12) return 4096;
    }
    return 3072;
  }
}
