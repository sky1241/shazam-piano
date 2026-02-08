/// ShazaPiano - Section "Musiques de la semaine" pour la HomePage
///
/// Affiche les 5 musiques en rotation avec timer et rang leaderboard.
///
/// NOT connected to existing code. Ready to be integrated.
/// Pour intégrer : ajouter WeeklyTracksSection() dans le body de HomePage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music/models.dart';
import '../../../core/music/rotation_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

class WeeklyTracksSection extends ConsumerWidget {
  /// Callback quand l'utilisateur tape sur une musique
  final void Function(FreeTrack track)? onTrackTap;

  /// Callback quand l'utilisateur tape sur le bouton vote
  final VoidCallback? onVoteTap;

  const WeeklyTracksSection({super.key, this.onTrackTap, this.onVoteTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rotation = RotationService.getCurrentRotation();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
          ),
          child: Row(
            children: [
              const Text('🎵', style: TextStyle(fontSize: 20)),
              const SizedBox(width: AppConstants.spacing8),
              Text('Musiques de la semaine', style: AppTextStyles.title),
              const Spacer(),
              // Vote button
              if (onVoteTap != null)
                GestureDetector(
                  onTap: onVoteTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacing8,
                      vertical: AppConstants.spacing4,
                    ),
                    margin: const EdgeInsets.only(right: AppConstants.spacing8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '🗳️ Voter',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              // Timer rotation
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing8,
                  vertical: AppConstants.spacing4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rotation.timeRemainingText,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing12),

        // Scroll horizontal des 5 musiques
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing12,
            ),
            itemCount: rotation.tracks.length,
            itemBuilder: (context, index) {
              final track = rotation.tracks[index];
              return _TrackCard(
                track: track,
                onTap: () => onTrackTap?.call(track),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Carte musique ───────────────────────────────────────

class _TrackCard extends StatelessWidget {
  final FreeTrack track;
  final VoidCallback? onTap;

  const _TrackCard({required this.track, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacing4),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacing12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icône play + difficulté
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    track.difficultyEmoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing8),

              // Titre
              Text(
                track.title,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),

              // Compositeur
              Text(
                track.composer,
                style: AppTextStyles.caption.copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const Spacer(),

              // Rang leaderboard + durée
              Row(
                children: [
                  // TODO: Remplacer par le vrai rang de l'utilisateur
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '🏆 —',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 9,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    track.durationFormatted,
                    style: AppTextStyles.caption.copyWith(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
