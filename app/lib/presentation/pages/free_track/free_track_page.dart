/// ShazaPiano - Page détail d'une musique gratuite
///
/// Affiche : preview vidéo, leaderboard résumé, bouton Practice, vote.
///
/// NOT connected to existing code. Ready to be integrated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../state/leaderboard_provider.dart';
import '../leaderboard/leaderboard_page.dart';

class FreeTrackPage extends ConsumerStatefulWidget {
  final FreeTrack track;

  const FreeTrackPage({super.key, required this.track});

  @override
  ConsumerState<FreeTrackPage> createState() => _FreeTrackPageState();
}

class _FreeTrackPageState extends ConsumerState<FreeTrackPage> {
  int _selectedLevel = 1;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(leaderboardProvider.notifier).loadLeaderboard(widget.track.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final leaderboard = ref.watch(leaderboardProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // App bar avec image
          SliverAppBar(
            backgroundColor: AppColors.surface,
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.track.title,
                style: AppTextStyles.title.copyWith(fontSize: 14),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.3),
                      AppColors.bg,
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 40),
                      const Text('🎹', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 8),
                      Text(
                        widget.track.composer,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.track.difficultyEmoji),
                          const SizedBox(width: 4),
                          Text(
                            widget.track.difficulty.toUpperCase(),
                            style: AppTextStyles.caption,
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.track.durationFormatted,
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

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Sélection niveau ──────────────────────
                  _SectionHeader(title: 'Niveau', icon: Icons.stairs_rounded),
                  const SizedBox(height: AppConstants.spacing8),
                  _LevelSelector(
                    selectedLevel: _selectedLevel,
                    onLevelChanged: (level) {
                      setState(() => _selectedLevel = level);
                    },
                  ),
                  const SizedBox(height: AppConstants.spacing24),

                  // ─── Preview vidéo ─────────────────────────
                  _SectionHeader(
                    title: 'Preview',
                    icon: Icons.play_circle_outline,
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  _VideoPreviewPlaceholder(level: _selectedLevel),
                  const SizedBox(height: AppConstants.spacing24),

                  // ─── Leaderboard résumé ────────────────────
                  _SectionHeader(
                    title: 'Leaderboard',
                    icon: Icons.emoji_events_outlined,
                    trailing: TextButton(
                      onPressed: () => _openFullLeaderboard(context),
                      child: Text(
                        'Voir tout',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  _LeaderboardPreview(
                    entries: leaderboard.entries.take(5).toList(),
                    isLoading: leaderboard.isLoading,
                    userEntry: leaderboard.userEntry,
                  ),
                  const SizedBox(height: AppConstants.spacing32),
                ],
              ),
            ),
          ),
        ],
      ),

      // ─── Bottom bar : bouton Practice ──────────────────
      bottomNavigationBar: _BottomBar(
        trackId: widget.track.id,
        onPracticeTap: _startPractice,
        onLeaderboardTap: () => _openFullLeaderboard(context),
      ),
    );
  }

  void _startPractice() {
    // TODO: Naviguer vers PracticePage avec les expected notes
    // de cette musique gratuite et le niveau sélectionné.
    //
    // Navigator.push(context, MaterialPageRoute(
    //   builder: (_) => PracticePage(
    //     trackId: widget.track.id,
    //     level: _selectedLevel,
    //     expectedNotesUrl: widget.track.expectedNotesUrl,
    //   ),
    // ));
  }

  void _openFullLeaderboard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderboardPage(
          trackId: widget.track.id,
          trackTitle: widget.track.displayName,
        ),
      ),
    );
  }
}

// ─── Section Header ──────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppConstants.spacing8),
        Text(title, style: AppTextStyles.title),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

// ─── Sélecteur de niveau ─────────────────────────────────

class _LevelSelector extends StatelessWidget {
  final int selectedLevel;
  final ValueChanged<int> onLevelChanged;

  const _LevelSelector({
    required this.selectedLevel,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(AppConstants.totalLevels, (index) {
        final level = index + 1;
        final isSelected = level == selectedLevel;
        return Expanded(
          child: GestureDetector(
            onTap: () => onLevelChanged(level),
            child: Container(
              margin: EdgeInsets.only(
                right: index < 3 ? AppConstants.spacing4 : 0,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: AppConstants.spacing8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.divider,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '$level',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    AppConstants.levelNames[index],
                    style: AppTextStyles.caption.copyWith(fontSize: 9),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── Placeholder vidéo ───────────────────────────────────

class _VideoPreviewPlaceholder extends StatelessWidget {
  final int level;

  const _VideoPreviewPlaceholder({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text('Preview Niveau $level', style: AppTextStyles.body),
            Text(
              '${AppConstants.previewDurationSec}s • Gratuit',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Preview leaderboard (5 premiers) ────────────────────

class _LeaderboardPreview extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final bool isLoading;
  final LeaderboardEntry? userEntry;

  const _LeaderboardPreview({
    required this.entries,
    required this.isLoading,
    this.userEntry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppConstants.spacing16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        child: Center(
          child: Text(
            'Pas encore de scores. Soyez le premier !',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      ),
      child: Column(
        children: entries.asMap().entries.map((e) {
          final rank = e.key + 1;
          final entry = e.value;
          final isUser = userEntry?.uid == entry.uid;

          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing12,
              vertical: AppConstants.spacing8,
            ),
            decoration: BoxDecoration(
              border: e.key < entries.length - 1
                  ? const Border(
                      bottom: BorderSide(color: AppColors.divider, width: 0.5),
                    )
                  : null,
              color: isUser ? AppColors.primary.withValues(alpha: 0.1) : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '#$rank',
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing8),
                Expanded(
                  child: Text(
                    entry.displayName,
                    style: AppTextStyles.body.copyWith(fontSize: 13),
                    maxLines: 1,
                  ),
                ),
                Text(
                  entry.scoreFormatted,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Bottom bar ──────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final String trackId;
  final VoidCallback onPracticeTap;
  final VoidCallback onLeaderboardTap;

  const _BottomBar({
    required this.trackId,
    required this.onPracticeTap,
    required this.onLeaderboardTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacing16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Bouton leaderboard
            IconButton(
              onPressed: onLeaderboardTap,
              icon: const Icon(
                Icons.emoji_events_outlined,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: AppConstants.spacing8),
            // Bouton Practice
            Expanded(
              child: ElevatedButton(
                onPressed: onPracticeTap,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusButton,
                    ),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.piano, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'PRACTICE MODE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
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
}
