import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

/// Video preview tile for level
class VideoTile extends StatelessWidget {
  final int level;
  final String levelName;
  final String? previewUrl;
  final String? thumbnailUrl;
  final bool isUnlocked;
  final bool isLoading;
  final String? videoKey;
  final int? tempo;
  final VoidCallback? onTap;

  const VideoTile({
    super.key,
    required this.level,
    required this.levelName,
    this.previewUrl,
    this.thumbnailUrl,
    this.isUnlocked = false,
    this.isLoading = false,
    this.videoKey,
    this.tempo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        child: Stack(
          children: [
            // Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail/Preview area
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppConstants.radiusCard),
                        topRight: Radius.circular(AppConstants.radiusCard),
                      ),
                    ),
                    child: _buildPreviewArea(),
                  ),
                ),

                // Info section
                Padding(
                  padding: const EdgeInsets.all(AppConstants.spacing12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Niveau $level',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacing4),
                      Text(
                        levelName,
                        style: AppTextStyles.title.copyWith(fontSize: 16),
                      ),
                      if (key != null || tempo != null) ...[
                        const SizedBox(height: AppConstants.spacing8),
                        Row(
                          children: [
                            if (key != null) ...[
                              Icon(
                                Icons.music_note,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(videoKey!, style: AppTextStyles.caption),
                              const SizedBox(width: AppConstants.spacing12),
                            ],
                            if (tempo != null) ...[
                              Icon(
                                Icons.speed,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text('$tempo BPM', style: AppTextStyles.caption),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Badge overlay
            if (!isUnlocked)
              Positioned(
                top: AppConstants.spacing8,
                right: AppConstants.spacing8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacing8,
                    vertical: AppConstants.spacing4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusCard,
                    ),
                  ),
                  child: Text(
                    '16s preview',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            // Loading overlay
            if (isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bg.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusCard,
                    ),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewArea() {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (thumbnailUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppConstants.radiusCard),
          topRight: Radius.circular(AppConstants.radiusCard),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.play_circle_filled,
                size: 48,
                color: AppColors.primary,
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                              (progress.expectedTotalBytes ?? 1)
                        : null,
                  ),
                );
              },
            ),
            const Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.play_circle_filled,
                size: 48,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Center(child: Icon(Icons.piano, size: 48, color: AppColors.divider));
  }
}
