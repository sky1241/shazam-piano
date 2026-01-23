// ============================================================================
// SESSION-021: Practice Debug Report
// ============================================================================
// Lightweight debug reporting for Practice mode.
// Activation: --dart-define=PRACTICE_DEBUG=true
//
// Features:
// - Ring buffer of last 20 pitch events with full context
// - Counters for noteOn/noteOff/dupe/outOfRange/dropTTL/latencySpike/stabilitySkip
// - Periodic log summary (every 5s if events occurred)
// - Final session dump on dispose
// - Sample-rate tracking (detected vs forced, ratio)
// - Timebase info (DateTime.now() elapsed from Stopwatch)
//
// Usage:
//   final report = PracticeDebugReport();
//   report.logEvent(...);
//   report.updateSampleRate(detected, forced);
//   report.logPeriodicSummary(elapsedMs);
//   report.dumpFinalReport();
// ============================================================================

import 'package:flutter/foundation.dart';

import 'mic_engine.dart';

/// SESSION-021: Debug report for Practice mode analysis.
///
/// Collects and summarizes pitch detection events for post-session debugging.
/// Only active when kPracticeDebugEnabled is true (--dart-define=PRACTICE_DEBUG=true).
class PracticeDebugReport {
  PracticeDebugReport({
    this.ringBufferSize = 20,
    this.periodicLogIntervalMs = 5000.0,
  });

  final int ringBufferSize;
  final double periodicLogIntervalMs;

  // Ring buffer
  final List<DebugPitchEvent> _ringBuffer = [];

  // Counters
  int _noteOnCount = 0;
  int _noteOffCount = 0;
  int _dupeCount = 0;
  int _outOfRangeCount = 0;
  int _dropTtlCount = 0;
  int _latencySpikeCount = 0;
  int _stabilitySkipCount = 0;

  // Latency tracking
  double? _latencyCompMs;
  double? _latencyMedianMs;
  int _latencySampleCount = 0;

  // Sample-rate tracking
  int? _detectedSampleRate;
  int? _forcedSampleRate;
  double? _sampleRateRatio;

  // Timing
  double _lastPeriodicLogMs = -10000.0;
  double _sessionStartMs = 0.0;

  // Snap tracking (SESSION-021)
  int _snapCount = 0;

  // SESSION-022: Re-attack and TTL tracking
  int _reattackCount = 0;
  int _ttlReleaseCount = 0;

  /// Reset all state for new session.
  void reset() {
    _ringBuffer.clear();
    _noteOnCount = 0;
    _noteOffCount = 0;
    _dupeCount = 0;
    _outOfRangeCount = 0;
    _dropTtlCount = 0;
    _latencySpikeCount = 0;
    _stabilitySkipCount = 0;
    _latencyCompMs = null;
    _latencyMedianMs = null;
    _latencySampleCount = 0;
    _detectedSampleRate = null;
    _forcedSampleRate = null;
    _sampleRateRatio = null;
    _lastPeriodicLogMs = -10000.0;
    _sessionStartMs = 0.0;
    _snapCount = 0;
    _reattackCount = 0;
    _ttlReleaseCount = 0;
  }

  /// Update sample rate tracking info.
  void updateSampleRate({
    required int detected,
    required int forced,
  }) {
    _detectedSampleRate = detected;
    _forcedSampleRate = forced;
    _sampleRateRatio = forced > 0 ? detected / forced : null;
  }

  /// Log a pitch snap event (+-1 semitone tolerance).
  void logSnap() {
    if (!kPracticeDebugEnabled) return;
    _snapCount++;
  }

  /// SESSION-022: Log a re-attack event (same note struck while held).
  void logReattack() {
    if (!kPracticeDebugEnabled) return;
    _reattackCount++;
  }

  /// SESSION-022: Log a TTL release event (note auto-released after timeout).
  void logTtlRelease() {
    if (!kPracticeDebugEnabled) return;
    _ttlReleaseCount++;
  }

  /// Log a pitch event to the ring buffer.
  void logEvent(DebugPitchEvent event) {
    if (!kPracticeDebugEnabled) return;

    _ringBuffer.add(event);
    if (_ringBuffer.length > ringBufferSize) {
      _ringBuffer.removeAt(0);
    }

    // Update counters based on state
    switch (event.state) {
      case 'noteOn':
        _noteOnCount++;
        break;
      case 'noteOff':
        _noteOffCount++;
        break;
      case 'dupe':
        _dupeCount++;
        break;
      case 'outOfRange':
        _outOfRangeCount++;
        break;
      case 'dropTtl':
        _dropTtlCount++;
        break;
      case 'spike':
        _latencySpikeCount++;
        break;
      case 'stabilitySkip':
        _stabilitySkipCount++;
        break;
    }
  }

  /// Log a latency spike rejection.
  void logLatencySpike(double sampleMs, double medianMs, double threshold) {
    if (!kPracticeDebugEnabled) return;
    _latencySpikeCount++;
  }

  /// Update latency tracking info.
  void updateLatency({
    required double compMs,
    double? medianMs,
    required int sampleCount,
  }) {
    _latencyCompMs = compMs;
    _latencyMedianMs = medianMs;
    _latencySampleCount = sampleCount;
  }

