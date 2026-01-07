import 'dart:math';
import 'package:flutter/foundation.dart';

/// MicEngine: Robust scoring engine for Practice mode
/// Handles: pitch detection → event buffer → note matching → decisions
/// ZERO dependency on "nextDetected" stability gates
class MicEngine {
  MicEngine({
    required this.noteEvents,
    required this.hitNotes,
    required this.detectPitch,
    this.headWindowSec = 0.12,
    this.tailWindowSec = 0.45,
    this.absMinRms = 0.0008,
    this.minConfForWrong = 0.35,
    this.eventDebounceSec = 0.05,
    this.wrongFlashCooldownSec = 0.15,
    this.uiHoldMs = 200,
  });

  final List<NoteEvent> noteEvents;
  final List<bool> hitNotes;
  final double Function(List<double>, double) detectPitch;

  final double headWindowSec;
  final double tailWindowSec;
  final double absMinRms;
  final double minConfForWrong;
  final double eventDebounceSec;
  final double wrongFlashCooldownSec;
  final int uiHoldMs;

  String? _sessionId;
  final List<PitchEvent> _events = [];
  int? _detectedChannels;
  int? _detectedSampleRate;
  bool _configLogged = false;

  // UI state (hold last valid midi 200ms)
  int? _uiMidi;
  DateTime? _uiMidiSetAt;

  // Wrong flash throttle
  DateTime? _lastWrongFlashAt;

  /// Current UI detected MIDI (held 200ms)
  int? get uiDetectedMidi {
    if (_uiMidi != null && _uiMidiSetAt != null) {
      final elapsed = DateTime.now().difference(_uiMidiSetAt!).inMilliseconds;
      if (elapsed < uiHoldMs) return _uiMidi;
    }
    return null;
  }

  void reset(String sessionId) {
    _sessionId = sessionId;
    _events.clear();
    _detectedChannels = null;
    _detectedSampleRate = null;
    _configLogged = false;
    _uiMidi = null;
    _uiMidiSetAt = null;
    _lastWrongFlashAt = null;

    if (kDebugMode) {
      debugPrint(
        'SESSION_PARAMS sessionId=$sessionId head=${headWindowSec.toStringAsFixed(3)}s '
        'tail=${tailWindowSec.toStringAsFixed(3)}s absMinRms=${absMinRms.toStringAsFixed(4)} '
        'minConfWrong=${minConfForWrong.toStringAsFixed(2)} debounce=${eventDebounceSec.toStringAsFixed(3)}s '
        'wrongCooldown=${wrongFlashCooldownSec.toStringAsFixed(3)}s uiHold=${uiHoldMs}ms',
      );
    }
  }

  /// Process audio chunk: detect pitch, store event, match notes
  List<NoteDecision> onAudioChunk(
    List<int> rawSamples,
    DateTime now,
    double elapsedSec,
  ) {
    final decisions = <NoteDecision>[];

    // 1) Detect channels/sampleRate once
    if (_detectedChannels == null || _detectedSampleRate == null) {
      _detectAudioConfig(rawSamples, elapsedSec);
    }

    // 2) Downmix if stereo
    final samples = _detectedChannels == 2
        ? _downmixStereo(rawSamples)
        : rawSamples.map((s) => s.toDouble()).toList();

    if (samples.isEmpty) return decisions;

    // 3) Detect pitch
    final freq = detectPitch(samples, _detectedSampleRate!.toDouble());

    // 4) Gate: freq range + RMS
    if (freq < 50.0 || freq > 2000.0) return decisions;

    final rms = _computeRms(samples);
    if (rms < absMinRms) return decisions;

    final midi = _freqToMidi(freq);
    final conf = (rms / 0.05).clamp(0.0, 1.0); // Normalize RMS to confidence

    // 5) Anti-spam: skip if same midi within debounce window
    if (_events.isNotEmpty) {
      final last = _events.last;
      if ((elapsedSec - last.tSec).abs() < eventDebounceSec &&
          last.midi == midi) {
        return decisions;
      }
    }

    // 6) Store event
    _events.add(
      PitchEvent(
        tSec: elapsedSec,
        midi: midi,
        freq: freq,
        conf: conf,
        rms: rms,
      ),
    );

    // Prune old events (keep 2.0s)
    _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);

    // 7) Update UI midi (hold 200ms)
    _uiMidi = midi;
    _uiMidiSetAt = now;

    // 8) Match notes
    decisions.addAll(_matchNotes(elapsedSec, now));

