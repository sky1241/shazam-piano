/// ShazaPiano - Leaderboard Provider (Riverpod)
///
/// Gère le leaderboard global par musique par semaine.
/// Utilise Firestore pour le stockage.
///
/// NOT connected to existing code. Ready to be integrated.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/music/models.dart';
import '../../core/music/rotation_service.dart';

// ─────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────

class LeaderboardState {
  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? userEntry;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final String? trackId;
  final int weekNumber;
  final int year;

  const LeaderboardState({
    this.entries = const [],
    this.userEntry,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.trackId,
    this.weekNumber = 0,
    this.year = 0,
  });

  LeaderboardState copyWith({
    List<LeaderboardEntry>? entries,
    LeaderboardEntry? userEntry,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    String? trackId,
    int? weekNumber,
    int? year,
    bool clearError = false,
    bool clearUserEntry = false,
  }) {
    return LeaderboardState(
      entries: entries ?? this.entries,
      userEntry: clearUserEntry ? null : userEntry ?? this.userEntry,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : error ?? this.error,
      trackId: trackId ?? this.trackId,
      weekNumber: weekNumber ?? this.weekNumber,
      year: year ?? this.year,
    );
  }

  bool get hasEntries => entries.isNotEmpty;
  bool get hasUserEntry => userEntry != null;
  int get totalPlayers => entries.length;
}

// ─────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────

final leaderboardProvider =
    StateNotifierProvider<LeaderboardNotifier, LeaderboardState>((ref) {
  return LeaderboardNotifier();
});

class LeaderboardNotifier extends StateNotifier<LeaderboardState> {
  LeaderboardNotifier() : super(const LeaderboardState());

  // Note: _docId will be used when Firestore integration is complete.
  // String _docId(String trackId) {
  //   final rotation = RotationService.getCurrentRotation();
  //   return '${trackId}_${rotation.weekNumber}_${rotation.year}';
  // }

  /// Charger le top 50 pour une musique
  Future<void> loadLeaderboard(String trackId) async {
    state = state.copyWith(isLoading: true, trackId: trackId, clearError: true);

    try {
      final rotation = RotationService.getCurrentRotation();

      // TODO: Remplacer par l'appel Firestore réel
      // final docId = _docId(trackId);
      // final snapshot = await FirebaseFirestore.instance
      //     .collection('leaderboards')
      //     .doc(docId)
      //     .collection('scores')
      //     .orderBy('score', descending: true)
      //     .limit(50)
      //     .get();
      //
      // final entries = snapshot.docs.asMap().entries.map((e) {
      //   return LeaderboardEntry.fromFirestore(
      //     e.value.id,
      //     e.value.data(),
      //     e.key + 1, // rank
      //   );
      // }).toList();

      // Placeholder : liste vide en attendant l'intégration Firestore
      final List<LeaderboardEntry> entries = [];

      state = state.copyWith(
        entries: entries,
        isLoading: false,
        weekNumber: rotation.weekNumber,
        year: rotation.year,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur chargement leaderboard: $e',
      );
    }
  }

  /// Soumettre un score au leaderboard
  Future<void> submitScore({
    required String trackId,
    required String uid,
    required String displayName,
    required int score,
    required int maxCombo,
    required int perfectCount,
    required int goodCount,
    required int okCount,
    required int missCount,
    required double accuracy,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final entry = LeaderboardEntry(
        uid: uid,
        displayName: displayName,
        score: score,
        maxCombo: maxCombo,
        perfectCount: perfectCount,
        goodCount: goodCount,
        okCount: okCount,
        missCount: missCount,
        accuracy: accuracy,
        timestamp: DateTime.now(),
      );

      // TODO: Remplacer par l'appel Firestore réel
      // final docId = _docId(trackId);
      // await FirebaseFirestore.instance
      //     .collection('leaderboards')
      //     .doc(docId)
      //     .collection('scores')
      //     .doc(uid)
      //     .set(entry.toFirestore(), SetOptions(merge: true));

      state = state.copyWith(
        isSubmitting: false,
        userEntry: entry,
      );

      // Recharger le leaderboard pour avoir le rang à jour
      await loadLeaderboard(trackId);
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Erreur soumission score: $e',
      );
    }
  }

  /// Charger le rang de l'utilisateur
  Future<void> loadUserRank(String trackId, String uid) async {
    try {
      // TODO: Remplacer par l'appel Firestore réel
      // final docId = _docId(trackId);
      // final userDoc = await FirebaseFirestore.instance
      //     .collection('leaderboards')
      //     .doc(docId)
      //     .collection('scores')
      //     .doc(uid)
      //     .get();
      //
      // if (userDoc.exists) {
      //   final userScore = userDoc.data()!['score'] as int;
      //   // Compter les scores supérieurs pour le rang
      //   final higherScores = await FirebaseFirestore.instance
      //       .collection('leaderboards')
      //       .doc(docId)
      //       .collection('scores')
      //       .where('score', isGreaterThan: userScore)
      //       .count()
      //       .get();
      //   final rank = higherScores.count + 1;
      //   state = state.copyWith(
      //     userEntry: LeaderboardEntry.fromFirestore(uid, userDoc.data()!, rank),
      //   );
      // }
    } catch (e) {
      // Silently fail - le rang est optionnel
    }
  }

  /// Reset (quand on change de musique)
  void reset() {
    state = const LeaderboardState();
  }
}
