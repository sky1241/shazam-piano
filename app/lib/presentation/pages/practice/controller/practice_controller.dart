import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/practice/debug/practice_debug_logger.dart';
import '../../../../core/practice/matching/note_matcher.dart';
import '../../../../core/practice/model/practice_models.dart';
import '../../../../core/practice/scoring/practice_scoring_engine.dart';

/// View state for practice UI
class PracticeViewState {
  const PracticeViewState({
    required this.isActive,
    required this.scoringState,
    this.currentSessionId,
    this.currentNoteIndex = 0,
    this.lastGrade,
  });

  final bool isActive;
  final PracticeScoringState scoringState;
  final String? currentSessionId;
  final int currentNoteIndex;
  final HitGrade? lastGrade;

  factory PracticeViewState.initial() =>
      PracticeViewState(isActive: false, scoringState: PracticeScoringState());

  PracticeViewState copyWith({
    bool? isActive,
    PracticeScoringState? scoringState,
    String? currentSessionId,
    int? currentNoteIndex,
    HitGrade? lastGrade,
  }) {
    return PracticeViewState(
      isActive: isActive ?? this.isActive,
      scoringState: scoringState ?? this.scoringState,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      currentNoteIndex: currentNoteIndex ?? this.currentNoteIndex,
      lastGrade: lastGrade ?? this.lastGrade,
    );
  }
}

/// Practice session controller
///
/// Orchestrates matching, scoring, and logging for a practice session.
///
/// Workflow:
/// 1. startPractice() → init session, load expected notes
/// 2. onPlayedNote() → match + score + update state
/// 3. onTimeUpdate() → check for missed notes
/// 4. stopPractice() → finalize metrics
class PracticeController extends StateNotifier<PracticeViewState> {
  PracticeController({
    required PracticeScoringEngine scoringEngine,
    required NoteMatcher matcher,
    required PracticeDebugLogger logger,
  }) : _scoringEngine = scoringEngine,
       _matcher = matcher,
       _logger = logger,
       super(PracticeViewState.initial());

  final PracticeScoringEngine _scoringEngine;
  final NoteMatcher _matcher;
  final PracticeDebugLogger _logger;

  // Session state
  String? _currentSessionId;
  List<ExpectedNote> _expectedNotes = [];
  List<PlayedNoteEvent> _playedBuffer = [];
  Set<String> _consumedPlayedIds = {};
  int _nextExpectedIndex = 0;

  // Scoring state (mutable, updated in-place)
  PracticeScoringState _scoringState = PracticeScoringState();

  // Timing tracking for dt averages
  final List<double> _allAbsDtMs = [];

  static const _uuid = Uuid();

  /// Start a new practice session
  ///
  /// [sessionId] must be unique per session (anti-replay)
  /// [expectedNotes] list of notes to match against
  void startPractice({
    required String sessionId,
    required List<ExpectedNote> expectedNotes,
  }) {
    // Reset everything
    _currentSessionId = sessionId;
    _expectedNotes = expectedNotes;
    _playedBuffer = [];
    _consumedPlayedIds = {};
    _nextExpectedIndex = 0;
    _scoringState = PracticeScoringState();
    _allAbsDtMs.clear();

    _logger.clearLogs();

    state = state.copyWith(
      isActive: true,
      currentSessionId: sessionId,
      currentNoteIndex: 0,
      scoringState: _scoringState,
    );
  }

  /// Stop the current practice session
  ///
  /// Finalizes metrics and clears session state
  void stopPractice() {
    if (!state.isActive) return;

    // Finalize p95 timing metric
    if (_allAbsDtMs.isNotEmpty && _allAbsDtMs.length > 1) {
      final sorted = List<double>.from(_allAbsDtMs)..sort();
      final p95Index = (sorted.length * 0.95).floor();
      _scoringState.timingP95AbsMs = sorted[p95Index];
    }

    state = state.copyWith(isActive: false, scoringState: _scoringState);

    _currentSessionId = null;
  }

