import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/process_response.dart';

class ResultBottomSheet extends StatelessWidget {
  final ProcessResponse result;

  const ResultBottomSheet({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final hasId =
        result.identifiedTitle != null || result.identifiedArtist != null;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusCard),
        ),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.music_note, color: AppColors.primary),
              SizedBox(width: AppConstants.spacing8),
              Text('Analyse terminée', style: AppTextStyles.title),
            ],
          ),
          const SizedBox(height: AppConstants.spacing12),
          if (hasId) ...[
            Text(
              result.identifiedTitle ?? 'Titre inconnu',
              style: AppTextStyles.display.copyWith(fontSize: 20),
            ),
            const SizedBox(height: AppConstants.spacing4),
            Text(
              result.identifiedArtist ?? 'Artiste inconnu',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (result.identifiedAlbum != null) ...[
              const SizedBox(height: AppConstants.spacing4),
              Text(result.identifiedAlbum!, style: AppTextStyles.caption),
            ],
          ] else ...[
            Text(
              'Aucune identification trouvée',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spacing16),
          Text(
            'Niveaux générés : ${result.successCount}/${result.levels.length}',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppConstants.spacing16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continuer'),
            ),
          ),
        ],
      ),
    );
  }
}
