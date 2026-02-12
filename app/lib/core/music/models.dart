/// ShazaPiano - Music models for weekly rotation & leaderboard
///
/// NOT connected to existing code. Ready to be integrated.
library;

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────
// Free Track (musique du pool gratuit)
// ─────────────────────────────────────────────────────────

@immutable
class FreeTrack {
  final String id;
  final String title;
  final String composer;
  final String difficulty; // 'easy', 'medium', 'hard'
  final int durationSec;
  final String? coverAssetPath; // ex: 'assets/covers/fur_elise.jpg'

  /// URLs pré-générées sur Firebase Storage (4 niveaux)
  final Map<int, String> previewUrls; // preview 12s par niveau
  final Map<int, String> fullVideoUrls; // vidéos complètes par niveau
  final String? midiUrl; // MIDI pour practice mode
  final String? expectedNotesUrl; // JSON notes attendues pour practice

  const FreeTrack({
    required this.id,
    required this.title,
    required this.composer,
    required this.difficulty,
    required this.durationSec,
    this.coverAssetPath,
    this.previewUrls = const {},
    this.fullVideoUrls = const {},
    this.midiUrl,
    this.expectedNotesUrl,
  });

  /// Nom affiché : "Für Elise - Beethoven"
  String get displayName => '$title - $composer';

  /// Icône difficulté
  String get difficultyEmoji {
    switch (difficulty) {
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

  /// Durée formatée : "2:30"
  String get durationFormatted {
    final min = durationSec ~/ 60;
    final sec = durationSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────
// Weekly Rotation
// ─────────────────────────────────────────────────────────

@immutable
class WeeklyRotation {
  final int weekNumber;
  final int year;
  final List<FreeTrack> tracks; // exactement 5
  final DateTime startsAt;
  final DateTime endsAt;

  const WeeklyRotation({
    required this.weekNumber,
    required this.year,
    required this.tracks,
    required this.startsAt,
    required this.endsAt,
  });

  /// Temps restant avant la prochaine rotation
  Duration get timeRemaining {
    final now = DateTime.now();
    if (now.isAfter(endsAt)) return Duration.zero;
    return endsAt.difference(now);
  }

  /// Texte formaté : "Nouveau dans 3j"
  String get timeRemainingText {
    final remaining = timeRemaining;
    if (remaining == Duration.zero) return 'Nouveau !';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    if (days > 0) return 'Nouveau dans ${days}j';
    final minutes = remaining.inMinutes % 60;
    return 'Nouveau dans ${hours}h${minutes > 0 ? ' ${minutes}m' : ''}';
  }

  /// Est-ce que la rotation est active ?
  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }
}

// ─────────────────────────────────────────────────────────
// Leaderboard Entry
// ─────────────────────────────────────────────────────────

@immutable
class LeaderboardEntry {
  final String uid;
  final String displayName;
  final int score;
  final int maxCombo;
  final int perfectCount;
  final int goodCount;
  final int okCount;
  final int missCount;
  final double accuracy;
  final DateTime timestamp;
  final int rank; // calculé côté client ou serveur

  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.score,
    required this.maxCombo,
    required this.perfectCount,
    this.goodCount = 0,
    this.okCount = 0,
    this.missCount = 0,
    required this.accuracy,
    required this.timestamp,
    this.rank = 0,
  });

  /// Total notes jouées
  int get totalNotes => perfectCount + goodCount + okCount + missCount;

  /// Texte score formaté : "45,200"
  String get scoreFormatted {
    if (score >= 1000) {
      final thousands = score ~/ 1000;
      final remainder = score % 1000;
      return '$thousands,${remainder.toString().padLeft(3, '0')}';
    }
    return score.toString();
  }

  /// Texte accuracy : "94%"
  String get accuracyText => '${(accuracy * 100).toInt()}%';

  /// Texte combo : "x48"
  String get comboText => 'x$maxCombo';

  /// Depuis JSON Firestore
  factory LeaderboardEntry.fromFirestore(
    String docId,
    Map<String, dynamic> data,
    int rank,
  ) {
    return LeaderboardEntry(
      uid: docId,
      displayName: data['displayName'] as String? ?? 'Anonymous',
      score: data['score'] as int? ?? 0,
      maxCombo: data['maxCombo'] as int? ?? 0,
      perfectCount: data['perfectCount'] as int? ?? 0,
      goodCount: data['goodCount'] as int? ?? 0,
      okCount: data['okCount'] as int? ?? 0,
      missCount: data['missCount'] as int? ?? 0,
      accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as dynamic).toDate()
          : DateTime.now(),
      rank: rank,
    );
  }

  /// Vers JSON pour Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'score': score,
      'maxCombo': maxCombo,
      'perfectCount': perfectCount,
      'goodCount': goodCount,
      'okCount': okCount,
      'missCount': missCount,
      'accuracy': accuracy,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

// ─────────────────────────────────────────────────────────
// Vote (système de vote communautaire)
// ─────────────────────────────────────────────────────────

@immutable
class VoteCandidate {
  final String trackId;
  final String title;
  final String composer;
  final String difficulty;
  final int voteCount;
  final bool hasVoted; // si l'utilisateur courant a voté pour celle-ci

  const VoteCandidate({
    required this.trackId,
    required this.title,
    required this.composer,
    required this.difficulty,
    this.voteCount = 0,
    this.hasVoted = false,
  });

  VoteCandidate copyWith({int? voteCount, bool? hasVoted}) {
    return VoteCandidate(
      trackId: trackId,
      title: title,
      composer: composer,
      difficulty: difficulty,
      voteCount: voteCount ?? this.voteCount,
      hasVoted: hasVoted ?? this.hasVoted,
    );
  }
}

@immutable
class WeeklyVote {
  final int weekNumber;
  final int year;
  final List<VoteCandidate> candidates; // 5-8 candidats
  final int maxVotes; // nombre max de votes par user (1 ou 3)
  final DateTime votingEndsAt;

  const WeeklyVote({
    required this.weekNumber,
    required this.year,
    required this.candidates,
    this.maxVotes = 3,
    required this.votingEndsAt,
  });

  bool get isVotingOpen => DateTime.now().isBefore(votingEndsAt);

  Duration get timeRemaining {
    final now = DateTime.now();
    if (now.isAfter(votingEndsAt)) return Duration.zero;
    return votingEndsAt.difference(now);
  }
}