  /// Handle a played note event (mic or MIDI)
  ///
  /// This is the core matching + scoring logic:
  /// 1. Validate session
  /// 2. Add to buffer
  /// 3. Try to match with expected notes
  /// 4. If matched: resolve hit/miss, update score
  /// 5. If no match: mark as wrong (with caution)
  void onPlayedNote(PlayedNoteEvent event) {
    if (!state.isActive || _currentSessionId != state.currentSessionId) {
      // Stale event from previous session, ignore
      return;
    }

    // Add to buffer
    _playedBuffer.add(event);

    // Try to match with upcoming expected notes
    // We scan from _nextExpectedIndex up to a reasonable lookahead
    // (e.g., 10 notes ahead) to handle early hits
    final lookahead = 10;
    final scanEndIndex = (_nextExpectedIndex + lookahead).clamp(
      0,
      _expectedNotes.length,
    );

    for (var i = _nextExpectedIndex; i < scanEndIndex; i++) {
      final expected = _expectedNotes[i];

      // Check if this expected note is in range of the played event
      final dt = event.tPlayedMs - expected.tExpectedMs;
      if (dt < -_matcher.windowMs) {
        // Played note is too early for this expected note
        // (and all subsequent ones), stop scanning
        break;
      }

      // Try to match
      final candidate = _matcher.findBestMatch(
        expected,
        [event], // Only check this new event
        _consumedPlayedIds,
      );

      if (candidate != null) {
        // Match found!
        _resolveExpectedNote(
          expectedIndex: i,
          matchedEvent: event,
          dtMs: candidate.dtMs,
        );

        // Mark as consumed
        _consumedPlayedIds.add(event.id);
        return; // Done processing this event
      }
    }

    // No match found
    // CRITICAL: Only mark as WRONG if we're confident it's not a future hit
    // For now, we just buffer it. Wrong notes are detected in onTimeUpdate
    // when we move past the time window.
  }

  /// Update current time (called every frame or regularly)
  ///
  /// Checks for missed notes (time passed beyond window)
  void onTimeUpdate(double currentTimeMs) {
    if (!state.isActive) return;

    // Process all expected notes that are now "late" (missed)
    while (_nextExpectedIndex < _expectedNotes.length) {
      final expected = _expectedNotes[_nextExpectedIndex];

      // If current time is beyond the match window, this note is missed
      if (currentTimeMs > expected.tExpectedMs + _matcher.windowMs) {
        // Check if it was already matched
        final wasMatched = _consumedPlayedIds.any((id) {
          return _playedBuffer
              .where((e) => e.id == id)
              .any((e) => _isMatchForExpected(e, expected));
        });

        if (!wasMatched) {
          // Miss!
          _resolveExpectedNote(
            expectedIndex: _nextExpectedIndex,
            matchedEvent: null,
            dtMs: null,
          );
        }

        _nextExpectedIndex++;
      } else {
        // This note is still in range, stop scanning
        break;
      }
    }

    // Check for wrong notes (played events that never matched)
    // Only consider events that are now outside all possible windows
    final minExpectedTime = _nextExpectedIndex < _expectedNotes.length
        ? _expectedNotes[_nextExpectedIndex].tExpectedMs
        : double.infinity;

    final wrongCandidates = _playedBuffer.where((event) {
      // Already consumed? Not wrong
      if (_consumedPlayedIds.contains(event.id)) return false;

      // Too early to judge? (might match a future note)
      if (event.tPlayedMs + _matcher.windowMs >= minExpectedTime) {
        return false;
      }

      // This event is old and never matched → wrong
      return true;
    }).toList();

    for (final wrong in wrongCandidates) {
      _handleWrongNote(wrong);
      _consumedPlayedIds.add(wrong.id); // Mark to avoid reprocessing
    }

    // Update view state
    state = state.copyWith(
      currentNoteIndex: _nextExpectedIndex,
      scoringState: _scoringState,
    );
  }