  /// Log periodic summary (call from onAudioChunk).
  void logPeriodicSummary(double elapsedMs) {
    if (!kPracticeDebugEnabled) return;

    if (_sessionStartMs == 0.0) {
      _sessionStartMs = elapsedMs;
    }

    if (elapsedMs - _lastPeriodicLogMs < periodicLogIntervalMs) {
      return;
    }
    _lastPeriodicLogMs = elapsedMs;

    // Only log if there was activity
    final totalEvents = _noteOnCount + _noteOffCount + _dupeCount +
        _outOfRangeCount + _dropTtlCount + _latencySpikeCount + _stabilitySkipCount;
    if (totalEvents == 0) return;

    final sessionDurationSec = (elapsedMs - _sessionStartMs) / 1000.0;

    debugPrint(
      'DEBUG_REPORT_PERIODIC t=${elapsedMs.toStringAsFixed(0)}ms '
      'duration=${sessionDurationSec.toStringAsFixed(1)}s '
      'noteOn=$_noteOnCount noteOff=$_noteOffCount '
      'dupe=$_dupeCount outOfRange=$_outOfRangeCount dropTtl=$_dropTtlCount '
      'latencySpike=$_latencySpikeCount stabilitySkip=$_stabilitySkipCount '
      'latencyCompMs=${_latencyCompMs?.toStringAsFixed(1) ?? "n/a"} '
      'latencyMedianMs=${_latencyMedianMs?.toStringAsFixed(1) ?? "n/a"} '
      'latencySamples=$_latencySampleCount',
    );
  }

  /// Dump final report at end of session.
  void dumpFinalReport(double elapsedMs) {
    if (!kPracticeDebugEnabled) return;

    final sessionDurationSec = (elapsedMs - _sessionStartMs) / 1000.0;

    debugPrint('');
    debugPrint('============================================================');
    debugPrint('DEBUG_REPORT_FINAL - SESSION COMPLETE');
    debugPrint('============================================================');
    debugPrint('Duration: ${sessionDurationSec.toStringAsFixed(1)}s');
    debugPrint('');
    debugPrint('--- COUNTERS ---');
    debugPrint('  noteOn:        $_noteOnCount');
    debugPrint('  noteOff:       $_noteOffCount');
    debugPrint('  dupe:          $_dupeCount');
    debugPrint('  outOfRange:    $_outOfRangeCount');
    debugPrint('  dropTtl:       $_dropTtlCount');
    debugPrint('  latencySpike:  $_latencySpikeCount');
    debugPrint('  stabilitySkip: $_stabilitySkipCount');
    debugPrint('');
    debugPrint('--- LATENCY ---');
    debugPrint('  compMs:     ${_latencyCompMs?.toStringAsFixed(1) ?? "n/a"}');
    debugPrint('  medianMs:   ${_latencyMedianMs?.toStringAsFixed(1) ?? "n/a"}');
    debugPrint('  samples:    $_latencySampleCount');
    debugPrint('  timebase:   DateTime.now() elapsed (Stopwatch monotonic)');
    debugPrint('');
    debugPrint('--- SAMPLE RATE ---');
    debugPrint('  detected:   ${_detectedSampleRate ?? "n/a"}');
    debugPrint('  forced:     ${_forcedSampleRate ?? "n/a"}');
    debugPrint('  ratio:      ${_sampleRateRatio?.toStringAsFixed(3) ?? "n/a"}');
    debugPrint('');
    debugPrint('--- SNAP (+-1 semitone) ---');
    debugPrint('  snapCount:  $_snapCount');
    debugPrint('');
    debugPrint('--- SESSION-022: REATTACK & TTL ---');
    debugPrint('  reattacks:    $_reattackCount');
    debugPrint('  ttlReleases:  $_ttlReleaseCount');
    debugPrint('');
    debugPrint('--- RING BUFFER (last $ringBufferSize events) ---');
    for (var i = 0; i < _ringBuffer.length; i++) {
      final e = _ringBuffer[i];
      debugPrint('  [$i] ${e.toString()}');
    }
    debugPrint('============================================================');
    debugPrint('');
  }

  /// Get stats as map (for external access).
  Map<String, dynamic> get stats => {
    'noteOnCount': _noteOnCount,
    'noteOffCount': _noteOffCount,
    'dupeCount': _dupeCount,
    'outOfRangeCount': _outOfRangeCount,
    'dropTtlCount': _dropTtlCount,
    'latencySpikeCount': _latencySpikeCount,
    'stabilitySkipCount': _stabilitySkipCount,
    'latencyCompMs': _latencyCompMs,
    'latencyMedianMs': _latencyMedianMs,
    'latencySampleCount': _latencySampleCount,
    'detectedSampleRate': _detectedSampleRate,
    'forcedSampleRate': _forcedSampleRate,
    'sampleRateRatio': _sampleRateRatio,
    'snapCount': _snapCount,
    'reattackCount': _reattackCount,
    'ttlReleaseCount': _ttlReleaseCount,
    'ringBufferSize': _ringBuffer.length,
  };

  /// Get ring buffer (read-only).
  List<DebugPitchEvent> get ringBuffer => List.unmodifiable(_ringBuffer);
}
