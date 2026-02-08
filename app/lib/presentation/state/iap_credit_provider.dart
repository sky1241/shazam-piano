/// ShazaPiano - IAP Credit Provider (Riverpod)
///
/// Nouveau système : achat par musique (1€ consumable) avec
/// backward compatibility pour les users lifetime existants.
///
/// NOT connected to existing code. Ready to be integrated.
/// NE REMPLACE PAS iap_provider.dart — fonctionne EN PLUS.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'iap_provider.dart'; // Pour vérifier le lifetime unlock

// ─────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────

/// Product ID pour 1 crédit (consumable)
const String kCreditProductId = 'shazapiano_credit_1eur';

/// Prix affiché
const String kCreditPrice = '1,00 €';

/// Clé de stockage des crédits
const String _creditsKey = 'shazapiano_credits';

/// Clé de stockage des jobs débloqués
const String _unlockedJobsKey = 'shazapiano_unlocked_jobs';

// ─────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────

class IAPCreditState {
  final int availableCredits;
  final Set<String> unlockedJobIds;
  final bool isPurchasing;
  final bool isInitialized;
  final String? error;

  const IAPCreditState({
    this.availableCredits = 0,
    this.unlockedJobIds = const {},
    this.isPurchasing = false,
    this.isInitialized = false,
    this.error,
  });

  IAPCreditState copyWith({
    int? availableCredits,
    Set<String>? unlockedJobIds,
    bool? isPurchasing,
    bool? isInitialized,
    String? error,
    bool clearError = false,
  }) {
    return IAPCreditState(
      availableCredits: availableCredits ?? this.availableCredits,
      unlockedJobIds: unlockedJobIds ?? this.unlockedJobIds,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      isInitialized: isInitialized ?? this.isInitialized,
      error: clearError ? null : error ?? this.error,
    );
  }

  /// Vérifie si un job est débloqué (par crédit ou par lifetime)
  bool isJobUnlocked(String jobId) {
    return unlockedJobIds.contains(jobId);
  }

  bool get hasCredits => availableCredits > 0;
}

// ─────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────

final iapCreditProvider =
    StateNotifierProvider<IAPCreditNotifier, IAPCreditState>((ref) {
      return IAPCreditNotifier(ref);
    });

class IAPCreditNotifier extends StateNotifier<IAPCreditState> {
  final Ref _ref;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  IAPCreditNotifier(this._ref) : super(const IAPCreditState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Charger les données locales
      final prefs = await SharedPreferences.getInstance();
      final credits = prefs.getInt(_creditsKey) ?? 0;
      final unlockedJobsJson = prefs.getString(_unlockedJobsKey);
      final unlockedJobs = <String>{};
      if (unlockedJobsJson != null) {
        final list = jsonDecode(unlockedJobsJson) as List;
        unlockedJobs.addAll(list.cast<String>());
      }

      // Écouter les achats
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (error) {
          state = state.copyWith(error: 'Purchase stream error: $error');
        },
      );

      state = state.copyWith(
        availableCredits: credits,
        unlockedJobIds: unlockedJobs,
        isInitialized: true,
      );
    } catch (e) {
      state = state.copyWith(isInitialized: true, error: 'Init error: $e');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.productID != kCreditProductId) continue;

      if (purchase.status == PurchaseStatus.purchased) {
        // Ajouter un crédit
        _addCredit();
        state = state.copyWith(isPurchasing: false);
      }

      if (purchase.status == PurchaseStatus.error) {
        state = state.copyWith(
          isPurchasing: false,
          error: 'Erreur achat: ${purchase.error?.message}',
        );
      }

      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }

  /// Acheter un crédit (1€)
  Future<void> purchaseCredit() async {
    state = state.copyWith(isPurchasing: true, clearError: true);

    try {
      final response = await _iap.queryProductDetails({kCreditProductId});

      if (response.productDetails.isEmpty) {
        state = state.copyWith(
          isPurchasing: false,
          error: 'Produit non trouvé',
        );
        return;
      }

      final product = response.productDetails.first;
      final purchaseParam = PurchaseParam(productDetails: product);
      await _iap.buyConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      state = state.copyWith(isPurchasing: false, error: 'Erreur achat: $e');
    }
  }

  /// Consommer un crédit pour débloquer un job
  Future<bool> useCredit(String jobId) async {
    // Vérifier d'abord si l'user a le lifetime (ancien système)
    final legacyIap = _ref.read(iapProvider);
    if (legacyIap.isUnlocked) return true;

    // Vérifier si déjà débloqué
    if (state.isJobUnlocked(jobId)) return true;

    // Vérifier les crédits
    if (state.availableCredits <= 0) return false;

    // Consommer
    final newCredits = state.availableCredits - 1;
    final newUnlocked = Set<String>.from(state.unlockedJobIds)..add(jobId);

    state = state.copyWith(
      availableCredits: newCredits,
      unlockedJobIds: newUnlocked,
    );

    // Persister
    await _saveState(newCredits, newUnlocked);
    return true;
  }

  /// Vérifier si un job est accessible (lifetime OU crédit)
  bool isAccessible(String jobId) {
    final legacyIap = _ref.read(iapProvider);
    if (legacyIap.isUnlocked) return true;
    return state.isJobUnlocked(jobId);
  }

  /// Ajouter un crédit (après achat réussi)
  Future<void> _addCredit() async {
    final newCredits = state.availableCredits + 1;
    state = state.copyWith(availableCredits: newCredits);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_creditsKey, newCredits);
  }

  /// Sauvegarder l'état
  Future<void> _saveState(int credits, Set<String> unlockedJobs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_creditsKey, credits);
      await prefs.setString(
        _unlockedJobsKey,
        jsonEncode(unlockedJobs.toList()),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
