import 'package:flutter/foundation.dart';
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

  // FIX BUG P0-A (SESSION4): Latence micro compensation
  // Problème: onTimeUpdate() résolvait miss trop tôt (avant arrivée event stable)
  // Solution: Ajouter latence micro (~300ms) avant de déclarer miss
  // ChatGPT analysis: dt observés = 0.259-0.485s (moyenne ~300ms)
  static const double _micLatencyMs = 300.0;

  // Tail window for timeout detection (matches MicEngine tailWindowSec)
  static const double _tailWindowMs = 450.0;

  // FIX BUG P0-B (SESSION4): Octave subharmonic correction
  // Problème: Micro détecte octave basse (ex: C3=48 au lieu de C4=60)
  // Solution: Correction ciblée +12/+24 SI pitch-class match ET distance finale ≤3
  // IMPORTANT: Octave shifts globaux restent désactivés dans NoteMatcher
  static const int _octaveSemitones = 12;
  static const int _maxOctaveFixSemitoneDistance = 3;

  // Session state
  String? _currentSessionId;
  List<ExpectedNote> _expectedNotes = [];
  List<PlayedNoteEvent> _playedBuffer = [];
  Set<String> _consumedPlayedIds = {};
  Set<int> _resolvedExpectedIndices =
      {}; // Track resolved notes to prevent double-resolve
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
    _resolvedExpectedIndices = {};
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

    // FIX BUG #8 (SESSION4): Finalize remaining unresolved notes as MISS
    // Problème: idx=7 détecté MISS mais jamais RESOLVE avant video_end stop
    // Solution: Forcer résolution de toutes notes non résolues avant metrics finaux
    _finalizeRemainingNotes();

    // Finalize p95 timing metric
    if (_allAbsDtMs.isNotEmpty && _allAbsDtMs.length > 1) {
      final sorted = List<double>.from(_allAbsDtMs)..sort();
      final p95Index = (sorted.length * 0.95).floor();
      _scoringState.timingP95AbsMs = sorted[p95Index];
    }

    state = state.copyWith(isActive: false, scoringState: _scoringState);

    _currentSessionId = null;
  }

  /// Finalize all unresolved expected notes as MISS
  /// Called at stopPractice() to ensure all notes are accounted for
  void _finalizeRemainingNotes() {
    final unresolvedIndices = <int>[];
    for (int i = 0; i < _expectedNotes.length; i++) {
      if (!_resolvedExpectedIndices.contains(i)) {
        unresolvedIndices.add(i);
      }
    }

    if (unresolvedIndices.isEmpty) return;

    if (kDebugMode) {
      debugPrint(
        'FINALIZE: Marking ${unresolvedIndices.length} unresolved notes as MISS at stop (indices: ${unresolvedIndices.join(",")})',
      );
    }

    // Resolve each unresolved note as MISS
    for (final idx in unresolvedIndices) {
      _resolvedExpectedIndices.add(idx);
      _resolveExpectedNote(expectedIndex: idx, matchedEvent: null, dtMs: null);
    }
  }

  /// Handle a played note event (mic or MIDI)
  ///
  /// This is the core matching + scoring logic:
  /// 1. Validate session
  /// 2. Add to buffer
  /// 3. Try to match with expected notes
  /// 4. If matched: resolve hit/miss, update score
  /// 5. If no match: mark as wrong (with caution)
  ///
  /// [forceMatchExpectedIndex]: If provided, skip matching and directly resolve
  /// the expected note at this index. Used when external system (OLD) already
  /// validated the match (bridge between OLD/NEW systems).
  void onPlayedNote(
    PlayedNoteEvent event, {
    int? forceMatchExpectedIndex,
    double? micEngineDtMs, // dt from MicEngine (for bridge)
  }) {
    if (!state.isActive || _currentSessionId != state.currentSessionId) {
      // Stale event from previous session, ignore
      return;
    }

    // BRIDGE: If OLD system already validated match, skip our matching
    if (forceMatchExpectedIndex != null) {
      if (forceMatchExpectedIndex >= 0 &&
          forceMatchExpectedIndex < _expectedNotes.length &&
          !_resolvedExpectedIndices.contains(forceMatchExpectedIndex)) {
        final expectedNote = _expectedNotes[forceMatchExpectedIndex];

        // Apply octave fix if needed
        // CRITICAL: Include the forced note itself in activeExpected for octave fix
        // Handle both forward and backward matches (forced index can be < _nextExpectedIndex)
        final lookahead = 10;
        final scanStartIndex = forceMatchExpectedIndex < _nextExpectedIndex
            ? forceMatchExpectedIndex
            : _nextExpectedIndex;
        final naturalEnd = _nextExpectedIndex + lookahead;
        final forcedEnd = forceMatchExpectedIndex + 1;
        final scanEndIndex = (naturalEnd > forcedEnd ? naturalEnd : forcedEnd)
            .clamp(scanStartIndex, _expectedNotes.length);
        final activeExpected = _expectedNotes.sublist(
          scanStartIndex,
          scanEndIndex,
        );
        final playedEvent = _maybeFixDownOctave(event, activeExpected);

        // Add to buffer
        _playedBuffer.add(playedEvent);

        // Mark consumed immediately
        _consumedPlayedIds.add(playedEvent.id);

        // FIX BUG #6 (SESSION4): Use MicEngine's dtMs instead of recalculating
        // MicEngine window: [start-120ms ... end+450ms] (can be 2s+ for long notes)
        // PracticeController would calculate dt from note.start only (≤450ms threshold)
        // These are INCOMPATIBLE - HITs at 570ms+ after start are valid in MicEngine
        // but rejected by PracticeController. Use MicEngine's dt (calculated correctly).
        final dtMs =
            micEngineDtMs ?? (playedEvent.tPlayedMs - expectedNote.tExpectedMs);

        // Mark as resolved BEFORE calling _resolveExpectedNote to prevent recursion
        _resolvedExpectedIndices.add(forceMatchExpectedIndex);

        // Resolve with MicEngine's dt
        _resolveExpectedNote(
          expectedIndex: forceMatchExpectedIndex,
          matchedEvent: playedEvent,
          dtMs: dtMs,
        );

        return;
      }
    }

    // Try to match with upcoming expected notes
    // We scan from _nextExpectedIndex up to a reasonable lookahead
    // (e.g., 10 notes ahead) to handle early hits
    final lookahead = 10;
    final scanEndIndex = (_nextExpectedIndex + lookahead).clamp(
      _nextExpectedIndex,
      _expectedNotes.length,
    );

    // FIX BUG #1 (SESSION4): Octave subharmonic correction AVANT buffering
    // CRITICAL: Buffer DOIT stocker event corrigé, sinon _isMatchForExpected
    // classifiera les HIT comme MISS plus tard dans wasMatched checks
    final activeExpected = _expectedNotes.sublist(
      _nextExpectedIndex,
      scanEndIndex,
    );
    final playedEvent = _maybeFixDownOctave(event, activeExpected);

    // Add to buffer (corrected event)
    _playedBuffer.add(playedEvent);

    for (var i = _nextExpectedIndex; i < scanEndIndex; i++) {
      final expected = _expectedNotes[i];

      // Skip if already resolved (by bridge)
      if (_resolvedExpectedIndices.contains(i)) {
        continue;
      }

      // Check if this expected note is in range of the played event
      final dt = playedEvent.tPlayedMs - expected.tExpectedMs;
      if (dt < -_matcher.windowMs) {
        // Played note is too early for this expected note
        // (and all subsequent ones), stop scanning
        break;
      }

      // Try to match
      final candidate = _matcher.findBestMatch(
        expected,
        [playedEvent], // Possibly corrected event
        _consumedPlayedIds,
      );

      if (candidate != null) {
        // Match found!
        _resolvedExpectedIndices.add(i);

        _resolveExpectedNote(
          expectedIndex: i,
          matchedEvent: playedEvent,
          dtMs: candidate.dtMs,
        );

        // Mark as consumed
        _consumedPlayedIds.add(playedEvent.id);
        return; // Done processing this event
      }
    }

    // FIX BUG #3 (SESSION4): Log match failure avec détails filtrage
    if (kDebugMode && _nextExpectedIndex < _expectedNotes.length) {
      final nextExpected = _expectedNotes[_nextExpectedIndex];
      debugPrint(
        'SESSION4_MATCH_FAIL: '
        'rawMidi=${event.midi} usedMidi=${playedEvent.midi} '
        't=${playedEvent.tPlayedMs.toStringAsFixed(1)} '
        'nextExpectedMidi=${nextExpected.midi} '
        'dist=${(playedEvent.midi - nextExpected.midi).abs()}',
      );
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

      // CRITICAL: Timeout must match MicEngine logic: note.end + tailWindow + latency
      // = (tExpected + duration) + tailWindow + latency
      // This ensures controller doesn't mark MISS before MicEngine for long notes
      final timeoutMs =
          expected.tExpectedMs +
          (expected.durationMs ?? 0) +
          _tailWindowMs +
          _micLatencyMs;

      if (currentTimeMs > timeoutMs) {
        // Skip if already resolved (by bridge or normal matching)
        if (!_resolvedExpectedIndices.contains(_nextExpectedIndex)) {
          // Check if it was matched
          final wasMatched = _consumedPlayedIds.any((id) {
            return _playedBuffer
                .where((e) => e.id == id)
                .any((e) => _isMatchForExpected(e, expected));
          });

          if (!wasMatched) {
            // Miss!
            _resolvedExpectedIndices.add(_nextExpectedIndex);
            _resolveExpectedNote(
              expectedIndex: _nextExpectedIndex,
              matchedEvent: null,
              dtMs: null,
            );
          }
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
    // FIX BUG #2 (SESSION4): Éviter punir artefacts techniques
    // Si pitch-class match note attendue proche temporellement → near-miss
    // (pas de pénalité WRONG)
    if (_isNearMissPitchClass(event)) {
      _logger.logNearMissPlayed(
        sessionId: _currentSessionId!,
        playedId: event.id,
        pitchKey: event.midi,
        tPlayedMs: event.tPlayedMs,
        reason:
            'Pitch-class matches expected near same time (likely octave/harmonic artifact)',
      );
      return;
    }

    // Vrai WRONG (note complètement hors contexte)
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

  /// FIX BUG #1 (SESSION4): Octave subharmonic correction ciblée
  ///
  /// Corrige UNIQUEMENT si:
  /// - Source = microphone (pas MIDI)
  /// - Pitch-class match avec expected active
  /// - Distance originale >3 demi-tons
  /// - Après correction (+12 ou +24), distance ≤3
  ///
  /// IMPORTANT: N'active PAS octave shifts globaux (restent désactivés NoteMatcher)
  PlayedNoteEvent _maybeFixDownOctave(
    PlayedNoteEvent event,
    List<ExpectedNote> activeExpected,
  ) {
    if (event.source != NoteSource.microphone) return event;
    if (activeExpected.isEmpty) return event;

    final pitchClasses = activeExpected.map((e) => e.midi % 12).toSet();
    final playedPc = event.midi % 12;
    if (!pitchClasses.contains(playedPc)) return event;

    // Helper: distance minimale à expected notes avec même pitch-class
    int minDist(int midi) {
      var best = 1 << 30;
      for (final e in activeExpected) {
        if ((e.midi % 12) != playedPc) continue;
        final d = (midi - e.midi).abs();
        if (d < best) best = d;
      }
      return best;
    }

    final originalDist = minDist(event.midi);
    if (originalDist <= _maxOctaveFixSemitoneDistance) return event;

    // Tester +12 et +24 (corrections octave basse)
    final candidates = <int>[
      event.midi + _octaveSemitones,
      event.midi + (_octaveSemitones * 2),
    ].where((m) => m >= 0 && m <= 127).toList();

    var bestMidi = event.midi;
    var bestDist = originalDist;

    for (final m in candidates) {
      final d = minDist(m);
      if (d < bestDist) {
        bestDist = d;
        bestMidi = m;
      }
    }

    if (bestMidi != event.midi && bestDist <= _maxOctaveFixSemitoneDistance) {
      if (kDebugMode) {
        debugPrint(
          'SESSION4_OCTAVE_FIX: '
          'playedId=${event.id.substring(0, 8)} '
          'rawMidi=${event.midi} correctedMidi=$bestMidi '
          'bestDist=$bestDist',
        );
      }
      return PlayedNoteEvent(
        id: event.id,
        midi: bestMidi,
        tPlayedMs: event.tPlayedMs,
        durationMs: event.durationMs,
        source: event.source,
      );
    }

    return event;
  }

  /// FIX BUG #2 (SESSION4): Check si pitch-class match expected note proche
  ///
  /// Utilisé pour éviter pénalité WRONG sur artefacts techniques
  /// (octave/harmonique détecté mais distance >3)
  bool _isNearMissPitchClass(PlayedNoteEvent event) {
    if (_expectedNotes.isEmpty) return false;
    final playedPc = event.midi % 12;

    // Scanner autour pointer expected (±6 notes) avec window temporelle large
    final start = (_nextExpectedIndex - 6).clamp(0, _expectedNotes.length);
    final end = (_nextExpectedIndex + 6).clamp(0, _expectedNotes.length);
    final checkWindowMs = (_matcher.windowMs * 2) + _micLatencyMs;

    for (final e in _expectedNotes.sublist(start, end)) {
      final dt = (e.tExpectedMs - event.tPlayedMs).abs();
      if (dt > checkWindowMs) continue;
      if ((e.midi % 12) == playedPc) return true;
    }
    return false;
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
        // CRITICAL: Must be >= ScoringEngine.okThresholdMs (450ms) to allow "ok" grades
        // Previous: 300ms caused events at 300-450ms to be rejected by matcher
        // but accepted by scorer, resulting in unmatched hits marked as MISS
        windowMs:
            450, // Matches MicEngine tailWindowSec and ScoringEngine okThreshold
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
