/// ShazaPiano - Page détail d'une musique gratuite
///
/// Single-screen layout: no scroll. Compact header, circular level selector
/// matching the home page stepper, piano roll preview, inline leaderboard.
///
/// UX rules: 44px touch targets, 12px min font, haptic, 4px grid, no scroll.
library;

import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import '../../state/leaderboard_provider.dart';
import '../leaderboard/leaderboard_page.dart';
import '../practice/practice_page.dart';

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
    final track = widget.track;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // ── App bar ──────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
      ),

      // ── Body: single screen, no scroll ──────────────────
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Track header ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing16,
              ),
              child: Column(
                children: [
                  // Title
                  Text(
                    track.title,
                    style: AppTextStyles.title.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppConstants.spacing4),
                  // Composer · difficulty · duration
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        track.composer,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      _dot(),
                      _DifficultyBadge(difficulty: track.difficulty),
                      _dot(),
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        track.durationFormatted,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacing16),

            // ── Level selector (circles) ──────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing24,
              ),
              child: _CircleLevelSelector(
                selectedLevel: _selectedLevel,
                onLevelChanged: (level) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedLevel = level);
                },
              ),
            ),
            const SizedBox(height: AppConstants.spacing16),

            // ── Piano roll preview (takes remaining space) ─
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing16,
                ),
                child: _PianoRollPreview(level: _selectedLevel),
              ),
            ),
            const SizedBox(height: AppConstants.spacing12),

            // ── Leaderboard inline ────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing16,
              ),
              child: _InlineLeaderboard(
                entries: leaderboard.entries,
                isLoading: leaderboard.isLoading,
                onTap: () => _openFullLeaderboard(context),
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
          ],
        ),
      ),

      // ── Bottom bar: Practice button ─────────────────────
      bottomNavigationBar: _BottomBar(
        onPracticeTap: _startPractice,
        onLeaderboardTap: () => _openFullLeaderboard(context),
      ),
    );
  }

  void _startPractice() {
    final track = widget.track;
    final previewUrl = track.previewUrls[_selectedLevel] ?? '';
    final videoUrl = track.fullVideoUrls[_selectedLevel] ?? '';
    final midiUrl = track.midiUrl ?? '';

    final levelResult = LevelResult(
      level: _selectedLevel,
      name: track.title,
      previewUrl: previewUrl,
      videoUrl: videoUrl,
      midiUrl: midiUrl,
      durationSec: track.durationSec.toDouble(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticePage(level: levelResult, freeTrackId: track.id),
      ),
    );
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

  static Widget _dot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing8),
      child: Text(
        '\u00b7',
        style: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.5),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─── Difficulty badge ─────────────────────────────────────

class _DifficultyBadge extends StatelessWidget {
  final String difficulty;

  const _DifficultyBadge({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      'easy' => AppColors.success,
      'medium' => AppColors.warning,
      'hard' => AppColors.error,
      _ => AppColors.textSecondary,
    };
    final label = switch (difficulty) {
      'easy' => 'Facile',
      'medium' => 'Moyen',
      'hard' => 'Difficile',
      _ => difficulty,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: AppConstants.fontSizeMin,
        ),
      ),
    );
  }
}

// ─── Circle level selector (matches home stepper) ─────────

class _CircleLevelSelector extends StatelessWidget {
  final int selectedLevel;
  final ValueChanged<int> onLevelChanged;

  const _CircleLevelSelector({
    required this.selectedLevel,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 1; i <= 4; i++) ...[
          _SelectableNode(
            level: i,
            label: AppConstants.levelNames[i - 1],
            isSelected: i == selectedLevel,
            onTap: () => onLevelChanged(i),
          ),
          if (i < 4)
            // Connector line
            Container(
              width: AppConstants.spacing20,
              height: 2,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: i < selectedLevel
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : AppColors.textSecondary.withValues(alpha: 0.3),
              ),
            ),
        ],
      ],
    );
  }
}

class _SelectableNode extends StatelessWidget {
  final int level;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectableNode({
    required this.level,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: AppConstants.touchTargetMin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circle
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.20)
                    : AppColors.divider,
                border: Border.all(color: color, width: isSelected ? 2.5 : 2.0),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '$level',
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing4),
            // Label
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                fontSize: AppConstants.fontSizeMin,
                color: color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Piano roll preview ───────────────────────────────────

class _PianoRollPreview extends StatelessWidget {
  final int level;

  const _PianoRollPreview({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard - 1),
        child: Stack(
          children: [
            // Falling note bars
            Positioned.fill(child: _NotesBars(level: level)),

            // Top fade (notes appearing)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.card,
                      AppColors.card.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom keyboard line
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.0),
                      AppColors.primary.withValues(alpha: 0.6),
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.6),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom glow
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Play overlay
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.25),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
            ),

            // Level + duration label at bottom
            Positioned(
              bottom: AppConstants.spacing12,
              left: AppConstants.spacing16,
              right: AppConstants.spacing16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Niveau $level',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${AppConstants.previewDurationSec}s \u00b7 Gratuit',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Stylized falling note bars to simulate a piano roll

class _NotesBars extends StatelessWidget {
  final int level;

  const _NotesBars({required this.level});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Generate pseudo-random but deterministic note positions based on level
        final rng = Random(level * 42);
        // More notes for higher levels
        final noteCount = 10 + level * 4;

        final notes = <Widget>[];
        for (int i = 0; i < noteCount; i++) {
          final left = rng.nextDouble() * (w - 20);
          final top = rng.nextDouble() * (h - 30) + 15;
          final noteWidth = 6.0 + rng.nextDouble() * 12;
          final noteHeight = 16.0 + rng.nextDouble() * 40;
          final opacity = 0.15 + rng.nextDouble() * 0.35;

          notes.add(
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: noteWidth,
                height: noteHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: AppColors.primary.withValues(alpha: opacity),
                ),
              ),
            ),
          );
        }

        return Stack(children: notes);
      },
    );
  }
}

// ─── Inline leaderboard (compact single row) ──────────────

class _InlineLeaderboard extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final bool isLoading;
  final VoidCallback onTap;

  const _InlineLeaderboard({
    required this.entries,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
            vertical: AppConstants.spacing12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppConstants.spacing8),
              Expanded(child: _buildContent()),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return Text(
        'Chargement...',
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      );
    }

    if (entries.isEmpty) {
      return Text(
        'Aucun score \u2014 Sois le premier !',
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      );
    }

    final top = entries.first;
    return Text(
      '\u{1f947} ${top.displayName} \u00b7 ${top.scoreFormatted}',
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ─── Bottom bar ──────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final VoidCallback onPracticeTap;
  final VoidCallback onLeaderboardTap;

  const _BottomBar({
    required this.onPracticeTap,
    required this.onLeaderboardTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing16,
        vertical: AppConstants.spacing12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Leaderboard icon
            IconButton(
              onPressed: onLeaderboardTap,
              icon: const Icon(
                Icons.emoji_events_outlined,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: AppConstants.spacing8),
            // Practice button
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    AppConstants.radiusButton,
                  ),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onPracticeTap();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppConstants.spacing12,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.buttonGradient,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusButton,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.piano, size: 20, color: Colors.white),
                        SizedBox(width: AppConstants.spacing8),
                        Text(
                          'PRACTICE MODE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
