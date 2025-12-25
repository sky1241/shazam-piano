import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../state/iap_provider.dart';

/// Settings Page
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final iapState = ref.watch(iapProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          // Account Section
          _buildSection(
            title: 'Compte',
            children: [
              ListTile(
                leading: const Icon(Icons.person, color: AppColors.primary),
                title: const Text('Statut'),
                subtitle: Text(
                  iapState.isUnlocked ? 'Compte premium' : 'Compte gratuit',
                  style: AppTextStyles.caption.copyWith(
                    color: iapState.isUnlocked
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
                trailing: iapState.isUnlocked
                    ? const Icon(Icons.verified, color: AppColors.success)
                    : null,
              ),
              if (!iapState.isUnlocked)
                ListTile(
                  leading: const Icon(
                    Icons.shopping_cart,
                    color: AppColors.warning,
                  ),
                  title: const Text('Débloquer tous les niveaux'),
                  subtitle: const Text('1,00 \$ - Achat unique'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _handleUnlock,
                ),
              ListTile(
                leading: const Icon(
                  Icons.restore,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Restaurer les achats'),
                onTap: _handleRestore,
              ),
            ],
          ),

          // About Section
          _buildSection(
            title: 'À propos',
            children: [
              const ListTile(
                leading: Icon(Icons.info, color: AppColors.primary),
                title: Text('Version'),
                subtitle: Text('1.0.0+1'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.privacy_tip,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Politique de confidentialité'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openLink('https://shazapiano.com/privacy'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.gavel,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Conditions d\'utilisation'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openLink('https://shazapiano.com/terms'),
              ),
            ],
          ),

          // Support Section
          _buildSection(
            title: 'Support',
            children: [
              ListTile(
                leading: const Icon(Icons.help, color: AppColors.primary),
                title: const Text('Aide & FAQ'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openLink('https://shazapiano.com/faq'),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report, color: AppColors.error),
                title: const Text('Signaler un problème'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openLink('https://shazapiano.com/support'),
              ),
            ],
          ),

          // Danger Zone
          _buildSection(
            title: 'Données',
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Supprimer mes données'),
                subtitle: const Text('Action irréversible'),
                onTap: _handleDeleteData,
              ),
            ],
          ),

          const SizedBox(height: AppConstants.spacing32),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacing16,
            AppConstants.spacing24,
            AppConstants.spacing16,
            AppConstants.spacing8,
          ),
          child: Text(
            title,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  void _handleUnlock() {
    // Paywall placeholder
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ouverture du paywall...')));
  }

  void _handleRestore() async {
    try {
      await ref.read(iapProvider.notifier).restorePurchases();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Achats restaurés avec succès !'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleDeleteData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Supprimer mes données ?'),
        content: const Text(
          'Cette action est irréversible. Toutes vos générations et votre statut premium seront perdus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              // Remove data action placeholder
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Données supprimées'),
                  backgroundColor: AppColors.error,
                ),
              );
            },
            child: const Text(
              'Supprimer',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _openLink(String url) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ouverture: $url'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
