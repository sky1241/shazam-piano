import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../pitch/mic_tuning.dart';

/// Résultat de la détection acoustique de la pièce.
class RoomDetectionResult {
  const RoomDetectionResult({
    required this.profile,
    required this.decayTimeMs,
    required this.ambientNoiseRms,
    required this.confidence,
    required this.detectionMethod,
  });

  /// Profil de réverbération détecté.
  final ReverbProfile profile;

  /// Temps de décroissance estimé (ms pour -20dB).
  final double decayTimeMs;

  /// Niveau de bruit ambiant (RMS).
  final double ambientNoiseRms;

  /// Confiance de la détection (0.0-1.0).
  final double confidence;

  /// Méthode utilisée pour la détection.
  final String detectionMethod;

  @override
  String toString() {
    return 'RoomDetectionResult(profile=${profile.name}, '
        'decayTime=${decayTimeMs.toStringAsFixed(0)}ms, '
        'noise=${ambientNoiseRms.toStringAsFixed(4)}, '
        'confidence=${confidence.toStringAsFixed(2)})';
  }
}

/// Seuils de classification pour la réverbération.
abstract class _RoomThresholds {
  /// Decay < 300ms = pièce sèche (low reverb).
  static const double lowMaxDecayMs = 300.0;

  /// Decay 300-800ms = pièce normale (medium reverb).
  static const double mediumMaxDecayMs = 800.0;

  /// Decay > 800ms = espace réverbérant (high reverb).
  // (implicite: > mediumMaxDecayMs)

  /// RMS minimum pour considérer qu'une note a été jouée.
  static const double noteMinRms = 0.02;

  /// Ratio de décroissance pour mesurer le decay (-20dB ≈ 0.1).
  static const double decayRatio = 0.1;
}

/// Service de détection automatique du profil acoustique de la pièce.
///
/// Analyse le decay time après une note franche pour estimer
/// la réverbération de l'environnement.
class RoomDetector {
  RoomDetector();

  /// Détecte le profil de réverbération en analysant le decay d'une note.
  ///
  /// [audioStream] : Stream de chunks audio Float32List.
  /// [sampleRate] : Taux d'échantillonnage (ex: 44100).
  /// [maxDuration] : Durée max d'écoute.
  ///
  /// L'utilisateur doit jouer une note franche pendant l'écoute.
  /// La détection mesure le temps de décroissance du signal.
  Future<RoomDetectionResult> detectFromNoteDecay({
    required Stream<Float32List> audioStream,
    required double sampleRate,
    Duration maxDuration = const Duration(seconds: 5),
  }) async {
    final rmsHistory = <_RmsSample>[];
    final completer = Completer<RoomDetectionResult>();

    // État de la détection
    var state = _DetectionState.waitingForNote;
    double peakRms = 0.0;
    int peakTimeMs = 0;
    double ambientNoiseRms = 0.0;
    final noiseAccumulator = <double>[];

    // Timeout
    final timeout = Timer(maxDuration, () {
      if (!completer.isCompleted) {
        completer.complete(_fallbackResult(ambientNoiseRms));
      }
    });

    StreamSubscription<Float32List>? subscription;
    final startTime = DateTime.now();

    subscription = audioStream.listen((samples) {
      if (completer.isCompleted) {
        subscription?.cancel();
        return;
      }

      final nowMs = DateTime.now().difference(startTime).inMilliseconds;
      final rms = _calculateRms(samples);

      rmsHistory.add(_RmsSample(timeMs: nowMs, rms: rms));

      switch (state) {
        case _DetectionState.waitingForNote:
          // Collecter le bruit ambiant
          if (rms < _RoomThresholds.noteMinRms * 0.5) {
            noiseAccumulator.add(rms);
            if (noiseAccumulator.length >= 10) {
              ambientNoiseRms =
                  noiseAccumulator.reduce((a, b) => a + b) /
                  noiseAccumulator.length;
            }
          }

          // Détecter le début de la note
          if (rms >= _RoomThresholds.noteMinRms) {
            peakRms = rms;
            peakTimeMs = nowMs;
            state = _DetectionState.trackingPeak;
            if (kDebugMode) {
              debugPrint(
                'RoomDetector: Note detected at ${nowMs}ms, RMS=${rms.toStringAsFixed(4)}',
              );
            }
          }

        case _DetectionState.trackingPeak:
          // Suivre le pic
          if (rms > peakRms) {
            peakRms = rms;
            peakTimeMs = nowMs;
          } else if (rms < peakRms * 0.7) {
            // Le pic est passé, commencer à mesurer le decay
            state = _DetectionState.measuringDecay;
            if (kDebugMode) {
              debugPrint(
                'RoomDetector: Peak passed at ${nowMs}ms, peakRms=${peakRms.toStringAsFixed(4)}',
              );
            }
          }

        case _DetectionState.measuringDecay:
          // Mesurer le decay time
          final decayThreshold = peakRms * _RoomThresholds.decayRatio;

          if (rms <= decayThreshold || rms <= ambientNoiseRms * 1.5) {
            // Le signal a suffisamment décru
            final decayTimeMs = (nowMs - peakTimeMs).toDouble();
            final profile = _classifyFromDecayTime(decayTimeMs);
            final confidence = _calculateConfidence(
              peakRms: peakRms,
              ambientNoiseRms: ambientNoiseRms,
              decayTimeMs: decayTimeMs,
            );

            if (kDebugMode) {
              debugPrint(
                'RoomDetector: Decay complete - decayTime=${decayTimeMs.toStringAsFixed(0)}ms, '
                'profile=${profile.name}, confidence=${confidence.toStringAsFixed(2)}',
              );
            }

            timeout.cancel();
            subscription?.cancel();

            completer.complete(
              RoomDetectionResult(
                profile: profile,
                decayTimeMs: decayTimeMs,
                ambientNoiseRms: ambientNoiseRms,
                confidence: confidence,
                detectionMethod: 'note_decay',
              ),
            );
          }
      }
    });

    return completer.future;
  }

