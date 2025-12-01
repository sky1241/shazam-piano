import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../state/iap_provider.dart';

class PaywallModal extends ConsumerStatefulWidget {
  const PaywallModal({super.key});

  @override
  ConsumerState<PaywallModal> createState() => _PaywallModalState();
}

class _PaywallModalState extends ConsumerState<PaywallModal> {
  bool _isPurchasing = false;

  @override
  Widget build(BuildContext context) {
    final iapState = ref.watch(iapProvider);

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.buttonGradient,
              ),
              child: const Icon(
                Icons.lock_open,
                size: 40,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: AppConstants.spacing24),

            // Title
            Text(
              'Tout débloquer pour 1\$',
              style: AppTextStyles.title.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppConstants.spacing16),

            // Features
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFeature('4 niveaux de difficulté'),
                _buildFeature('Vidéos complètes'),
                _buildFeature('Mode pratique interactif'),
                _buildFeature('Téléchargement illimité'),
                _buildFeature('Mises à jour gratuites'),
              ],
            ),

            const SizedBox(height: AppConstants.spacing24),

            // Purchase Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isPurchasing ? null : _handlePurchase,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isPurchasing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Acheter maintenant - 1,00 \$'),
              ),
            ),

            const SizedBox(height: AppConstants.spacing12),

            // Restore Button
            TextButton(
              onPressed: _handleRestore,
              child: Text(
                'Restaurer l\'achat',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),

            // Error message
            if (iapState.error != null) ...[
              const SizedBox(height: AppConstants.spacing12),
              Container(
                padding: const EdgeInsets.all(AppConstants.spacing12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: AppConstants.spacing8),
                    Expanded(
                      child: Text(
                        iapState.error!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: 20,
          ),
          const SizedBox(width: AppConstants.spacing12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePurchase() async {
    setState(() {
      _isPurchasing = true;
    });

    try {
      await ref.read(iapProvider.notifier).purchase();
      
      final iapState = ref.read(iapProvider);
      
      if (iapState.isUnlocked && mounted) {
        // Success - close modal
        Navigator.of(context).pop(true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Achat réussi ! Tous les niveaux sont débloqués 🎉'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur d\'achat: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPurchasing = false;
        });
      }
    }
  }

  Future<void> _handleRestore() async {
    try {
      await ref.read(iapProvider.notifier).restorePurchases();
      
      final iapState = ref.read(iapProvider);
      
      if (iapState.isUnlocked && mounted) {
        Navigator.of(context).pop(true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Achat restauré avec succès !'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun achat à restaurer'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de restauration: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

