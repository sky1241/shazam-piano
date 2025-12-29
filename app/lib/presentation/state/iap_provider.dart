import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import 'iap_state.dart';

const bool _isProduct = bool.fromEnvironment('dart.vm.product');
const bool _devUnlockAll =
    // DEV ONLY: enable with --dart-define=DEV_UNLOCK_ALL=true in debug/dev.
    !_isProduct && bool.fromEnvironment('DEV_UNLOCK_ALL', defaultValue: false);

/// IAP state provider
final iapProvider = StateNotifierProvider<IAPNotifier, IAPState>((ref) {
  return IAPNotifier();
});

class IAPNotifier extends StateNotifier<IAPState> {
  IAPNotifier() : super(const IAPState()) {
    _initialize();
  }

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  static const String _unlockedKey = 'all_levels_unlocked';

  /// Initialize IAP
  Future<void> _initialize() async {
    try {
      // Check if IAP is available
      final available = await _iap.isAvailable();

      if (!available) {
        if (_devUnlockAll) {
          state = state.copyWith(
            isInitialized: true,
            isUnlocked: true,
            error: null,
          );
          return;
        }
        state = state.copyWith(
          isInitialized: true,
          error: 'Purchases unavailable',
        );
        return;
      }

      // Load saved unlock status
      final prefs = await SharedPreferences.getInstance();
      final isUnlocked = prefs.getBool(_unlockedKey) ?? false;
      final effectiveUnlocked = isUnlocked || _devUnlockAll;

      // Listen to purchase updates
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (error) {
          state = state.copyWith(error: 'Purchase stream error: $error');
        },
      );

      state = state.copyWith(
        isInitialized: true,
        isUnlocked: effectiveUnlocked,
      );

      // Auto-restore on startup
      if (!effectiveUnlocked) {
        await restorePurchases();
      }
    } catch (e) {
      state = state.copyWith(
        isInitialized: true,
        error: 'IAP initialization failed: $e',
      );
    }
  }

  /// Handle purchase updates
  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _unlockContent();
      }

      if (purchase.status == PurchaseStatus.error) {
        state = state.copyWith(
          isPurchasing: false,
          isRestoring: false,
          error: 'Purchase error: ${purchase.error?.message}',
        );
      }

      if (purchase.status == PurchaseStatus.purchased) {
        state = state.copyWith(isPurchasing: false);
      }

      // Complete purchase
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }

  /// Purchase product
  Future<void> purchase() async {
    try {
      state = state.copyWith(isPurchasing: true, error: null);

      // Query product
      final response = await _iap.queryProductDetails({
        AppConstants.iapProductId,
      });

      if (response.notFoundIDs.isNotEmpty) {
        state = state.copyWith(isPurchasing: false, error: 'Product not found');
        return;
      }

      if (response.productDetails.isEmpty) {
        state = state.copyWith(
          isPurchasing: false,
          error: 'No products available',
        );
        return;
      }

      final product = response.productDetails.first;

      // Start purchase
      final purchaseParam = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);

      // State will be updated by purchase stream
    } catch (e) {
      state = state.copyWith(isPurchasing: false, error: 'Purchase failed: $e');
    }
  }

  /// Restore purchases
  Future<void> restorePurchases() async {
    try {
      state = state.copyWith(isRestoring: true, error: null);

      await _iap.restorePurchases();

      // Give it a moment to process
      await Future.delayed(const Duration(seconds: 2));

      if (!state.isUnlocked) {
        state = state.copyWith(
          isRestoring: false,
          error: 'No purchases to restore',
        );
      } else {
        state = state.copyWith(isRestoring: false);
      }
    } catch (e) {
      state = state.copyWith(isRestoring: false, error: 'Restore failed: $e');
    }
  }

  /// Unlock content
  Future<void> _unlockContent() async {
    try {
      // Save to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_unlockedKey, true);

      state = state.copyWith(
        isUnlocked: true,
        isPurchasing: false,
        isRestoring: false,
      );

      // Future: sync to Firestore for multi-device support
    } catch (e) {
      state = state.copyWith(error: 'Failed to unlock: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
