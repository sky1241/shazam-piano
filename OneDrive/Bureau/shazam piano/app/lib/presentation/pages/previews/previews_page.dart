import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import '../../widgets/video_tile.dart';

class PreviewsPage extends StatefulWidget {
  final List<LevelResult> levels;
  final bool isUnlocked;

  const PreviewsPage({
    super.key,
    required this.levels,
    this.isUnlocked = false,
  });

  @override
  State<PreviewsPage> createState() => _PreviewsPageState();
}

class _PreviewsPageState extends State<PreviewsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Tes vidéos piano'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _handleShare,
          ),
        ],
      ),
      body: Column(
        children: [
          // Video grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                    key: level.keyGuess,
                    tempo: level.tempoGuess,
                    onTap: () => _handleVideoTileTap(level),
                  );
                },
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
    );
  }

  void _handleVideoTileTap(LevelResult level) {
    if (widget.isUnlocked) {
      // Navigate to full player
      // TODO: Navigate to PlayerPage with full video
    } else {
      // Show preview or paywall
      // TODO: Show preview player or paywall modal
      _showPaywallModal();
    }
  }

  void _handleUnlock() {
    // TODO: Trigger IAP purchase
    _showPaywallModal();
  }

  void _handleRestore() {
    // TODO: Restore purchases
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restauration des achats...'),
      ),
    );
  }

  void _handleShare() {
    // TODO: Share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Partage à venir...'),
      ),
    );
  }

  void _showPaywallModal() {
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
              Icon(
                Icons.lock_open,
                size: 48,
                color: AppColors.primary,
              ),
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
              }).toList(),
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