  /// Mesure uniquement le bruit ambiant (1 seconde de silence).
  Future<double> measureAmbientNoise({
    required Stream<Float32List> audioStream,
    Duration duration = const Duration(seconds: 1),
  }) async {
    final rmsValues = <double>[];
    final completer = Completer<double>();

    final timeout = Timer(duration, () {
      if (!completer.isCompleted) {
        if (rmsValues.isEmpty) {
          completer.complete(0.0);
        } else {
          // Moyenne des valeurs (en ignorant les outliers)
          rmsValues.sort();
          final trimmed = rmsValues.length > 4
              ? rmsValues.sublist(1, rmsValues.length - 1)
              : rmsValues;
          final avg = trimmed.reduce((a, b) => a + b) / trimmed.length;
          completer.complete(avg);
        }
      }
    });

    StreamSubscription<Float32List>? subscription;
    subscription = audioStream.listen((samples) {
      if (completer.isCompleted) {
        subscription?.cancel();
        return;
      }

      final rms = _calculateRms(samples);
      rmsValues.add(rms);
    });

    final result = await completer.future;
    timeout.cancel();
    await subscription.cancel();
    return result;
  }

  /// Analyse un historique RMS pour estimer le decay time.
  /// Utilisé pour l'analyse post-hoc.
  double analyzeDecayTime(List<double> rmsHistory, {double? sampleIntervalMs}) {
    if (rmsHistory.length < 10) return 500.0; // Pas assez de données

    // Trouver le pic
    var peakIndex = 0;
    var peakRms = 0.0;
    for (var i = 0; i < rmsHistory.length; i++) {
      if (rmsHistory[i] > peakRms) {
        peakRms = rmsHistory[i];
        peakIndex = i;
      }
    }

    // Trouver le moment où le signal décroît à 10% du pic
    final decayThreshold = peakRms * _RoomThresholds.decayRatio;
    var decayIndex = peakIndex;
    for (var i = peakIndex; i < rmsHistory.length; i++) {
      if (rmsHistory[i] <= decayThreshold) {
        decayIndex = i;
        break;
      }
    }

    final interval =
        sampleIntervalMs ?? 23.0; // ~44100 samples / 1024 = 43Hz ≈ 23ms
    return (decayIndex - peakIndex) * interval;
  }

  /// Classifie le profil de réverbération selon le decay time.
  ReverbProfile _classifyFromDecayTime(double decayTimeMs) {
    if (decayTimeMs < _RoomThresholds.lowMaxDecayMs) {
      return ReverbProfile.low;
    } else if (decayTimeMs < _RoomThresholds.mediumMaxDecayMs) {
      return ReverbProfile.medium;
    } else {
      return ReverbProfile.high;
    }
  }

  /// Calcule la confiance de la détection.
  double _calculateConfidence({
    required double peakRms,
    required double ambientNoiseRms,
    required double decayTimeMs,
  }) {
    // Plus le ratio signal/bruit est élevé, plus on est confiant
    final snr = ambientNoiseRms > 0 ? peakRms / ambientNoiseRms : 10.0;

    // Confiance basée sur SNR
    var confidence = (snr / 20.0).clamp(0.3, 1.0);

    // Pénalité si le decay est très court ou très long (moins fiable)
    if (decayTimeMs < 100 || decayTimeMs > 2000) {
      confidence *= 0.7;
    }

    return confidence;
  }

  /// Calcule le RMS d'un buffer audio.
  double _calculateRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / samples.length);
  }

  /// Résultat par défaut si la détection échoue.
  RoomDetectionResult _fallbackResult(double ambientNoiseRms) {
    if (kDebugMode) {
      debugPrint('RoomDetector: Using fallback (medium profile)');
    }
    return RoomDetectionResult(
      profile: ReverbProfile.medium,
      decayTimeMs: 500.0,
      ambientNoiseRms: ambientNoiseRms,
      confidence: 0.3,
      detectionMethod: 'fallback',
    );
  }
}

/// État interne de la détection.
enum _DetectionState { waitingForNote, trackingPeak, measuringDecay }

/// Sample RMS avec timestamp.
class _RmsSample {
  const _RmsSample({required this.timeMs, required this.rms});
  final int timeMs;
  final double rms;
}
