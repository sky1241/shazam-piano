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
    this.pitchWindowSize = 2048,
    this.minPitchIntervalMs = 40,
    this.verboseDebug = false,
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
  final int pitchWindowSize;
  final int minPitchIntervalMs;
  final bool verboseDebug;

  String? _sessionId;
  final List<PitchEvent> _events = [];
  int _detectedChannels = 1;
  int _detectedSampleRate = 44100;
  bool _configLogged = false;

  DateTime? _lastChunkTime;
  double? _sampleRateEmaHz;
  DateTime? _lastPitchAt;

  // FIX BUG CRITIQUE: Expose detected sample rate for calibration/tests
  int get detectedSampleRate => _detectedSampleRate;

  final List<double> _sampleBuffer = <double>[];
  Float32List? _pitchWindow;

  double? _lastFreqHz;
  double? _lastRms;
  double? _lastConfidence;
  int? _lastMidi;

  double? get lastFreqHz => _lastFreqHz;
  double? get lastRms => _lastRms;
  double? get lastConfidence => _lastConfidence;
  int? get lastMidi => _lastMidi;

  // UI state (hold last valid midi 200ms)
  int? _uiMidi;
  DateTime? _uiMidiSetAt;

  // Wrong flash throttle
  DateTime? _lastWrongFlashAt;

  // Stability tracking: pitchClass → consecutive count
  final Map<int, int> _pitchClassStability = {};
  int? _lastDetectedPitchClass;

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
    _detectedChannels = 1;
    _detectedSampleRate = 44100;
    _configLogged = false;
    _lastChunkTime = null;
    _sampleRateEmaHz = null;
    _lastPitchAt = null;
    _sampleBuffer.clear();
    _pitchWindow = null;
    _lastFreqHz = null;
    _lastRms = null;
    _lastConfidence = null;
    _lastMidi = null;
    _uiMidi = null;
    _uiMidiSetAt = null;
    _lastWrongFlashAt = null;
    _pitchClassStability.clear();
    _lastDetectedPitchClass = null;

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
    List<double> rawSamples,
    DateTime now,
    double elapsedSec,
  ) {
    // Update audio config (sampleRate/channels) using real callback cadence.
    _detectAudioConfig(rawSamples, now);

    // Downmix if stereo interleaved.
    final samples = _detectedChannels == 2
        ? _downmixStereo(rawSamples)
        : rawSamples;

    // Keep a fixed-size rolling window for pitch detection (MPM requires bufferSize).
    if (samples.isNotEmpty) {
      _sampleBuffer.addAll(samples);
      if (_sampleBuffer.length > pitchWindowSize) {
        _sampleBuffer.removeRange(0, _sampleBuffer.length - pitchWindowSize);
      }
    }

    final decisions = <NoteDecision>[];

    final rms = samples.isEmpty ? 0.0 : _computeRms(samples);
    _lastRms = rms;

    final canComputePitch =
        pitchWindowSize > 0 &&
        _sampleBuffer.length >= pitchWindowSize &&
        rms >= absMinRms &&
        (_lastPitchAt == null ||
            now.difference(_lastPitchAt!).inMilliseconds >= minPitchIntervalMs);

    if (canComputePitch) {
      _lastPitchAt = now;
      final window = _pitchWindow ??= Float32List(pitchWindowSize);
      final start = _sampleBuffer.length - pitchWindowSize;
      for (var i = 0; i < pitchWindowSize; i++) {
        window[i] = _sampleBuffer[start + i];
      }

      final freqRaw = detectPitch(window, _detectedSampleRate.toDouble());
      // FIX BUG 3 CRITICAL: Compensate frequency for sampleRate mismatch
      // If device records at 49344 Hz but algorithm expects 44100 Hz,
      // detected frequency is off by ratio 49344/44100 = 1.119 → +1.95 semitones
      // Correction: freq_real = freq_detected * (44100 / detectedSampleRate)
      const expectedSampleRate = 44100;
      final freq = freqRaw > 0
          ? freqRaw * (expectedSampleRate / _detectedSampleRate)
          : 0.0;

      if (freq > 0 && freq >= 50.0 && freq <= 2000.0) {
        final midi = _freqToMidi(freq);
        final conf = (rms / 0.05).clamp(0.0, 1.0);

        _lastFreqHz = freq;
        _lastConfidence = conf;
        _lastMidi = midi;

        // Track pitch class stability (consecutive detections)
        final pitchClass = midi % 12;
        if (_lastDetectedPitchClass == pitchClass) {
          _pitchClassStability[pitchClass] =
              (_pitchClassStability[pitchClass] ?? 0) + 1;
        } else {
          _pitchClassStability.clear();
          _pitchClassStability[pitchClass] = 1;
          _lastDetectedPitchClass = pitchClass;
        }

        // Anti-spam: skip if same midi within debounce window
        if (_events.isNotEmpty) {
          final last = _events.last;
          if ((elapsedSec - last.tSec).abs() < eventDebounceSec &&
              last.midi == midi) {
            _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);
            decisions.addAll(_matchNotes(elapsedSec, now));
            _lastChunkTime = now;
            return decisions;
          }
        }

        final stabilityFrames = _pitchClassStability[pitchClass] ?? 1;
        _events.add(
          PitchEvent(
            tSec: elapsedSec,
            midi: midi,
            freq: freq,
            conf: conf,
            rms: rms,
            stabilityFrames: stabilityFrames,
          ),
        );

        // UI state (hold last valid midi 200ms)
        _uiMidi = midi;
        _uiMidiSetAt = now;
      }
    }

    // Prune old events (keep 2.0s), then match notes even if no new pitch event
    // so MISS decisions still fire when the user stays silent.
    _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);
    decisions.addAll(_matchNotes(elapsedSec, now));

    _lastChunkTime = now;
    return decisions;
  }

  void _detectAudioConfig(List<double> samples, DateTime now) {
    // Keep updating the estimate; _configLogged only gates one-time logging.

    // Heuristic: if samples.length > typical mono frame size → stereo
    // Typical: 44100Hz × 0.1s = 4410 samples mono, 8820 stereo
    if (_lastChunkTime == null) {
      return;
    }

    final dtUs = now.difference(_lastChunkTime!).inMicroseconds;
    if (dtUs <= 0) {
      return;
    }

    final dtSec = dtUs / 1000000.0;
    if (dtSec < 0.008 || dtSec > 0.2) {
      return;
    }
    final inputRate = samples.length / dtSec;

    // Infer stereo when total input rate is roughly 2x a plausible mono SR.
    // Threshold chosen to avoid false positives from scheduling jitter.
    final channels = inputRate >= 60000 ? 2 : 1;
    if (channels != _detectedChannels) {
      _sampleBuffer.clear();
      _pitchWindow = null;
    }
    _detectedChannels = channels;

    final srInstant = inputRate / channels;
    _sampleRateEmaHz = _sampleRateEmaHz == null
        ? srInstant
        : (_sampleRateEmaHz! * 0.9 + srInstant * 0.1);
    _detectedSampleRate = _sampleRateEmaHz!.round().clamp(32000, 52000);

    if (!_configLogged && kDebugMode) {
      // PROOF log: calculate semitone shift if mismatch
      const expectedSampleRate = 44100;
      final ratio = _detectedSampleRate / expectedSampleRate;
      final semitoneShift = 12 * (log(ratio) / ln2);
      debugPrint(
        'MIC_INPUT sessionId=$_sessionId channels=$_detectedChannels '
        'sampleRate=$_detectedSampleRate inputRate=${inputRate.toStringAsFixed(0)} '
        'samplesLen=${samples.length} dtSec=${dtSec.toStringAsFixed(3)} '
        'expectedSR=44100 ratio=${ratio.toStringAsFixed(3)} semitoneShift=${semitoneShift.toStringAsFixed(2)}',
      );
      _configLogged = true;
    }
  }

  List<double> _downmixStereo(List<double> samples) {
    final mono = <double>[];
    for (var i = 0; i < samples.length - 1; i += 2) {
      final l = samples[i];
      final r = samples[i + 1];
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

    // CRITICAL FIX: Guard against hitNotes/noteEvents desync
    // Can occur if notes reloaded or list reassigned during active session
    if (hitNotes.length != noteEvents.length) {
      if (verboseDebug && kDebugMode) {
        debugPrint(
          'SCORING_DESYNC sessionId=$_sessionId hitNotes=${hitNotes.length} noteEvents=${noteEvents.length} ABORT',
        );
      }
      return decisions; // Abort scoring to prevent crash
    }

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

      // Declare expectedPitchClass early for logging
      final expectedPitchClass = note.pitch % 12;

      // Log event buffer state for this note (debug)
      if (kDebugMode) {
        final eventsInWindow = _events
            .where((e) => e.tSec >= windowStart && e.tSec <= windowEnd)
            .toList();
        final pitchClasses = eventsInWindow
            .map((e) => e.midi % 12)
            .toSet()
            .join(',');
        debugPrint(
          'BUFFER_STATE sessionId=$_sessionId noteIdx=$idx expectedMidi=${note.pitch} expectedPC=$expectedPitchClass '
          'window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] '
          'eventsInWindow=${eventsInWindow.length} totalEvents=${_events.length} '
          'pitchClassesInWindow=[$pitchClasses]',
        );
      }

      // Find best match in event buffer with DETAILED REJECT LOGGING
      PitchEvent? bestEvent;
      double bestDistance = double.infinity;
      String? rejectReason; // Track why events were rejected

      for (final event in _events) {
        // Reject: out of time window
        if (event.tSec < windowStart || event.tSec > windowEnd) {
          if (verboseDebug && kDebugMode && rejectReason == null) {
            rejectReason = 'out_of_window';
          }
          continue;
        }

        // Reject: low stability (< 1 frame = impossible, so accept all)
        // Note: Piano with real mic is often unstable, requiring only 1 frame
        if (event.stabilityFrames < 1) {
          if (verboseDebug && kDebugMode && rejectReason == null) {
            rejectReason = 'low_stability_frames=${event.stabilityFrames}';
          }
          continue;
        }

        final detectedPitchClass = event.midi % 12;

        // Reject: pitch class mismatch
        if (detectedPitchClass != expectedPitchClass) {
          if (verboseDebug && kDebugMode && rejectReason == null) {
            rejectReason =
                'pitch_class_mismatch_expected=$expectedPitchClass-detected=$detectedPitchClass';
          }
          continue;
        }

        // Now we have pitch class match, test direct midi ONLY
        // (octave shifts ±12/±24 disabled to prevent harmonics false hits)
        final distDirect = (event.midi - note.pitch).abs().toDouble();
        if (distDirect < bestDistance) {
          bestDistance = distDirect;
          bestEvent = event;
        }
      }

      // Track best event across all notes for wrong flash
      if (bestEvent != null &&
          (bestEventAcrossAll == null ||
              bestEvent.conf > bestEventAcrossAll.conf)) {
        bestEventAcrossAll = bestEvent;
        bestMidiAcrossAll = bestEvent.midi;
      }

      // Check HIT with very tolerant distance (≤3 semitones for real piano+mic)
      if (bestEvent != null && bestDistance <= 3.0) {
        hitNotes[idx] = true;
        
        // FIX BUG #7 (SESSION4): Calculate dt correctly for long notes
        // For long notes (>500ms), playing DURING the note should be perfect (dt=0)
        // Only penalize if played before note.start or after note.end
        final double dtSec;
        if (bestEvent.tSec < note.start) {
          // Played before note started (early)
          dtSec = bestEvent.tSec - note.start; // negative
        } else if (bestEvent.tSec <= note.end) {
          // Played DURING the note (perfect timing for long notes)
          dtSec = 0.0;
        } else {
          // Played after note ended (late)
          dtSec = bestEvent.tSec - note.end; // positive
        }
        
        decisions.add(
          NoteDecision(
            type: DecisionType.hit,
            noteIndex: idx,
            expectedMidi: note.pitch,
            detectedMidi: bestEvent.midi,
            confidence: bestEvent.conf,
            dtSec: dtSec,
            window: (windowStart, windowEnd),
          ),
        );

        if (kDebugMode) {
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} expectedPC=$expectedPitchClass detectedMidi=${bestEvent.midi} '
            'freq=${bestEvent.freq.toStringAsFixed(1)} conf=${bestEvent.conf.toStringAsFixed(2)} '
            'stability=${bestEvent.stabilityFrames} distance=${bestDistance.toStringAsFixed(1)} '
            'dt=${dtSec.toStringAsFixed(3)}s '
            'window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] result=HIT',
          );
        }
      } else {
        // LOG REJECT with detailed reason
        if (kDebugMode) {
          final finalReason = bestEvent == null
              ? (rejectReason ?? 'no_events_in_buffer')
              : 'distance_too_large=${bestDistance.toStringAsFixed(1)}_threshold=3.0';
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} expectedPC=$expectedPitchClass '
            'window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] '
            'result=REJECT reason=$finalReason '
            'bestEvent=${bestEvent != null ? "midi=${bestEvent.midi} freq=${bestEvent.freq.toStringAsFixed(1)} conf=${bestEvent.conf.toStringAsFixed(2)} stability=${bestEvent.stabilityFrames}" : "null"}',
          );
        }
      }
    }

    // Wrong flash: if best event exists but no hit, trigger wrong flash (throttled)
    // FIX: Only trigger wrongFlash if there was at least one active note in window
    // (prevents phantom red keys after all notes have been played)
    final hasActiveNoteInWindow = noteEvents.asMap().entries.any((entry) {
      final idx = entry.key;
      final note = entry.value;
      if (hitNotes[idx]) return false; // Already hit
      final windowStart = note.start - headWindowSec;
      final windowEnd = note.end + tailWindowSec;
      return elapsed >= windowStart && elapsed <= windowEnd;
    });

    if (bestEventAcrossAll != null &&
        bestEventAcrossAll.conf >= minConfForWrong &&
        decisions.where((d) => d.type == DecisionType.hit).isEmpty &&
        hasActiveNoteInWindow) {
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
    required this.stabilityFrames,
  });
  final double tSec;
  final int midi;
  final double freq;
  final double conf;
  final double rms;
  final int stabilityFrames;
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
