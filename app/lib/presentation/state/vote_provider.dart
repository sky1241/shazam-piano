/// ShazaPiano - Vote Provider (Riverpod)
///
/// Gère le système de vote communautaire pour choisir les musiques
/// de la semaine suivante.
///
/// NOT connected to existing code. Ready to be integrated.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/music/models.dart';
import '../../core/music/free_tracks_catalog.dart';
import '../../core/music/rotation_service.dart';

// ─────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────

class VoteState {
  final WeeklyVote? currentVote;
  final bool isLoading;
  final bool isVoting;
  final String? error;
  final int userVotesRemaining;

  const VoteState({
    this.currentVote,
    this.isLoading = false,
    this.isVoting = false,
    this.error,
    this.userVotesRemaining = 3,
  });

  VoteState copyWith({
    WeeklyVote? currentVote,
    bool? isLoading,
    bool? isVoting,
    String? error,
    int? userVotesRemaining,
    bool clearError = false,
  }) {
    return VoteState(
      currentVote: currentVote ?? this.currentVote,
      isLoading: isLoading ?? this.isLoading,
      isVoting: isVoting ?? this.isVoting,
      error: clearError ? null : error ?? this.error,
      userVotesRemaining: userVotesRemaining ?? this.userVotesRemaining,
    );
  }

  bool get isVotingOpen => currentVote?.isVotingOpen ?? false;
  bool get canVote => userVotesRemaining > 0 && isVotingOpen;
  List<VoteCandidate> get candidates => currentVote?.candidates ?? [];
  List<VoteCandidate> get sortedCandidates {
    final list = List<VoteCandidate>.from(candidates);
    list.sort((a, b) => b.voteCount.compareTo(a.voteCount));
    return list;
  }
}

// ─────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────

final voteProvider =
    StateNotifierProvider<VoteNotifier, VoteState>((ref) {
  return VoteNotifier();
});

class VoteNotifier extends StateNotifier<VoteState> {
  VoteNotifier() : super(const VoteState());

  /// Charger le vote de la semaine courante
  ///
  /// Les candidats sont les musiques qui NE SONT PAS dans la rotation
  /// courante (pour éviter les doublons semaine suivante).
  Future<void> loadCurrentVote() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final rotation = RotationService.getCurrentRotation();
      final currentTrackIds = rotation.tracks.map((t) => t.id).toSet();

      // Candidats = musiques pas dans la rotation courante
      final allTracks = FreeTracksCatalog.allTracks;
      final candidateTracks = allTracks
          .where((t) => !currentTrackIds.contains(t.id))
          .toList();

      // Prendre 8 candidats max (shuffle déterministe basé sur semaine+1)
      // pour que la liste des candidats soit stable toute la semaine
      final seed = rotation.year * 100 + rotation.weekNumber + 1;
      final shuffled = List<FreeTrack>.from(candidateTracks);
      shuffled.shuffle(Random(seed));
      final selected = shuffled.take(8).toList();

      final candidates = selected
          .map((t) => VoteCandidate(
                trackId: t.id,
                title: t.title,
                composer: t.composer,
                difficulty: t.difficulty,
                voteCount: 0,
                hasVoted: false,
              ))
          .toList();

      // TODO: Charger les votes réels depuis Firestore
      // final voteDocId = 'vote_${rotation.weekNumber}_${rotation.year}';
      // final voteDoc = await FirebaseFirestore.instance
      //     .collection('votes')
      //     .doc(voteDocId)
      //     .get();
      // ... merger les voteCount réels avec les candidats

      // TODO: Charger les votes de l'utilisateur
      // final userVotesDoc = await FirebaseFirestore.instance
      //     .collection('votes')
      //     .doc(voteDocId)
      //     .collection('user_votes')
      //     .doc(currentUserId)
      //     .get();
      // ... déterminer userVotesRemaining et hasVoted

      // Fin du vote = vendredi 18h (laisse le weekend pour la génération)
      final votingEnds = rotation.startsAt
          .add(const Duration(days: 4, hours: 18));

      state = state.copyWith(
        currentVote: WeeklyVote(
          weekNumber: rotation.weekNumber,
          year: rotation.year,
          candidates: candidates,
          maxVotes: 3,
          votingEndsAt: votingEnds,
        ),
        isLoading: false,
        userVotesRemaining: 3,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur chargement vote: $e',
      );
    }
  }

  /// Voter pour une musique
  Future<void> vote(String trackId) async {
    if (!state.canVote) return;

    state = state.copyWith(isVoting: true, clearError: true);

    try {
      // TODO: Écrire le vote dans Firestore
      // final voteDocId = 'vote_${state.currentVote!.weekNumber}_${state.currentVote!.year}';
      // await FirebaseFirestore.instance
      //     .collection('votes')
      //     .doc(voteDocId)
      //     .update({'$trackId': FieldValue.increment(1)});
      //
      // await FirebaseFirestore.instance
      //     .collection('votes')
      //     .doc(voteDocId)
      //     .collection('user_votes')
      //     .doc(currentUserId)
      //     .set({trackId: true}, SetOptions(merge: true));

      // Mettre à jour le state localement
      if (state.currentVote != null) {
        final updatedCandidates = state.currentVote!.candidates.map((c) {
          if (c.trackId == trackId) {
            return c.copyWith(
              voteCount: c.voteCount + 1,
              hasVoted: true,
            );
          }
          return c;
        }).toList();

        state = state.copyWith(
          currentVote: WeeklyVote(
            weekNumber: state.currentVote!.weekNumber,
            year: state.currentVote!.year,
            candidates: updatedCandidates,
            maxVotes: state.currentVote!.maxVotes,
            votingEndsAt: state.currentVote!.votingEndsAt,
          ),
          isVoting: false,
          userVotesRemaining: state.userVotesRemaining - 1,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isVoting: false,
        error: 'Erreur vote: $e',
      );
    }
  }

  /// Annuler un vote
  Future<void> unvote(String trackId) async {
    // TODO: Similaire à vote() mais en décrémentant
    if (state.currentVote != null) {
      final updatedCandidates = state.currentVote!.candidates.map((c) {
        if (c.trackId == trackId && c.hasVoted) {
          return c.copyWith(
            voteCount: c.voteCount - 1,
            hasVoted: false,
          );
        }
        return c;
      }).toList();

      state = state.copyWith(
        currentVote: WeeklyVote(
          weekNumber: state.currentVote!.weekNumber,
          year: state.currentVote!.year,
          candidates: updatedCandidates,
          maxVotes: state.currentVote!.maxVotes,
          votingEndsAt: state.currentVote!.votingEndsAt,
        ),
        userVotesRemaining: state.userVotesRemaining + 1,
      );
    }
  }
}
