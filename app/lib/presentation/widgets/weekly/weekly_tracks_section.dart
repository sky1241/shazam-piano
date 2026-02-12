/// ShazaPiano - Section "Musiques de la semaine" pour la HomePage
///
/// Affiche les 5 musiques en rotation avec timer et rang leaderboard.
///
/// UX rules applied: touch targets 44px, min font 12px, InkWell feedback,
/// haptic feedback, 4px grid spacing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              Expanded(
                child: Text(
                  'Musiques de la semaine',
                  style: AppTextStyles.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppConstants.spacing8),
              // Vote button — 44px min touch target
              if (onVoteTap != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppConstants.spacing4),
                  child: Material(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onVoteTap?.call();
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppConstants.touchTargetMin,
                          minWidth: AppConstants.touchTargetMin,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.spacing12,
                            vertical: AppConstants.spacing8,
                          ),
                          child: Text(
                            '🗳️ Voter',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Timer rotation
              Container(
                constraints: const BoxConstraints(
                  minHeight: AppConstants.touchTargetMin,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing12,
                  vertical: AppConstants.spacing8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                ),
                child: Text(
                  rotation.timeRemainingText,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
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
          height: 172,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing4),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap?.call();
          },
          child: Container(
            width: 136,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              border: Border.all(color: AppColors.divider, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacing12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icone play + difficulte
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        track.difficultyEmoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacing8),

                  // Titre
                  Text(
                    track.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppConstants.spacing4),

                  // Compositeur — min 12px
                  Text(
                    track.composer,
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const Spacer(),

                  // Rang leaderboard + duree — min 12px
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacing8,
                          vertical: AppConstants.spacing4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppConstants.spacing4),
                        ),
                        child: Text(
                          '🏆 —',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        track.durationFormatted,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
