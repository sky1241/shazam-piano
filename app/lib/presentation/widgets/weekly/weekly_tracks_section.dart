/// ShazaPiano - Section "Cette semaine" pour la HomePage
///
/// Affiche les 6 musiques en rotation avec timer et rang leaderboard.
/// PageView par paires : chaque swipe = 2 nouvelles cartes.
///
/// UX rules applied: touch targets 44px, min font 12px, InkWell feedback,
/// haptic feedback, 4px grid spacing, visual hierarchy, page indicators.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music/models.dart';
import '../../../core/music/rotation_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

class WeeklyTracksSection extends ConsumerStatefulWidget {
  final void Function(FreeTrack track)? onTrackTap;
  final VoidCallback? onVoteTap;

  const WeeklyTracksSection({super.key, this.onTrackTap, this.onVoteTap});

  @override
  ConsumerState<WeeklyTracksSection> createState() =>
      _WeeklyTracksSectionState();
}

class _WeeklyTracksSectionState extends ConsumerState<WeeklyTracksSection> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rotation = RotationService.getCurrentRotation();

    // Group tracks into pages of 2
    final pages = <List<FreeTrack>>[];
    for (var i = 0; i < rotation.tracks.length; i += 2) {
      final end = (i + 2).clamp(0, rotation.tracks.length);
      pages.add(rotation.tracks.sublist(i, end));
    }
    final pageCount = pages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header — clean single row ─────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Cette semaine',
                style: AppTextStyles.title.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // Timer as subtle metadata, right-aligned
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing8,
                  vertical: AppConstants.spacing4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: AppConstants.spacing4),
                    Text(
                      rotation.timeRemainingText,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontSize: AppConstants.fontSizeMin,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing12),

        // ── PageView: 2 cards per page ──────────────────
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
            itemCount: pageCount,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, pageIndex) {
              final pageTracks = pages[pageIndex];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing16,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < pageTracks.length; i++) ...[
                      Expanded(
                        child: _TrackCard(
                          track: pageTracks[i],
                          onTap: () => widget.onTrackTap?.call(pageTracks[i]),
                        ),
                      ),
                      if (i < pageTracks.length - 1)
                        const SizedBox(width: AppConstants.spacing8),
                    ],
                    // Fill empty slot on last page if odd count
                    if (pageTracks.length == 1) ...[
                      const SizedBox(width: AppConstants.spacing8),
                      const Expanded(child: SizedBox()),
                    ],
                  ],
                ),
              );
            },
          ),
        ),

        // ── Page indicators ────────────────────────────────
        if (pageCount > 1) ...[
          const SizedBox(height: AppConstants.spacing12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pageCount, (i) {
              final isActive = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(
                  milliseconds: AppConstants.animMicroMs,
                ),
                width: isActive ? 20 : 8,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        ],

        // ── Vote CTA banner ──────────────────────────────────
        if (widget.onVoteTap != null) ...[
          const SizedBox(height: AppConstants.spacing12),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing16,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onVoteTap?.call();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacing16,
                    vertical: AppConstants.spacing12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusMedium,
                    ),
                    color: AppColors.primary.withValues(alpha: 0.08),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Glow icon
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacing12),
                      // Text
                      Expanded(
                        child: Text(
                          'Choisis la prochaine s\u00e9lection',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacing8),
                      // Chevron
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: AppColors.primary.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Carte musique ───────────────────────────────────────

class _TrackCard extends StatelessWidget {
  final FreeTrack track;
  final VoidCallback? onTap;

  const _TrackCard({required this.track, this.onTap});

  Color get _difficultyColor {
    switch (track.difficulty) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.warning;
      case 'hard':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String get _difficultyLabel {
    switch (track.difficulty) {
      case 'easy':
        return 'Facile';
      case 'medium':
        return 'Moyen';
      case 'hard':
        return 'Difficile';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            border: Border.all(color: AppColors.divider, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacing12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Play icon + difficulty pill
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMedium,
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacing8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _difficultyColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusButton,
                        ),
                      ),
                      child: Text(
                        _difficultyLabel,
                        style: AppTextStyles.caption.copyWith(
                          color: _difficultyColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

                // Pousse le compositeur en bas de la carte
                const Spacer(),

                // Compositeur + duree
                Text(
                  '${track.composer} \u00b7 ${track.durationFormatted}',
                  style: AppTextStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
