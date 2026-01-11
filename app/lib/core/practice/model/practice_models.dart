import 'package:uuid/uuid.dart';

/// Hit grade based on timing accuracy (onset)
enum HitGrade { perfect, good, ok, miss, wrong }

/// Source of a played note event
enum NoteSource { microphone, midi }

/// Expected note (from sheet music / MIDI file)
class ExpectedNote {
  const ExpectedNote({
    required this.index,
    required this.midi,
    required this.tExpectedMs,
    this.durationMs,
  });

  final int index;
  final int midi; // MIDI note number (0-127)
  final double tExpectedMs; // Expected onset time in milliseconds
  final double? durationMs; // Expected duration (null if not available)

  @override
  String toString() =>
      'ExpectedNote(idx=$index, midi=$midi, t=${tExpectedMs.toStringAsFixed(1)}ms, '
      'dur=${durationMs?.toStringAsFixed(1) ?? "null"}ms)';
}

/// Event of a note played by the user
class PlayedNoteEvent {
  PlayedNoteEvent({
    String? id,
    required this.midi,
    required this.tPlayedMs,
    this.durationMs,
    required this.source,
  }) : id = id ?? const Uuid().v4();

  final String id; // Unique ID for exclusivity tracking
  final int midi; // MIDI note number detected
  final double tPlayedMs; // Time when note was played (ms)
  final double? durationMs; // Duration held (null if not available)
  final NoteSource source; // mic or midi

  @override
  String toString() =>
      'PlayedNoteEvent(id=${id.substring(0, 8)}, midi=$midi, t=${tPlayedMs.toStringAsFixed(1)}ms, '
      'dur=${durationMs?.toStringAsFixed(1) ?? "null"}ms, src=$source)';
}

/// Match candidate between expected note and played event
class MatchCandidate {
  const MatchCandidate({
    required this.expectedIndex,
    required this.playedId,
    required this.dtMs,
  });

  final int expectedIndex; // Index of expected note
  final String playedId; // ID of played event
  final double dtMs; // Time difference (played - expected) in ms

  double get absDtMs => dtMs.abs();

  @override
  String toString() =>
      'MatchCandidate(expectedIdx=$expectedIndex, playedId=${playedId.substring(0, 8)}, '
      'dt=${dtMs.toStringAsFixed(1)}ms)';
}

/// Resolution of an expected note (after matching)
class NoteResolution {
  const NoteResolution({
    required this.expectedIndex,
    required this.grade,
    this.dtMs,
    required this.pointsAdded,
    this.matchedPlayedId,
    this.sustainFactor = 1.0,
  });

  final int expectedIndex;
  final HitGrade grade;
  final double? dtMs; // null for miss/wrong (no match)
  final int pointsAdded; // Points added to total score
  final String? matchedPlayedId; // null for miss (no match found)
  final double sustainFactor; // 0.7-1.0 (1.0 if duration not available)

  @override
  String toString() =>
      'NoteResolution(expectedIdx=$expectedIndex, grade=$grade, '
      'dt=${dtMs?.toStringAsFixed(1) ?? "null"}ms, pts=$pointsAdded, '
      'matchedId=${matchedPlayedId?.substring(0, 8) ?? "null"}, sustain=${sustainFactor.toStringAsFixed(2)})';
}

/// Scoring state (updated in real-time during practice)
class PracticeScoringState {
  PracticeScoringState({
    this.totalScore = 0,
    this.combo = 0,
    this.maxCombo = 0,
    this.perfectCount = 0,
    this.goodCount = 0,
    this.okCount = 0,
    this.missCount = 0,
    this.wrongCount = 0,
    this.timingAbsDtSum = 0.0,
    this.sustainFactorSum = 0.0,
    this.timingP95AbsMs = 0.0,
  });

  int totalScore;
  int combo;
  int maxCombo;
  int perfectCount;
  int goodCount;
  int okCount;
  int missCount;
  int wrongCount;

  // For average calculations
  double timingAbsDtSum; // Sum of |dt| for matched notes
  double sustainFactorSum; // Sum of sustain factors for matched notes
  double timingP95AbsMs; // 95th percentile of |dt| (computed on stopPractice)

  /// Accuracy: notes matched / notes expected
  double get accuracyPitch {
    final matched = perfectCount + goodCount + okCount;
    final total = matched + missCount;
    return total > 0 ? matched / total : 0.0;
  }

  /// Average timing error (ms) for matched notes
  double get timingAvgAbsMs {
    final matched = perfectCount + goodCount + okCount;
    return matched > 0 ? timingAbsDtSum / matched : 0.0;
  }

  /// Average sustain factor for matched notes
  double get sustainAvgFactor {
    final matched = perfectCount + goodCount + okCount;
    return matched > 0 ? sustainFactorSum / matched : 1.0;
  }

  /// Total notes processed
  int get totalNotesProcessed => perfectCount + goodCount + okCount + missCount;

  PracticeScoringState copyWith({
    int? totalScore,
    int? combo,
    int? maxCombo,
    int? perfectCount,
    int? goodCount,
    int? okCount,
    int? missCount,
    int? wrongCount,
    double? timingAbsDtSum,
    double? sustainFactorSum,
    double? timingP95AbsMs,
  }) {
    return PracticeScoringState(
      totalScore: totalScore ?? this.totalScore,
      combo: combo ?? this.combo,
      maxCombo: maxCombo ?? this.maxCombo,
      perfectCount: perfectCount ?? this.perfectCount,
      goodCount: goodCount ?? this.goodCount,
      okCount: okCount ?? this.okCount,
      missCount: missCount ?? this.missCount,
      wrongCount: wrongCount ?? this.wrongCount,
      timingAbsDtSum: timingAbsDtSum ?? this.timingAbsDtSum,
      sustainFactorSum: sustainFactorSum ?? this.sustainFactorSum,
      timingP95AbsMs: timingP95AbsMs ?? this.timingP95AbsMs,
    );
  }

  @override
  String toString() =>
      'PracticeScoringState(score=$totalScore, combo=$combo/$maxCombo, '
      'grades=[P:$perfectCount G:$goodCount O:$okCount M:$missCount W:$wrongCount], '
      'accuracy=${(accuracyPitch * 100).toStringAsFixed(1)}%, '
      'avgTiming=${timingAvgAbsMs.toStringAsFixed(1)}ms)';
}
