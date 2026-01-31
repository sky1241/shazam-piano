/// UI Feedback Engine - Moteur de feedback perceptif "jeu vidéo"
///
/// SESSION-056: REFONTE COMPLÈTE - Source de vérité = PERCEPTION utilisateur
///
/// Règles SIMPLES:
/// - BLEU = Ce que le micro détecte (immédiat, <50ms)
/// - CYAN = Ce que la partition attend (notes en cours)
/// - VERT = BLEU ∩ CYAN (même pitch class, octave flexible)
/// - ROUGE = BLEU actif sans CYAN proche
///
/// SUPPRIMÉ de la boucle feedback:
/// - DecisionArbiter
/// - pointerIdx
/// - Fenêtres [t0..t1]
/// - Matching strict dist≤3
///
/// Le scoring reste séparé (hors boucle temps réel)
library;

import 'package:flutter/foundation.dart';

/// État du feedback UI à un instant t
class UIFeedbackState {
  /// Note BLEU (détection micro brute)
  final int? blueMidi;

  /// Notes CYAN (partition en cours - peut être multiple pour accords)
  final Set<int> cyanMidis;

  /// Note VERT (succès - BLEU ∩ CYAN)
  final int? greenMidi;

  /// Note ROUGE (erreur - BLEU sans CYAN proche)
  final int? redMidi;

  /// Timestamp de dernière mise à jour (ms depuis epoch)
  final int timestampMs;

  /// Confidence du pitch detector (0.0-1.0)
  final double confidence;

  const UIFeedbackState({
    this.blueMidi,
    this.cyanMidis = const {},
    this.greenMidi,
    this.redMidi,
    this.timestampMs = 0,
    this.confidence = 0.0,
  });

  /// État vide (aucun feedback)
  static const empty = UIFeedbackState();

