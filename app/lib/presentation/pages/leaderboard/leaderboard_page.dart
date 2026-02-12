/// ShazaPiano - Leaderboard Page
///
/// Affiche le classement global d'une musique pour la semaine courante.
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

class LeaderboardPage extends ConsumerStatefulWidget {
  final String trackId;
  final String trackTitle;

  const LeaderboardPage({
    super.key,
    required this.trackId,
    required this.trackTitle,
  });

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  @override
  void initState() {
    super.initState();
    // Charger le leaderboard au montage
    Future.microtask(() {
      ref.read(leaderboardProvider.notifier).loadLeaderboard(widget.trackId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leaderboardProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🏆 Leaderboard',
              style: AppTextStyles.title.copyWith(fontSize: 16),
            ),
            Text(widget.trackTitle, style: AppTextStyles.caption),
          ],
        ),
        actions: [
          // Timer rotation
          Padding(
            padding: const EdgeInsets.only(right: AppConstants.spacing16),
            child: Center(child: _RotationTimer()),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : state.error != null
          ? _ErrorView(
              error: state.error!,
              onRetry: () => ref
                  .read(leaderboardProvider.notifier)
                  .loadLeaderboard(widget.trackId),
            )
          : state.hasEntries
          ? _LeaderboardList(entries: state.entries, userEntry: state.userEntry)
          : _EmptyLeaderboard(),
    );
  }
}

// ─── Timer Rotation ──────────────────────────────────────

class _RotationTimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // TODO: Utiliser un StreamBuilder ou Timer pour mettre à jour en temps réel
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing12,
        vertical: AppConstants.spacing4,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: AppConstants.spacing4),
          Text(
            '3j 14h', // TODO: dynamique via RotationService
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Liste du Leaderboard ────────────────────────────────

class _LeaderboardList extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? userEntry;

  const _LeaderboardList({required this.entries, this.userEntry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top 3 podium
        if (entries.length >= 3) _Podium(top3: entries.take(3).toList()),

        // User rank highlight
        if (userEntry != null) _UserRankCard(entry: userEntry!),

        // Reste du classement
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              // TODO: reload via ref
            },
            color: AppColors.primary,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing16,
                vertical: AppConstants.spacing8,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final isUser = userEntry?.uid == entry.uid;
                return _LeaderboardRow(
                  entry: entry,
                  rank: index + 1,
                  isHighlighted: isUser,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Podium Top 3 ────────────────────────────────────────

class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> top3;

  const _Podium({required this.top3});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // #2
          if (top3.length > 1) _PodiumItem(entry: top3[1], rank: 2, height: 80),
          // #1
          _PodiumItem(entry: top3[0], rank: 1, height: 100),
          // #3
          if (top3.length > 2) _PodiumItem(entry: top3[2], rank: 3, height: 60),
        ],
      ),
    );
  }
}

class _PodiumItem extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;
  final double height;

  const _PodiumItem({
    required this.entry,
    required this.rank,
    required this.height,
  });

  String get _medal {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '';
    }
  }

  Color get _color {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_medal, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: AppConstants.spacing4),
        // Avatar circle
        CircleAvatar(
          radius: 20,
          backgroundColor: _color.withValues(alpha: 0.3),
          child: Text(
            entry.displayName.isNotEmpty
                ? entry.displayName[0].toUpperCase()
                : '?',
            style: AppTextStyles.title.copyWith(color: _color),
          ),
        ),
        const SizedBox(height: AppConstants.spacing4),
        Text(
          entry.displayName,
          style: AppTextStyles.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          entry.scoreFormatted,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.bold,
            color: _color,
          ),
        ),
        // Barre podium
        Container(
          width: 60,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _color.withValues(alpha: 0.4),
                _color.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Center(
            child: Text(
              '#$rank',
              style: AppTextStyles.title.copyWith(color: _color),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Ligne du classement ─────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;
  final bool isHighlighted;

  const _LeaderboardRow({
    required this.entry,
    required this.rank,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing12,
        vertical: AppConstants.spacing8,
      ),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: isHighlighted
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          // Rang
          SizedBox(
            width: 32,
            child: Text(
              '#$rank',
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.bold,
                color: rank <= 3 ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
          // Avatar
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.surface,
            child: Text(
              entry.displayName.isNotEmpty
                  ? entry.displayName[0].toUpperCase()
                  : '?',
              style: AppTextStyles.caption,
            ),
          ),
          const SizedBox(width: AppConstants.spacing8),
          // Nom
          Expanded(
            child: Text(
              isHighlighted ? '${entry.displayName} (Vous)' : entry.displayName,
              style: AppTextStyles.body.copyWith(
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Combo
          Text(
            entry.comboText,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.warning,
              fontSize: AppConstants.fontSizeMin,
            ),
          ),
          const SizedBox(width: AppConstants.spacing12),
          // Accuracy
          Text(entry.accuracyText, style: AppTextStyles.caption),
          const SizedBox(width: AppConstants.spacing12),
          // Score
          Text(
            entry.scoreFormatted,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.bold,
              color: isHighlighted ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── User rank card ──────────────────────────────────────

class _UserRankCard extends StatelessWidget {
  final LeaderboardEntry entry;

  const _UserRankCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing16,
        vertical: AppConstants.spacing8,
      ),
      padding: const EdgeInsets.all(AppConstants.spacing12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.2),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text('🏆', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: AppConstants.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Votre classement', style: AppTextStyles.caption),
                Text(
                  '#${entry.rank} — ${entry.scoreFormatted} pts',
                  style: AppTextStyles.title.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.comboText,
                style: AppTextStyles.caption.copyWith(color: AppColors.warning),
              ),
              Text(entry.accuracyText, style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Leaderboard vide ────────────────────────────────────

class _EmptyLeaderboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 48)),
            const SizedBox(height: AppConstants.spacing16),
            Text(
              'Aucun score cette semaine',
              style: AppTextStyles.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Soyez le premier à jouer et\nà apparaître au classement !',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Vue d'erreur ────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppConstants.spacing16),
            Text(error, style: AppTextStyles.body, textAlign: TextAlign.center),
            const SizedBox(height: AppConstants.spacing16),
            ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
