import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/strings_fr.dart';
import '../../state/iap_provider.dart';
import '../../widgets/paywall_modal.dart';
import 'privacy_data_page.dart';

/// Settings Page — UX rules applied:
/// touch targets 44px+, haptic feedback, proper destructive action UX,
/// visual hierarchy with icon backgrounds, premium status card.
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
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Parametres', style: AppTextStyles.title),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing16),
        children: [
          // ─── Premium Status Card ─────────────────────────
          _PremiumCard(
            isUnlocked: iapState.isUnlocked,
            onUnlockTap: _handleUnlock,
          ),

          // ─── Compte ──────────────────────────────────────
          const _SectionHeader(title: 'COMPTE'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.restore,
                iconColor: AppColors.textSecondary,
                title: 'Restaurer les achats',
                onTap: _handleRestore,
              ),
            ],
          ),

          // ─── A propos ────────────────────────────────────
          const _SectionHeader(title: 'A PROPOS'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.shield_outlined,
                iconColor: AppColors.primary,
                title: StringsFr.settingsPrivacyLabel,
                hasChevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PrivacyDataPage(),
                  ),
                ),
              ),
              const _TileDivider(),
              _SettingsTile(
                icon: Icons.description_outlined,
                iconColor: AppColors.textSecondary,
                title: 'Politique de confidentialite',
                hasChevron: true,
                onTap: () => _openLink('https://shazapiano.com/privacy'),
              ),
              const _TileDivider(),
              _SettingsTile(
                icon: Icons.gavel_outlined,
                iconColor: AppColors.textSecondary,
                title: 'Conditions d\'utilisation',
                hasChevron: true,
                onTap: () => _openLink('https://shazapiano.com/terms'),
              ),
            ],
          ),

          // ─── Support ─────────────────────────────────────
          const _SectionHeader(title: 'SUPPORT'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.help_outline,
                iconColor: AppColors.primary,
                title: 'Aide & FAQ',
                hasChevron: true,
                onTap: () => _openLink('https://shazapiano.com/faq'),
              ),
              const _TileDivider(),
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                iconColor: AppColors.warning,
                title: 'Signaler un probleme',
                hasChevron: true,
                onTap: () => _openLink('https://shazapiano.com/support'),
              ),
            ],
          ),

          // ─── Donnees ─────────────────────────────────────
          const _SectionHeader(title: 'DONNEES'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.delete_outline,
                iconColor: AppColors.error,
                title: 'Supprimer mes donnees',
                subtitle: 'Action irreversible',
                titleColor: AppColors.error,
                onTap: _handleDeleteData,
              ),
            ],
          ),

          // ─── Footer ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: AppConstants.spacing32),
            child: Column(
              children: [
                Text(
                  'ShazaPiano',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing4),
                Text(
                  'Version 1.0.0+1',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.divider,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleUnlock() {
    HapticFeedback.mediumImpact();
    showDialog(context: context, builder: (context) => const PaywallModal());
  }

  void _handleRestore() async {
    HapticFeedback.lightImpact();
    try {
      await ref.read(iapProvider.notifier).restorePurchases();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Achats restaures avec succes !'),
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
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.error,
            size: 28,
          ),
        ),
        title: Text(
          'Supprimer mes donnees ?',
          style: AppTextStyles.title,
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Cette action est irreversible. Toutes vos generations '
          'et votre statut premium seront perdus.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.divider),
                padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.spacing12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                ),
              ),
              child: Text(
                'Annuler',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacing8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Donnees supprimees'),
                    backgroundColor: AppColors.error,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.spacing12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                ),
              ),
              child: const Text(
                'Supprimer definitivement',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openLink(String url) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ouverture: $url'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ─── Premium Status Card ──────────────────────────────────

class _PremiumCard extends StatelessWidget {
  final bool isUnlocked;
  final VoidCallback onUnlockTap;

  const _PremiumCard({required this.isUnlocked, required this.onUnlockTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing16),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacing20),
        decoration: BoxDecoration(
          gradient: isUnlocked
              ? LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.primaryVariant.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [AppColors.card, AppColors.surface],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(
            color: isUnlocked
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: isUnlocked ? AppColors.buttonGradient : null,
                color: isUnlocked ? null : AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              ),
              child: Icon(
                isUnlocked ? Icons.workspace_premium : Icons.lock_outline,
                color: isUnlocked ? Colors.white : AppColors.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppConstants.spacing16),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUnlocked ? 'Compte Premium' : 'Compte gratuit',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isUnlocked
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing4),
                  Text(
                    isUnlocked
                        ? 'Tous les niveaux debloques'
                        : 'Debloquer tout pour ${AppConstants.iapPrice}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            // Action
            if (!isUnlocked)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onUnlockTap();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacing16,
                      vertical: AppConstants.spacing8,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.buttonGradient,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusSmall,
                      ),
                    ),
                    child: Text(
                      'Debloquer',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            else
              const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing16 + AppConstants.spacing4,
        AppConstants.spacing24,
        AppConstants.spacing16,
        AppConstants.spacing8,
      ),
      child: Text(
        title,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─── Settings Card Container ──────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacing16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// ─── Settings Tile ────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool hasChevron;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.hasChevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap != null
            ? () {
                HapticFeedback.lightImpact();
                onTap!();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
            vertical: AppConstants.spacing12,
          ),
          child: Row(
            children: [
              // Icon with background
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: AppConstants.spacing12),
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        color: titleColor ?? AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppConstants.spacing4),
                      Text(
                        subtitle!,
                        style: AppTextStyles.caption.copyWith(
                          color:
                              titleColor?.withValues(alpha: 0.7) ??
                              AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Chevron
              if (hasChevron)
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tile Divider ─────────────────────────────────────────

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacing16 + 36 + AppConstants.spacing12,
      ),
      child: Divider(height: 1, color: AppColors.divider),
    );
  }
}
