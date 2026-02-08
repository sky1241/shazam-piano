/// ShazaPiano - Page de vote communautaire
///
/// Permet aux utilisateurs de voter pour les musiques de la semaine prochaine.
///
/// NOT connected to existing code. Ready to be integrated.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../state/vote_provider.dart';

class VotePage extends ConsumerStatefulWidget {
  const VotePage({super.key});

  @override
  ConsumerState<VotePage> createState() => _VotePageState();
}

class _VotePageState extends ConsumerState<VotePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(voteProvider.notifier).loadCurrentVote();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voteProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          '🗳️ Vote semaine prochaine',
          style: AppTextStyles.title.copyWith(fontSize: 16),
        ),
        actions: [
          if (state.currentVote != null)
            Padding(
              padding: const EdgeInsets.only(right: AppConstants.spacing16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacing8,
                    vertical: AppConstants.spacing4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${state.userVotesRemaining}/3 votes',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : state.error != null
              ? Center(child: Text(state.error!, style: AppTextStyles.body))
              : state.currentVote == null
                  ? const Center(child: Text('Pas de vote en cours'))
                  : _VoteList(
                      candidates: state.sortedCandidates,
                      canVote: state.canVote,
                      isVoting: state.isVoting,
                      isVotingOpen: state.isVotingOpen,
                      onVote: (trackId) {
                        ref.read(voteProvider.notifier).vote(trackId);
                      },
                      onUnvote: (trackId) {
                        ref.read(voteProvider.notifier).unvote(trackId);
                      },
                    ),
    );
  }
}

class _VoteList extends StatelessWidget {
  final List<VoteCandidate> candidates;
  final bool canVote;
  final bool isVoting;
  final bool isVotingOpen;
  final void Function(String trackId) onVote;
  final void Function(String trackId) onUnvote;

  const _VoteList({
    required this.candidates,
    required this.canVote,
    required this.isVoting,
    required this.isVotingOpen,
    required this.onVote,
    required this.onUnvote,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header info
        if (!isVotingOpen)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacing12),
            color: AppColors.warning.withValues(alpha: 0.1),
            child: Text(
              'Le vote est terminé. Résultats bientôt !',
              style: AppTextStyles.body.copyWith(color: AppColors.warning),
              textAlign: TextAlign.center,
            ),
          ),

        // Liste des candidats
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppConstants.spacing16),
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return _VoteCard(
                candidate: candidate,
                rank: index + 1,
                canVote: canVote && !candidate.hasVoted,
                canUnvote: candidate.hasVoted && isVotingOpen,
                isVoting: isVoting,
                onVote: () => onVote(candidate.trackId),
                onUnvote: () => onUnvote(candidate.trackId),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VoteCard extends StatelessWidget {
  final VoteCandidate candidate;
  final int rank;
  final bool canVote;
  final bool canUnvote;
  final bool isVoting;
  final VoidCallback onVote;
  final VoidCallback onUnvote;

  const _VoteCard({
    required this.candidate,
    required this.rank,
    required this.canVote,
    required this.canUnvote,
    required this.isVoting,
    required this.onVote,
    required this.onUnvote,
  });

  String get _difficultyEmoji {
    switch (candidate.difficulty) {
      case 'easy':
        return '🟢';
      case 'medium':
        return '🟡';
      case 'hard':
        return '🔴';
      default:
        return '⚪';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing8),
      padding: const EdgeInsets.all(AppConstants.spacing12),
      decoration: BoxDecoration(
        color: candidate.hasVoted
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.card,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: candidate.hasVoted
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
            : Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Rang
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.bold,
                color: rank <= 5 ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacing8),

          // Difficulté
          Text(_difficultyEmoji),
          const SizedBox(width: AppConstants.spacing8),

          // Info musique
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  candidate.composer,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),

          // Compteur votes
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing8,
              vertical: AppConstants.spacing4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${candidate.voteCount}',
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacing8),

          // Bouton vote/unvote
          if (candidate.hasVoted && canUnvote)
            IconButton(
              onPressed: isVoting ? null : onUnvote,
              icon: const Icon(
                Icons.check_circle,
                color: AppColors.primary,
              ),
              tooltip: 'Annuler le vote',
            )
          else if (canVote)
            IconButton(
              onPressed: isVoting ? null : onVote,
              icon: Icon(
                Icons.radio_button_unchecked,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
              tooltip: 'Voter',
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