    return decisions;
  }

  void _detectAudioConfig(List<int> samples, double elapsedSec) {
    if (_configLogged) return;

    // Heuristic: if samples.length > typical mono frame size → stereo
    // Typical: 44100Hz × 0.1s = 4410 samples mono, 8820 stereo
    final isStereo = samples.length > 6000;
    _detectedChannels = isStereo ? 2 : 1;

    // Estimate sample rate from buffer size and elapsed
    // inputRate = samples.length / dt
    // sr = inputRate / channels
    final dtApprox = 0.1; // Assume ~100ms chunks
    final inputRate = samples.length / dtApprox;
    final sr = (inputRate / _detectedChannels!).round();
    _detectedSampleRate = sr.clamp(32000, 52000);

    if (kDebugMode) {
      debugPrint(
        'MIC_INPUT sessionId=$_sessionId channels=$_detectedChannels '
        'sampleRate=$_detectedSampleRate inputRate=${inputRate.toStringAsFixed(0)} '
        'samplesLen=${samples.length}',
      );
    }
    _configLogged = true;
  }

  List<double> _downmixStereo(List<int> samples) {
    final mono = <double>[];
    for (var i = 0; i < samples.length - 1; i += 2) {
      final l = samples[i].toDouble();
      final r = samples[i + 1].toDouble();
      mono.add((l + r) / 2.0);
    }
    return mono;
  }

  double _computeRms(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    return sqrt(sum / samples.length);
  }

  int _freqToMidi(double freq) {
    return (12 * (log(freq / 440.0) / ln2) + 69).round();
  }

  List<NoteDecision> _matchNotes(double elapsed, DateTime now) {
    final decisions = <NoteDecision>[];

    // Track best event across all active notes for wrong flash
    PitchEvent? bestEventAcrossAll;
    int? bestMidiAcrossAll;

    for (var idx = 0; idx < noteEvents.length; idx++) {
      if (hitNotes[idx]) continue; // Already resolved

      final note = noteEvents[idx];
      final windowStart = note.start - headWindowSec;
      final windowEnd = note.end + tailWindowSec;

      // Check timeout MISS
      if (elapsed > windowEnd) {
        hitNotes[idx] = true;
        decisions.add(
          NoteDecision(
            type: DecisionType.miss,
            noteIndex: idx,
            expectedMidi: note.pitch,
            window: (windowStart, windowEnd),
            reason: 'timeout_no_match',
          ),
        );
        if (kDebugMode) {
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] '
            'result=MISS reason=timeout_no_match',
          );
        }
        continue;
      }

      // Check if note is active
      if (elapsed < windowStart) continue;

      // Find best match in event buffer
      PitchEvent? bestEvent;
      int? bestTestMidi;
      double bestDistance = double.infinity;

      for (final event in _events) {
        if (event.tSec < windowStart || event.tSec > windowEnd) continue;

        // Test direct midi
        final distDirect = (event.midi - note.pitch).abs().toDouble();
        if (distDirect < bestDistance) {
          bestDistance = distDirect;
          bestEvent = event;
          bestTestMidi = event.midi;
        }

        // Test octave correction: ±12 semitones BUT bring back to expected octave
        for (final shift in [-12, 12]) {
          final testMidi = event.midi + shift;
          final distOctave = (testMidi - note.pitch).abs().toDouble();
          if (distOctave < bestDistance) {
            bestDistance = distOctave;
            bestEvent = event;
            bestTestMidi = testMidi; // Corrected midi
          }
        }
      }

      // Track best event across all notes for wrong flash
      if (bestEvent != null &&
          (bestEventAcrossAll == null ||
              bestEvent.conf > bestEventAcrossAll.conf)) {
        bestEventAcrossAll = bestEvent;
        bestMidiAcrossAll = bestTestMidi;
      }

      // Check HIT
      if (bestEvent != null && bestDistance <= 1.0) {
        hitNotes[idx] = true;
        decisions.add(
          NoteDecision(
            type: DecisionType.hit,
            noteIndex: idx,
            expectedMidi: note.pitch,
            detectedMidi: bestTestMidi,
            confidence: bestEvent.conf,
            dtSec: bestEvent.tSec - note.start,
            window: (windowStart, windowEnd),
          ),
        );

        if (kDebugMode) {
          final isOctave = (bestTestMidi! - bestEvent.midi).abs() == 12;
          final reason = isOctave ? 'pitch_match_octave' : 'pitch_match';
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} detectedMidi=$bestTestMidi freq=${bestEvent.freq.toStringAsFixed(1)} '
            'conf=${bestEvent.conf.toStringAsFixed(2)} dt=${(bestEvent.tSec - note.start).toStringAsFixed(3)}s '
            'window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] result=HIT reason=$reason',
          );
        }
      }
    }

    // Wrong flash: if best event exists but no hit, trigger wrong flash (throttled)
    if (bestEventAcrossAll != null &&
        bestEventAcrossAll.conf >= minConfForWrong &&
        decisions.where((d) => d.type == DecisionType.hit).isEmpty) {
      final canFlash =
          _lastWrongFlashAt == null ||
          now.difference(_lastWrongFlashAt!).inMilliseconds >
              (wrongFlashCooldownSec * 1000);

      if (canFlash) {
        decisions.add(
          NoteDecision(
            type: DecisionType.wrongFlash,
            detectedMidi: bestMidiAcrossAll,
            confidence: bestEventAcrossAll.conf,
          ),
        );
        _lastWrongFlashAt = now;
      }
    }

    return decisions;
  }
}

class NoteEvent {
  const NoteEvent({
    required this.start,
    required this.end,
    required this.pitch,
  });
  final double start;
  final double end;
  final int pitch;
}

class PitchEvent {
  const PitchEvent({
    required this.tSec,
    required this.midi,
    required this.freq,
    required this.conf,
    required this.rms,
  });
  final double tSec;
  final int midi;
  final double freq;
  final double conf;
  final double rms;
}

enum DecisionType { hit, miss, wrongFlash }

class NoteDecision {
  const NoteDecision({
    required this.type,
    this.noteIndex,
    this.expectedMidi,
    this.detectedMidi,
    this.confidence,
    this.dtSec,
    this.window,
    this.reason,
  });

  final DecisionType type;
  final int? noteIndex;
  final int? expectedMidi;
  final int? detectedMidi;
  final double? confidence;
  final double? dtSec;
  final (double, double)? window;
  final String? reason;
}
