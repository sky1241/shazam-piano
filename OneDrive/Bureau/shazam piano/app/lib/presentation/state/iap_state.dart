import 'package:flutter/foundation.dart';

/// State for In-App Purchase
@immutable
class IAPState {
  final bool isInitialized;
  final bool isPurchasing;
  final bool isRestoring;
  final bool isUnlocked;
  final String? error;

  const IAPState({
    this.isInitialized = false,
    this.isPurchasing = false,
    this.isRestoring = false,
    this.isUnlocked = false,
    this.error,
  });

  IAPState copyWith({
    bool? isInitialized,
    bool? isPurchasing,
    bool? isRestoring,
    bool? isUnlocked,
    String? error,
  }) {
    return IAPState(
      isInitialized: isInitialized ?? this.isInitialized,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      isRestoring: isRestoring ?? this.isRestoring,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      error: error ?? this.error,
    );
  }

  bool get isLoading => isPurchasing || isRestoring;
  bool get hasError => error != null;
}