  /// Copie avec modifications
  UIFeedbackState copyWith({
    int? blueMidi,
    Set<int>? cyanMidis,
    int? greenMidi,
    int? redMidi,
    int? timestampMs,
    double? confidence,
    bool clearBlue = false,
    bool clearGreen = false,
    bool clearRed = false,
  }) {
    return UIFeedbackState(
      blueMidi: clearBlue ? null : (blueMidi ?? this.blueMidi),
      cyanMidis: cyanMidis ?? this.cyanMidis,
      greenMidi: clearGreen ? null : (greenMidi ?? this.greenMidi),
      redMidi: clearRed ? null : (redMidi ?? this.redMidi),
      timestampMs: timestampMs ?? this.timestampMs,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() {
    return 'UIFeedback(blue=$blueMidi cyan=$cyanMidis green=$greenMidi red=$redMidi conf=${confidence.toStringAsFixed(2)})';
  }
}

/// Moteur de feedback UI perceptif
///
/// Règle d'or: Quand l'utilisateur agit, l'UI réagit IMMÉDIATEMENT.
class UIFeedbackEngine {
  UIFeedbackEngine({
    this.onStateChanged,
  });

  /// Callback appelé à chaque changement d'état
  final void Function(UIFeedbackState)? onStateChanged;

  /// État courant
  UIFeedbackState _state = UIFeedbackState.empty;
  UIFeedbackState get state => _state;

  /// Dernière note BLEU avec son timestamp (pour debounce)
  int? _lastBlueMidi;
  int _lastBlueTimestampMs = 0;

  /// Dernier VERT avec timestamp (pour durée flash)
  int? _lastGreenMidi;
  int _lastGreenTimestampMs = 0;

  /// Dernier ROUGE avec timestamp (pour durée flash)
  int? _lastRedMidi;
  int _lastRedTimestampMs = 0;

  /// Compteur VERT pour debug (succès perceptifs)
  int _greenCount = 0;
  int get greenCount => _greenCount;

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Durée du flash VERT (ms)
  static const int greenFlashDurationMs = 200;

  /// Durée du flash ROUGE (ms)
  static const int redFlashDurationMs = 200;

  /// Debounce BLEU (ms) - évite le flickering
  static const int blueDebounceMs = 30;

  /// Seuil de confidence minimum pour afficher BLEU
  static const double minConfidenceForBlue = 0.5;

  /// Tolérance pitch class pour VERT (±2 demi-tons autour de l'octave)
  /// Cela permet d'accepter les octaves ±1 et ±2
  static const int pitchClassTolerance = 2;

  // ══════════════════════════════════════════════════════════════════════════
  // API PRINCIPALE
  // ══════════════════════════════════════════════════════════════════════════

  /// Met à jour le feedback avec une nouvelle détection pitch
  ///
  /// [detectedMidi] - Note MIDI détectée par le micro (null si silence)
  /// [confidence] - Confidence du pitch detector (0.0-1.0)
  /// [expectedMidis] - Notes MIDI attendues par la partition (peut être vide)
  /// [nowMs] - Timestamp courant en millisecondes
  void update({
    required int? detectedMidi,
    required double confidence,
    required Set<int> expectedMidis,
    required int nowMs,
  }) {
    // ══════════════════════════════════════════════════════════════════════
    // 1. CYAN = Notes attendues (toujours à jour)
    // ══════════════════════════════════════════════════════════════════════
    final cyanMidis = Set<int>.from(expectedMidis);

    // ══════════════════════════════════════════════════════════════════════
    // 2. BLEU = Détection micro (immédiat si confidence OK)
    // ══════════════════════════════════════════════════════════════════════
    int? blueMidi;
    if (detectedMidi != null && confidence >= minConfidenceForBlue) {
      // Debounce: éviter le flickering
      final sameNote = detectedMidi == _lastBlueMidi;
      final tooSoon = (nowMs - _lastBlueTimestampMs) < blueDebounceMs;

      if (!sameNote || !tooSoon) {
        blueMidi = detectedMidi;
        _lastBlueMidi = detectedMidi;
        _lastBlueTimestampMs = nowMs;
      } else {
        // Même note, pas assez de temps écoulé - garder l'ancien
        blueMidi = _lastBlueMidi;
      }
    } else if (_lastBlueMidi != null) {
      // Plus de détection - effacer après debounce
      final elapsed = nowMs - _lastBlueTimestampMs;
      if (elapsed < blueDebounceMs * 2) {
        // Garder un peu pour éviter le clignotement
        blueMidi = _lastBlueMidi;
      } else {
        blueMidi = null;
        _lastBlueMidi = null;
      }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 3. VERT = BLEU ∩ CYAN (même pitch class, octave flexible)
    // ══════════════════════════════════════════════════════════════════════
    int? greenMidi;
    if (blueMidi != null && cyanMidis.isNotEmpty) {
      final matchedCyan = _findPitchClassMatch(blueMidi, cyanMidis);
      if (matchedCyan != null) {
        greenMidi = blueMidi;
        if (_lastGreenMidi != blueMidi) {
          _lastGreenMidi = blueMidi;
          _lastGreenTimestampMs = nowMs;
          _greenCount++;
          if (kDebugMode) {
            debugPrint(
              'UI_GREEN_HIT blue=$blueMidi cyan=$matchedCyan pitchClass=${blueMidi % 12} '
              'greenCount=$_greenCount nowMs=$nowMs',
            );
          }
        }
      }
    }

    // Gérer expiration du flash VERT
    if (_lastGreenMidi != null) {
      final elapsed = nowMs - _lastGreenTimestampMs;
      if (elapsed > greenFlashDurationMs) {
        _lastGreenMidi = null;
        greenMidi = null;
      } else {
        // Flash encore actif
        greenMidi ??= _lastGreenMidi;
      }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 4. ROUGE = BLEU sans CYAN proche (erreur claire)
    // ══════════════════════════════════════════════════════════════════════
    int? redMidi;
    if (blueMidi != null && greenMidi == null && cyanMidis.isNotEmpty) {
      // BLEU actif mais pas de VERT (pas de match pitch class)
      // = L'utilisateur joue quelque chose qui n'est pas attendu
      final hasAnyNearby = _hasNearbyNote(blueMidi, cyanMidis);
      if (!hasAnyNearby) {
        redMidi = blueMidi;
        if (_lastRedMidi != blueMidi) {
          _lastRedMidi = blueMidi;
          _lastRedTimestampMs = nowMs;
          if (kDebugMode) {
            debugPrint(
              'UI_RED_ERROR blue=$blueMidi cyan=$cyanMidis pitchClass=${blueMidi % 12} '
              'nowMs=$nowMs',
            );
          }
        }
      }
    }

    // Gérer expiration du flash ROUGE
    if (_lastRedMidi != null) {
      final elapsed = nowMs - _lastRedTimestampMs;
      if (elapsed > redFlashDurationMs) {
        _lastRedMidi = null;
        redMidi = null;
      } else {
        // Flash encore actif
        redMidi ??= _lastRedMidi;
      }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 5. Construire nouvel état
    // ══════════════════════════════════════════════════════════════════════
    final newState = UIFeedbackState(
      blueMidi: blueMidi,
      cyanMidis: cyanMidis,
      greenMidi: greenMidi,
      redMidi: redMidi,
      timestampMs: nowMs,
      confidence: confidence,
    );

    // Notifier si changement
    if (_hasStateChanged(newState)) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  /// Reset complet de l'état
  void reset() {
    _state = UIFeedbackState.empty;
    _lastBlueMidi = null;
    _lastBlueTimestampMs = 0;
    _lastGreenMidi = null;
    _lastGreenTimestampMs = 0;
    _lastRedMidi = null;
    _lastRedTimestampMs = 0;
    _greenCount = 0;
    onStateChanged?.call(_state);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS PRIVÉS
  // ══════════════════════════════════════════════════════════════════════════

  /// Trouve un match pitch class dans les notes CYAN
  /// Retourne la note CYAN matchée ou null
  int? _findPitchClassMatch(int blueMidi, Set<int> cyanMidis) {
    final bluePC = blueMidi % 12;

    for (final cyan in cyanMidis) {
      final cyanPC = cyan % 12;
      // Match exact pitch class (C=C, D=D, etc.)
      if (bluePC == cyanPC) {
        return cyan;
      }
    }
    return null;
  }

  /// Vérifie s'il y a une note CYAN à proximité (±2 demi-tons)
  /// Utilisé pour éviter les faux ROUGE sur des notes proches
  bool _hasNearbyNote(int blueMidi, Set<int> cyanMidis) {
    for (final cyan in cyanMidis) {
      // Check pitch class match (octave flexible)
      if ((blueMidi % 12) == (cyan % 12)) {
        return true;
      }
      // Check distance directe (pour notes adjacentes)
      final dist = (blueMidi - cyan).abs();
      if (dist <= pitchClassTolerance) {
        return true;
      }
    }
    return false;
  }

  /// Vérifie si l'état a changé de manière significative
  bool _hasStateChanged(UIFeedbackState newState) {
    return _state.blueMidi != newState.blueMidi ||
        _state.greenMidi != newState.greenMidi ||
        _state.redMidi != newState.redMidi ||
        !_setEquals(_state.cyanMidis, newState.cyanMidis);
  }

  /// Compare deux sets
  bool _setEquals(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }
}
