part of '../practice_page.dart';

/// Base class containing all state fields for _PracticePageState.
/// Mixins can extend this to access state without circular dependency.
abstract class _PracticePageStateBase extends ConsumerState<PracticePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool get _isTestEnv =>
      widget.isTest || const bool.fromEnvironment('FLUTTER_TEST');

  String _formatMidiNote(int midi, {bool withOctave = false}) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final base = names[midi % 12];
    if (!withOctave) {
      return base;
    }
    final octave = (midi ~/ 12) - 1;
    return '$base$octave';
  }

  bool _practiceRunning = false;
  bool _practiceStarting =
      false; // Prevent race: don't show countdown until all ready
  int _practiceSessionId =
      0; // Increment on each new start; prevents stale callbacks
  bool _isListening = false;
  bool _isCalibrating =
      false; // FIX BUG CRITIQUE #2: Track active calibration beep
  int? _detectedNote;
  NoteAccuracy _accuracy = NoteAccuracy.miss;
  // PATCH: Shows only notes currently touching keyboard (no preview)
  // Computed fresh in _onMidiFrame and _onMicFrame
  // FEATURE A: Lead-in countdown state
  _PracticeState _practiceState = _PracticeState.idle;
  DateTime? _countdownStartTime;

  // FIX BUG 1: Helper to check if layout is stable (200ms after countdown start)
  // Increased from 100ms to 200ms to prevent preview flash during first frames
  // CRITICAL: Return false if countdown hasn't started yet to prevent preview during loading
  bool _isLayoutStable() {
    if (_countdownStartTime == null) {
      return false; // Countdown not started = NOT stable
    }
    return DateTime.now().difference(_countdownStartTime!).inMilliseconds >=
        200;
  }

  late double _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
  double? _earliestNoteStartSec; // Clamped to >= 0, used for effective lead-in

  int _totalNotes = 0;
  // SUSTAIN SCORING: Track cumulative sustain ratios for precision calculation
  // Precision = sum(sustainRatio) / totalNotes * 100
  // Each note contributes its sustainRatio (0.0-1.0) to the total
  double _cumulativeSustainRatio = 0.0;
  DateTime? _startTime;
  StreamSubscription<List<int>>? _micSub;
  final RecorderStream _recorder = RecorderStream();
  StreamSubscription<MidiPacket>? _midiSub;
  final _pitchDetector = PitchDetector();
  mic.MicEngine? _micEngine;
  double _micLatencyCompSec = 0.0; // Compensation for buffer latency
  // D1: Micro scoring offset (auto-calibrated via EMA on pitch_match confidence)
  double _micScoringOffsetSec =
      0.0; // Offset between micro elapsed and scoring elapsed

  // ══════════════════════════════════════════════════════════════════════
  // NEW SCORING SYSTEM (Session 4) - runs in PARALLEL with old system
  // ══════════════════════════════════════════════════════════════════════
  PracticeController? _newController; // New controller instance
  final bool _useNewScoringSystem = true; // Flag to enable/disable new system

  // ══════════════════════════════════════════════════════════════════════
  // SESSION-056: UI Feedback Engine - Moteur perceptif "jeu vidéo"
  // Source de vérité = PERCEPTION utilisateur (pas scoring)
  // BLEU=détection, CYAN=partition, VERT=succès, ROUGE=erreur
  // ══════════════════════════════════════════════════════════════════════
  UIFeedbackEngine? _uiFeedbackEngine;

  /// Vérifie si le mode S56 est PRÊT à produire du feedback
  bool _isS56ModeReady() {
    return _uiFeedbackEngine != null && _practiceRunning;
  }

  // Anti-spam note tenue: cache séparé pour hit vs wrong (FIX BUG #1)
  int? _lastHitMidi;
  DateTime? _lastHitAt;
  // SESSION-039: Track onset of last HIT to distinguish sustain vs re-attack
  double _lastHitOnsetMs = -10000.0;
  int? _lastWrongMidi;
  DateTime? _lastWrongAt;

  // Constantes gating audio
  // FIX BUG SESSION-005: Augmenter sensibilité micro (0.0020 → 0.0010)
  // Piano acoustique à 50cm dans pièce silencieuse = notes bien captées
  // 0.0010 permet de capter notes plus douces sans trop de faux positifs
  final double _absMinRms = 0.0010;
  // ══════════════════════════════════════════════════════════════════════

  // Timebase continuity variables removed (clock-based simplified)
  bool _micConfigLogged = false; // Log MIC_CONFIG only once per session
  List<_NoteEvent> _rawNoteEvents = [];
  List<_NoteEvent> _noteEvents = [];
  NotesSource _notesSource = NotesSource.none;
  int _notesRawCount = 0;
  int _notesDedupedCount = 0;
  int _notesFilteredCount = 0;
  int _notesDroppedOutOfRange = 0;
  int _notesDroppedDup = 0;
  int _notesDroppedOutOfVideo = 0;
  int _notesDroppedInvalidPitch = 0;
  int _notesDroppedInvalidTime = 0;
  int _notesMergedPairs = 0;
  int _notesOverlapsDetected = 0;
  final List<bool> _hitNotes = [];
  // Debug tracking (C4: Prove/stop duplicate overlays)
  int _overlayBuildCount = 0;
  int _listenerAttachCount = 0;
  int _painterInstanceId = 0;
  int _spawnLogCount = 0; // D2: Track SPAWN logs (reset per session)
  double _latencyMs = 0;
  final AudioPlayer _beepPlayer = AudioPlayer();
  bool _notesSourceLocked = false; // C2: Prevent mid-session source switch
  bool _useMidi = false;
  bool _midiAvailable = false;
  late final Ticker _ticker;
  final ScrollController _keyboardScrollController = ScrollController();
  double _keyboardScrollOffset = 0.0;
  double _lastLayoutMaxWidth = 0.0;
  VideoPlayerController? _videoController;
  double? _videoDurationSec;
  double? _stableVideoDurationSec; // C6: Non-decreasing duration per session
  ChewieController? _chewieController;
  VoidCallback? _videoListener;
  bool _videoLoading = true;
  String? _videoError;
  bool _notesLoading = false;
  String? _notesError;
  int? _notesLoadingSessionId; // C4: Guard double load by sessionId
  int?
  _notesLoadedSessionId; // C4: Guard already loaded (prevent sequential reload)
  double?
  _lastSanitizedDurationSec; // C7: Guard idempotent sanitize (epsilon 0.05)
  int _videoInitToken = 0; // Token guard for video init
  int?
  _durationLockedSessionId; // D2: Lock stable duration once per sessionId (prevent flip)
  PermissionStatus? _micPermissionStatus;
  bool _showMicPermissionFallback = false;
  bool _micDisabled = false;
  DateTime? _lastMicFrameAt;
  double _micRms = 0.0;
  // Phase B instrumentation: RMS statistics per session
  double? _micRmsMin;
  double? _micRmsMax;
  double _micRmsSum = 0.0;
  int _micSampleCount = 0;
  double? _micFrequency;
  int? _micNote;
  double _micConfidence = 0.0;
  DateTime? _lastMicLogAt;
  DateTime? _lastMidiFrameAt;
  int? _lastMidiNote;
  String? _stopReason;
  int _micRestartAttempts = 0;
  bool _micRestarting = false;
  DateTime? _lastMicRestartAt;
  DateTime? _lastUiUpdateAt;
  bool _videoEndFired = false;
  DateTime?
  _lastVideoEndAt; // FIX BUG 4: Track when video ended to prevent instant replay
  bool _devHudEnabled = false;
  bool _overlayBuiltInBuild = false;
  bool _showKeyboardGuides = false;
  bool _showKeyboardDebugLabels = true;
  bool _showMidiNumbers = true;
  bool _showOnlyTargets = false; // Toggle: paint only target notes (ghost test)
  // BUG 2 FIX: Track which variant was selected in preview to use consistently in practice
  String?
  _selectedVideoVariant; // 'preview' or 'full' - tracks what user chose in preview
  int _devTapCount = 0;
  DateTime? _devTapStartAt;

  // FIX BUG P0 (FALSE RED): Track recently validated HIT notes with timestamps
  // Prevents notes from turning red after being correctly validated
  final Map<int, DateTime> _recentlyHitNotes = {}; // midi -> hit timestamp

  int _displayFirstKey = _defaultFirstKey;
  int _displayLastKey = _defaultLastKey;
}
