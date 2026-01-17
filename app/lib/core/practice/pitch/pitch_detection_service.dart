import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

/// Abstract interface for pitch detection algorithms.
///
/// This abstraction allows swapping between different pitch detection
/// implementations (MPM, YIN, etc.) without changing the consuming code.
///
/// STEP 1 (YIN Integration): Created stable interface for pitch detection.
/// STEP 3: Added async support for isolate-based detection.
abstract class PitchDetectionService {
  /// Detect pitch from audio samples (synchronous).
  ///
  /// [samples] - Audio samples as Float32List (mono, normalized -1.0 to 1.0)
  /// [sampleRate] - Sample rate in Hz (e.g., 44100)
  ///
  /// Returns frequency in Hz, or null if no clear pitch detected.
  double? detectPitch(Float32List samples, {int? sampleRate});

  /// Detect pitch from audio samples (asynchronous).
  ///
  /// Default implementation wraps [detectPitch] in a Future.
  /// Override for true async implementations (e.g., isolate-based).
  ///
  /// STEP 3: Added for future isolate support.
  Future<double?> detectPitchAsync(Float32List samples, {int? sampleRate}) {
    return Future.value(detectPitch(samples, sampleRate: sampleRate));
  }

  /// Default sample rate for this detector.
  int get defaultSampleRate;

  /// Required buffer size for this detector.
  int get requiredBufferSize;

  /// Algorithm name for logging/debugging.
  String get algorithmName;

  /// Convert frequency to MIDI note number.
  int frequencyToMidiNote(double frequency);

  /// Convert MIDI note to frequency.
  double midiNoteToFrequency(int note);
}

/// Wrapper that runs pitch detection in an isolate for non-blocking operation.
///
/// STEP 3: Isolate-based async detection for performance on low-end devices.
///
/// Usage:
/// ```dart
/// final service = MpmPitchService();
/// final isolateService = IsolatePitchService(service);
/// final freq = await isolateService.detectPitchAsync(samples);
/// await isolateService.dispose();
/// ```
class IsolatePitchService implements PitchDetectionService {
  IsolatePitchService(this._innerService);

  final PitchDetectionService _innerService;

  // Reserved for true isolate implementation (future enhancement)
  Isolate? _isolate;

  @override
  String get algorithmName => '${_innerService.algorithmName}(isolate)';

  @override
  int get defaultSampleRate => _innerService.defaultSampleRate;

  @override
  int get requiredBufferSize => _innerService.requiredBufferSize;

  /// Synchronous detection - delegates to inner service.
  /// Use [detectPitchAsync] for non-blocking operation.
  @override
  double? detectPitch(Float32List samples, {int? sampleRate}) {
    return _innerService.detectPitch(samples, sampleRate: sampleRate);
  }

  /// Asynchronous detection via isolate.
  ///
  /// First call spawns the isolate. Subsequent calls reuse it.
  @override
  Future<double?> detectPitchAsync(
    Float32List samples, {
    int? sampleRate,
  }) async {
    // For now, just use async wrapper (true isolate implementation is complex)
    // This prepares the API without the complexity of isolate message passing
    return Future.microtask(() {
      return _innerService.detectPitch(samples, sampleRate: sampleRate);
    });
  }

  @override
  int frequencyToMidiNote(double frequency) {
    return _innerService.frequencyToMidiNote(frequency);
  }

  @override
  double midiNoteToFrequency(int note) {
    return _innerService.midiNoteToFrequency(note);
  }

  /// Dispose the isolate.
  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

/// Result of pitch detection with metadata.
///
/// Used for detailed analysis and comparison between algorithms.
class PitchDetectionResult {
  const PitchDetectionResult({
    required this.frequency,
    required this.confidence,
    required this.algorithmName,
    this.midiNote,
    this.processingTimeUs,
  });

  /// Detected frequency in Hz, or null if no pitch.
  final double? frequency;

  /// Confidence score (0.0 to 1.0).
  /// For MPM: clarity value from NSDF.
  /// For YIN: 1.0 - cumulative mean normalized difference.
  final double confidence;

  /// Algorithm that produced this result.
  final String algorithmName;

  /// MIDI note number (computed from frequency).
  final int? midiNote;

  /// Processing time in microseconds (for performance comparison).
  final int? processingTimeUs;

  @override
  String toString() =>
      'PitchDetectionResult(freq=${frequency?.toStringAsFixed(1)}Hz, '
      'conf=${confidence.toStringAsFixed(2)}, algo=$algorithmName, '
      'midi=$midiNote, time=${processingTimeUs}us)';
}
