// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import '../../widgets/video_tile.dart';
import '../../widgets/paywall_modal.dart';
import '../../state/iap_provider.dart';
import '../player/player_page.dart';

class PreviewsPage extends ConsumerStatefulWidget {
  final List<LevelResult> levels;
  final bool isUnlocked;
  final String? trackTitle;
  final String? trackArtist;

  const PreviewsPage({
    super.key,
    required this.levels,
    this.isUnlocked = false,
    this.trackTitle,
    this.trackArtist,
  });

  @override
  ConsumerState<PreviewsPage> createState() => _PreviewsPageState();
}

class _PreviewsPageState extends ConsumerState<PreviewsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tes videos piano'),
            if (widget.trackTitle != null)
              Text(widget.trackTitle!, style: AppTextStyles.caption),
            if (widget.trackArtist != null)
              Text(
                widget.trackArtist!,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _handleShare),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Video grid
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spacing16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppConstants.spacing16,
                          mainAxisSpacing: AppConstants.spacing16,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: widget.levels.length,
                    itemBuilder: (context, index) {
                      final level = widget.levels[index];

                      return VideoTile(
                        level: level.level,
                        levelName: level.name,
                        previewUrl: level.previewUrl,
                        isUnlocked: widget.isUnlocked,
                        isLoading: level.isPending,
                        videoKey: level.keyGuess,
                        tempo: level.tempoGuess,
                        onTap: () => _handleVideoTileTap(level),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Unlock button
            if (!widget.isUnlocked)
              Container(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.divider, width: 1),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Text(
                        'Débloquer les 4 niveaux',
                        style: AppTextStyles.title,
                      ),
                      const SizedBox(height: AppConstants.spacing8),
                      Text(
                        'Accès complet à toutes les vidéos',
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(height: AppConstants.spacing16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleUnlock,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppConstants.spacing16,
                            ),
                          ),
                          child: Text(
                            'Acheter pour ${AppConstants.iapPrice}',
                            style: AppTextStyles.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _handleRestore,
                        child: Text(
                          'Restaurer l\'achat',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleVideoTileTap(LevelResult level) {
    if (!level.isSuccess || level.previewUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune video disponible pour ce niveau.'),
        ),
      );
      return;
    }

    // Navigate to Player (will handle unlock status internally)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlayerPage(
          level: level,
          isUnlocked: widget.isUnlocked,
          trackTitle: widget.trackTitle,
          trackArtist: widget.trackArtist,
        ),
      ),
    );
  }

  Future<void> _handleUnlock() async {
    // Show paywall modal
    await showDialog<bool>(
      context: context,
      builder: (context) => const PaywallModal(),
    );

    // Check if unlocked after modal closes
    final iapState = ref.read(iapProvider);
    if (iapState.isUnlocked && mounted) {
      setState(() {
        // Force rebuild with unlocked status
      });
    }
  }

  void _handleRestore() async {
    try {
      await ref.read(iapProvider.notifier).restorePurchases();

      final iapState = ref.read(iapProvider);

      if (iapState.isUnlocked && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Achat restauré avec succès !'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          // Force rebuild with unlocked status
        });
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
            content: Text('Erreur: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleShare() {
    // TODO: Share functionality
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Partage à venir...')));
  }

  Future<bool?> _showPaywallModal() {
    return showDialog<bool>(
      context: context,
      builder: (context) => const PaywallModal(),
    );
  }

  void _showPaywallModalOld() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusCard),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacing24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_open, size: 48, color: AppColors.primary),
              const SizedBox(height: AppConstants.spacing16),
              Text(
                'Tout débloquer pour ${AppConstants.iapPrice}',
                style: AppTextStyles.display.copyWith(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacing16),
              ...AppConstants.levelNames.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppConstants.spacing4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 20,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppConstants.spacing8),
                      Text(
                        'Niveau ${entry.key + 1}: ${entry.value}',
                        style: AppTextStyles.body,
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: AppConstants.spacing24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: Trigger IAP
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppConstants.spacing16,
                    ),
                  ),
                  child: Text(
                    'Acheter maintenant (${AppConstants.iapPrice})',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Plus tard',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
