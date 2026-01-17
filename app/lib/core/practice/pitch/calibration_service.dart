import 'dart:async';
import 'dart:typed_data';

import 'pitch_services.dart';

/// Result of a single calibration note measurement.
class CalibrationNoteMeasurement {
  const CalibrationNoteMeasurement({
    required this.expectedMidi,
    required this.detectedMidi,
    required this.detectedFreq,
    required this.latencyMs,
    required this.rmsAmplitude,
    required this.confidence,
  });

  /// Expected MIDI note (what we asked the user to play).
  final int expectedMidi;

  /// Detected MIDI note (what we heard).
  final int? detectedMidi;

  /// Detected frequency in Hz.
  final double? detectedFreq;

  /// Latency from "play now" signal to first stable detection (ms).
  final double latencyMs;

  /// RMS amplitude of the detected signal.
  final double rmsAmplitude;

  /// Detection confidence (0.0 - 1.0).
  final double confidence;

  /// Is this a successful detection?
  bool get isValid => detectedMidi != null && detectedFreq != null;

  /// Pitch error in semitones (expected - detected).
  double get pitchErrorSemitones {
    if (detectedMidi == null) return 0.0;
    return (expectedMidi - detectedMidi!).toDouble();
  }

  /// Frequency error ratio (expected / detected).
  double get freqErrorRatio {
    if (detectedFreq == null || detectedFreq == 0) return 1.0;
    final expectedFreq = 440.0 * _pow2((expectedMidi - 69) / 12);
    return expectedFreq / detectedFreq!;
  }

  static double _pow2(double x) {
    // 2^x approximation
    double result = 1.0;
    double term = x * 0.693147; // ln(2)
    double factorial = 1.0;
    for (int i = 1; i <= 10; i++) {
      factorial *= i;
      result += _pow(term, i) / factorial;
    }
    return result;
  }

  static double _pow(double base, int exp) {
    double result = 1.0;
    for (int i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }
}

/// Result of full 9-note calibration session.
class CalibrationResult {
  const CalibrationResult({
    required this.measurements,
    required this.avgLatencyMs,
    required this.latencyStdDev,
    required this.avgFreqOffset,
    required this.minRmsThreshold,
    required this.successRate,
    required this.recommendedAlgorithm,
  });

  /// Individual note measurements.
  final List<CalibrationNoteMeasurement> measurements;

  /// Average latency in milliseconds.
  final double avgLatencyMs;

  /// Standard deviation of latency (consistency measure).
  final double latencyStdDev;

  /// Average frequency offset (ratio, 1.0 = perfect).
  final double avgFreqOffset;

  /// Recommended minimum RMS threshold.
  final double minRmsThreshold;

  /// Percentage of notes successfully detected (0.0 - 1.0).
  final double successRate;

  /// Recommended pitch algorithm based on calibration.
  final PitchAlgorithm recommendedAlgorithm;

  /// Is calibration usable? (>50% success rate).
  bool get isUsable => successRate >= 0.5;

  /// Get calibration grade.
  String get grade {
    if (successRate >= 0.9) return 'Excellent';
    if (successRate >= 0.7) return 'Good';
    if (successRate >= 0.5) return 'Acceptable';
    return 'Poor';
  }
}

/// State of the calibration process.
enum CalibrationState {
  idle,
  preparing,
  waitingForNote,
  listening,
  processing,
  complete,
  failed,
}

/// Callback for calibration progress updates.
typedef CalibrationProgressCallback =
    void Function(
      CalibrationState state,
      int currentNote,
      int totalNotes,
      String? message,
    );

/// Service to calibrate pitch detection for a specific device.
///
/// STEP 4: 9-note calibration routine.
///
/// The calibration plays 9 notes across the piano range:
/// - C3 (48), E3 (52), G3 (55) - Low register
/// - C4 (60), E4 (64), G4 (67) - Middle register
/// - C5 (72), E5 (76), G5 (79) - High register
///
/// For each note:
/// 1. Display "Play [note name] now"
/// 2. Start timer
/// 3. Listen for pitch detection
/// 4. Record: latency, detected frequency, RMS, confidence
/// 5. Move to next note
///
/// After all notes:
/// - Calculate average latency
/// - Calculate frequency offset
/// - Determine optimal RMS threshold
/// - Recommend MPM vs YIN based on results
class CalibrationService {
  CalibrationService({PitchDetectionService? pitchService})
    : _pitchService = pitchService ?? PitchServiceFactory.createDefault();