  /// Resolve an expected note (hit or miss)
  void _resolveExpectedNote({
    required int expectedIndex,
    required PlayedNoteEvent? matchedEvent,
    required double? dtMs,
  }) {
    final expected = _expectedNotes[expectedIndex];

    HitGrade grade;
    double sustainFactor = 1.0;
    int pointsAdded;

    if (matchedEvent == null) {
      // Miss
      grade = HitGrade.miss;
      pointsAdded = 0;
    } else {
      // Hit
      grade = _scoringEngine.gradeFromDt(dtMs!.abs().round());

      // Compute sustain if durations available
      sustainFactor = _scoringEngine.computeSustainFactor(
        matchedEvent.durationMs,
        expected.durationMs,
      );

      // Compute points
      pointsAdded = _scoringEngine.computeFinalPoints(
        grade,
        _scoringState.combo,
        sustainFactor,
      );

      // Track dt for averages
      _allAbsDtMs.add(dtMs.abs());
    }

    // Create resolution
    final resolution = NoteResolution(
      expectedIndex: expectedIndex,
      grade: grade,
      dtMs: dtMs,
      pointsAdded: pointsAdded,
      matchedPlayedId: matchedEvent?.id,
      sustainFactor: sustainFactor,
    );

    // Apply to scoring state
    _scoringEngine.applyResolution(_scoringState, resolution);

    // Log
    _logger.logResolveExpected(
      sessionId: _currentSessionId!,
      expectedIndex: expectedIndex,
      grade: grade,
      dtMs: dtMs,
      pointsAdded: pointsAdded,
      combo: _scoringState.combo,
      totalScore: _scoringState.totalScore,
      matchedPlayedId: matchedEvent?.id,
    );

    // Update UI with last grade
    state = state.copyWith(lastGrade: grade, scoringState: _scoringState);
  }

  /// Handle a wrong note (played but never matched)
  void _handleWrongNote(PlayedNoteEvent event) {
    _scoringEngine.applyWrongNotePenalty(_scoringState);

    _logger.logWrongPlayed(
      sessionId: _currentSessionId!,
      playedId: event.id,
      pitchKey: event.midi,
      tPlayedMs: event.tPlayedMs,
      reason: 'No matching expected note within window',
    );

    // Update UI
    state = state.copyWith(
      lastGrade: HitGrade.wrong,
      scoringState: _scoringState,
    );
  }

  /// Helper: check if a played event corresponds to an expected note
  bool _isMatchForExpected(PlayedNoteEvent event, ExpectedNote expected) {
    final dt = (event.tPlayedMs - expected.tExpectedMs).abs();
    if (dt > _matcher.windowMs) return false;

    return _matcher.pitchEquals(event.midi, expected.midi);
  }

  /// Get final session summary (for end-of-game dialog)
  Map<String, dynamic> getSessionSummary() {
    return _logger.getSessionSummary(_currentSessionId ?? 'unknown');
  }

  /// Get current scoring state (for HUD display)
  PracticeScoringState get currentScoringState => _scoringState;

  /// Create a unique played note event
  static PlayedNoteEvent createPlayedEvent({
    required int midi,
    required double tPlayedMs,
    double? durationMs,
    required NoteSource source,
  }) {
    return PlayedNoteEvent(
      id: _uuid.v4(),
      midi: midi,
      tPlayedMs: tPlayedMs,
      durationMs: durationMs,
      source: source,
    );
  }
}

/// Provider for practice controller
///
/// Will be used in practice_page.dart for state management
final practiceControllerProvider =
    StateNotifierProvider<PracticeController, PracticeViewState>((ref) {
      // Default config (will be customizable later)
      final scoringConfig = ScoringConfig();
      final scoringEngine = PracticeScoringEngine(config: scoringConfig);

      // Use existing pitch matching logic (to be injected from practice_page)
      final matcher = NoteMatcher(
        windowMs: 200,
        pitchEquals: (p1, p2) => p1 == p2, // Placeholder, will use real logic
      );

      final debugConfig = DebugLogConfig(enableLogs: true);
      final logger = PracticeDebugLogger(config: debugConfig);

      return PracticeController(
        scoringEngine: scoringEngine,
        matcher: matcher,
        logger: logger,
      );
    });