  final PitchDetectionService _pitchService;

  // Calibration notes (9 notes across 3 octaves)
  static const List<int> calibrationNotes = [
    48, 52, 55, // C3, E3, G3
    60, 64, 67, // C4, E4, G4
    72, 76, 79, // C5, E5, G5
  ];

  static const List<String> noteNames = [
    'C3',
    'E3',
    'G3',
    'C4',
    'E4',
    'G4',
    'C5',
    'E5',
    'G5',
  ];

  // Calibration parameters
  static const int _maxListenTimeMs = 5000; // Max time to wait for a note
  static const int _minStableFrames = 2; // Minimum stable frames to confirm

  CalibrationState _state = CalibrationState.idle;
  CalibrationState get state => _state;

  final List<CalibrationNoteMeasurement> _measurements = [];
  int _currentNoteIndex = 0;

  CalibrationProgressCallback? _progressCallback;

  /// Start the calibration process.
  ///
  /// [onProgress] is called with state updates.
  /// [audioStreamProvider] should yield audio chunks during listening.
  ///
  /// Returns the calibration result when complete.
  Future<CalibrationResult> calibrate({
    required CalibrationProgressCallback onProgress,
    required Stream<Float32List> audioStream,
  }) async {
    _progressCallback = onProgress;
    _measurements.clear();
    _currentNoteIndex = 0;

    _setState(CalibrationState.preparing);
    await Future.delayed(const Duration(milliseconds: 500));

    // Process each calibration note
    for (int i = 0; i < calibrationNotes.length; i++) {
      _currentNoteIndex = i;
      final expectedMidi = calibrationNotes[i];
      final noteName = noteNames[i];

      _setState(CalibrationState.waitingForNote, message: 'Play $noteName');

      // Short delay to let user prepare
      await Future.delayed(const Duration(milliseconds: 800));

      // Listen for the note
      _setState(
        CalibrationState.listening,
        message: 'Listening for $noteName...',
      );

      final measurement = await _listenForNote(
        expectedMidi: expectedMidi,
        audioStream: audioStream,
      );

      _measurements.add(measurement);

      _setState(
        CalibrationState.processing,
        message: measurement.isValid
            ? 'Detected ${measurement.detectedMidi} (${measurement.latencyMs.toStringAsFixed(0)}ms)'
            : 'Note not detected',
      );

      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Calculate final results
    final result = _calculateResult();
    _setState(CalibrationState.complete);

    return result;
  }

  /// Listen for a specific note and measure its characteristics.
  Future<CalibrationNoteMeasurement> _listenForNote({
    required int expectedMidi,
    required Stream<Float32List> audioStream,
  }) async {
    final startTime = DateTime.now();
    double? detectedFreq;
    int? detectedMidi;
    double latencyMs = _maxListenTimeMs.toDouble();
    double rmsAmplitude = 0.0;
    double confidence = 0.0;
    int stableFrames = 0;
    int? lastMidi;

    final completer = Completer<CalibrationNoteMeasurement>();

    // Timeout
    final timeout = Timer(Duration(milliseconds: _maxListenTimeMs), () {
      if (!completer.isCompleted) {
        completer.complete(
          CalibrationNoteMeasurement(
            expectedMidi: expectedMidi,
            detectedMidi: null,
            detectedFreq: null,
            latencyMs: _maxListenTimeMs.toDouble(),
            rmsAmplitude: rmsAmplitude,
            confidence: 0.0,
          ),
        );
      }
    });

    // Listen to audio stream
    StreamSubscription<Float32List>? subscription;
    subscription = audioStream.listen((samples) {
      if (completer.isCompleted) {
        subscription?.cancel();
        return;
      }

      // Calculate RMS
      double sumSquares = 0.0;
      for (final sample in samples) {
        sumSquares += sample * sample;
      }
      final rms = _sqrt(sumSquares / samples.length);
      if (rms > rmsAmplitude) rmsAmplitude = rms;

      // Skip if too quiet
      if (rms < 0.001) {
        stableFrames = 0;
        lastMidi = null;
        return;
      }

      // Detect pitch
      final freq = _pitchService.detectPitch(samples);
      if (freq == null) {
        stableFrames = 0;
        lastMidi = null;
        return;
      }

      final midi = _pitchService.frequencyToMidiNote(freq);

      // Check stability (same note as last frame)
      if (midi == lastMidi) {
        stableFrames++;
      } else {
        stableFrames = 1;
        lastMidi = midi;
      }

      // Need stable frames to confirm
      if (stableFrames >= _minStableFrames) {
        detectedFreq = freq;
        detectedMidi = midi;
        latencyMs = DateTime.now()
            .difference(startTime)
            .inMilliseconds
            .toDouble();

        // Estimate confidence from RMS and stability
        confidence = (rms * 10).clamp(0.0, 1.0);

        timeout.cancel();
        subscription?.cancel();

        completer.complete(
          CalibrationNoteMeasurement(
            expectedMidi: expectedMidi,
            detectedMidi: detectedMidi,
            detectedFreq: detectedFreq,
            latencyMs: latencyMs,
            rmsAmplitude: rmsAmplitude,
            confidence: confidence,
          ),
        );
      }
    });

    return completer.future;
  }

  /// Calculate final calibration result from measurements.
  CalibrationResult _calculateResult() {
    final validMeasurements = _measurements.where((m) => m.isValid).toList();
    final successRate = validMeasurements.length / _measurements.length;

    if (validMeasurements.isEmpty) {
      return CalibrationResult(
        measurements: _measurements,
        avgLatencyMs: 500.0, // Default fallback
        latencyStdDev: 0.0,
        avgFreqOffset: 1.0,
        minRmsThreshold: 0.001,
        successRate: 0.0,
        recommendedAlgorithm: PitchAlgorithm.mpm,
      );
    }

    // Calculate average latency
    final latencies = validMeasurements.map((m) => m.latencyMs).toList();
    final avgLatency = latencies.reduce((a, b) => a + b) / latencies.length;

    // Calculate latency std dev
    double latencyVariance = 0.0;
    for (final l in latencies) {
      latencyVariance += (l - avgLatency) * (l - avgLatency);
    }
    final latencyStdDev = _sqrt(latencyVariance / latencies.length);

    // Calculate average frequency offset
    final freqOffsets = validMeasurements.map((m) => m.freqErrorRatio).toList();
    final avgFreqOffset =
        freqOffsets.reduce((a, b) => a + b) / freqOffsets.length;

    // Calculate RMS threshold (minimum RMS that gave valid detection)
    final rmsValues = validMeasurements.map((m) => m.rmsAmplitude).toList();
    rmsValues.sort();
    // Use 10th percentile as threshold (or minimum if < 10 measurements)
    final thresholdIndex = (rmsValues.length * 0.1).floor();
    final minRmsThreshold = rmsValues[thresholdIndex] * 0.8; // 80% of min

    // Recommend algorithm based on low note performance
    // YIN is generally better for low frequencies
    final lowNoteMeasurements = validMeasurements
        .where((m) => m.expectedMidi < 60)
        .toList();
    final lowNoteSuccessRate = lowNoteMeasurements.isEmpty
        ? 0.0
        : lowNoteMeasurements.where((m) => m.isValid).length /
              lowNoteMeasurements.length;

    // If MPM struggles with low notes, recommend YIN
    final recommendedAlgorithm = lowNoteSuccessRate < 0.5
        ? PitchAlgorithm.yin
        : PitchAlgorithm.mpm;

    return CalibrationResult(
      measurements: _measurements,
      avgLatencyMs: avgLatency,
      latencyStdDev: latencyStdDev,
      avgFreqOffset: avgFreqOffset,
      minRmsThreshold: minRmsThreshold,
      successRate: successRate,
      recommendedAlgorithm: recommendedAlgorithm,
    );
  }

  void _setState(CalibrationState newState, {String? message}) {
    _state = newState;
    _progressCallback?.call(
      newState,
      _currentNoteIndex + 1,
      calibrationNotes.length,
      message,
    );
  }

  /// Simple sqrt approximation (avoid dart:math import for portability).
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}
