/// UI Feedback Engine - Moteur de feedback perceptif "jeu vidéo"
///
/// SESSION-056: REFONTE COMPLÈTE - Source de vérité = PERCEPTION utilisateur
/// SESSION-057: CORRECTIFS CRITIQUES:
///   - VERT uniquement sur HIT_VALIDÉ (événement externe), pas pitch class match
///   - BLEU/ROUGE utilisent rawMidiForUi (jamais snappé/mergé)
///   - Clear immédiat quand detectedMidi=null (pas de bleu coincé)
/// SESSION-058: CORRECTIFS CLEAR + PRIORITÉ:
///   - CLEAR annule aussi ROUGE (pas seulement BLEU) - rouge dépend du pitch
///   - VERT survit au CLEAR (flash de HIT_VALIDÉ indépendant)
///   - Log UI_CLEAR_TRIGGER inclut prevRed et prevGreen
///   - Priorité rendue: VERT > ROUGE > BLEU > CYAN > NEUTRE
/// SESSION-059 VERT: ANTI-FLICKER - LOI DU SYSTÈME:
///   - TENUE_CONFIRMÉE/RELÂCHÉE_CONFIRMÉE: état robuste aux micro-coupures
///   - validationActive: LATCHÉ à HIT_VALIDÉ, reset uniquement à RELÂCHÉE_CONFIRMÉE
///   - Table de priorité: P1(RELÂCHÉE)>P2(TENUE+ACTIF)>P3(TENUE+INACTIF)>P4(INCONNUE)
///   - Un seul VERT unifié (pas d'alternance entre verts)
///   - Fail-safe: INCONNUE → maintenir état précédent
/// SESSION-059 ROUGE: LOI DU SYSTÈME - MULTI-ROUGE:
///   - redMidis = Set of int (multi-rouge pour accords faux)
///   - MATCH STRICT: midi ∈ expectedMidis uniquement (pas de pitch class)
///   - Arbitrage Source_A (timeline) > Source_B (cyanMidis)
///   - Rouge lié à tenue: apparaît si TENUE_CONFIRMÉE, disparaît à RELÂCHÉE
///   - Rouge générique si aucun expected actif
///   - P1: Vert même touche → BLOQUER / P5: Mismatch+Tenue → SET_ROUGE
///   - _hasNearbyNote() SUPPRIMÉE (match strict imposé)
///
/// Règles CORRIGÉES:
/// - BLEU = rawMidiForUi (note réellement jouée, immédiat)
/// - CYAN = Notes attendues par partition
/// - VERT = TENUE_CONFIRMÉE + validationActive (latché, pas de timer)
/// - ROUGE = note fautive tenue (multi-rouge, match strict, lié à tenue)
///
/// Le scoring reste séparé (hors boucle temps réel)
library;

import 'package:flutter/foundation.dart';

// ════════════════════════════════════════════════════════════════════════════
// SESSION-059: ÉTATS DE TENUE (TenueEvaluator)
// ════════════════════════════════════════════════════════════════════════════

/// État de tenue confirmé (robuste aux micro-coupures)
/// SESSION-059: Jamais évalué frame-par-frame sur pitch instantané
enum TenueState {
  /// Tenue confirmée - l'utilisateur est considéré comme tenant la note
  /// Même si le pitch est absent sur quelques frames (< TOLÉRANCE)
  tenueConfirmee,

  /// Relâche confirmée - absence de pitch > TOLÉRANCE_MICRO_COUPURES
  /// Déclenche SET_ORIGINE immédiat + reset du latch
  relacheeConfirmee,

  /// Impossible de trancher - maintenir état précédent (anti-flicker)
  inconnue,
}

/// État visuel d'une touche clavier (render-only)
/// Priorité: green > red > blue > cyan > neutral
enum KeyVisualState {
  /// VERT - Succès (HIT_VALIDÉ)
  green,

  /// ROUGE - Erreur (rawMidi sans match)
  red,

  /// BLEU - Détection micro (rawMidi)
  blue,

  /// CYAN - Note attendue par partition
  cyan,

  /// Neutre - Touche blanche normale
  neutralWhite,

  /// Neutre - Touche noire normale
  neutralBlack,
}

/// État du feedback UI à un instant t
class UIFeedbackState {
  /// Note BLEU (détection micro brute - rawMidiForUi)
  final int? blueMidi;

  /// Notes CYAN (partition en cours - peut être multiple pour accords)
  final Set<int> cyanMidis;

  /// Note VERT (succès - HIT_VALIDÉ uniquement)
  final int? greenMidi;

  /// Notes ROUGE (erreur - notes fautives tenues)
  /// SESSION-059 ROUGE: Multi-rouge supporté pour accords faux
  final Set<int> redMidis;

  /// Timestamp de dernière mise à jour (ms depuis epoch)
  final int timestampMs;

  /// Confidence du pitch detector (0.0-1.0)
  final double confidence;

  const UIFeedbackState({
    this.blueMidi,
    this.cyanMidis = const {},
    this.greenMidi,
    this.redMidis = const {},
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
    Set<int>? redMidis,
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
      redMidis: clearRed ? const {} : (redMidis ?? this.redMidis),
      timestampMs: timestampMs ?? this.timestampMs,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() {
    return 'UIFeedback(blue=$blueMidi cyan=$cyanMidis green=$greenMidi red=$redMidis conf=${confidence.toStringAsFixed(2)})';
  }
}

/// Moteur de feedback UI perceptif
///
/// SESSION-057: Règle d'or corrigée:
/// - BLEU/ROUGE = rawMidiForUi (note réellement jouée)
/// - VERT = uniquement sur HIT_VALIDÉ
/// - Clear immédiat quand pas de pitch frais
class UIFeedbackEngine {
  UIFeedbackEngine({this.onStateChanged});

  /// Callback appelé à chaque changement d'état
  final void Function(UIFeedbackState)? onStateChanged;

  /// État courant
  UIFeedbackState _state = UIFeedbackState.empty;
  UIFeedbackState get state => _state;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-075: KEYBOARD RANGE FOR CLAMP
  // ══════════════════════════════════════════════════════════════════════════
  // All ROUGE midis are clamped to this range to fix octave detection errors.
  // YIN often detects 1-2 octaves too low/high due to "period doubling".
  // ══════════════════════════════════════════════════════════════════════════
  int _keyboardFirstKey = 21; // A0 (lowest piano key)
  int _keyboardLastKey = 108; // C8 (highest piano key)

  /// Configure the visible keyboard range for ROUGE clamping.
  /// Call this when the keyboard layout is determined.
  void setKeyboardRange(int firstKey, int lastKey) {
    // Only log if values changed (avoid spam)
    final changed = _keyboardFirstKey != firstKey || _keyboardLastKey != lastKey;
    _keyboardFirstKey = firstKey;
    _keyboardLastKey = lastKey;
    if (kDebugMode && changed) {
      debugPrint('UI_FEEDBACK_KEYBOARD_RANGE set to [$firstKey..$lastKey]');
    }
  }

  /// Clamp a MIDI note to the visible keyboard range by shifting octaves.
  int _clampMidiToKeyboard(int midi) {
    if (midi >= _keyboardFirstKey && midi <= _keyboardLastKey) {
      return midi;
    }
    int clamped = midi;
    while (clamped < _keyboardFirstKey) {
      clamped += 12;
    }
    while (clamped > _keyboardLastKey) {
      clamped -= 12;
    }
    // Final safety check
    if (clamped < _keyboardFirstKey || clamped > _keyboardLastKey) {
      return midi; // Fallback to original if clamp failed
    }
    return clamped;
  }

  /// SESSION-076: Clamp a MIDI note to the octave of an expected note.
  /// ONLY if detected MIDI has SAME pitch class (% 12) as an expected note.
  /// This fixes YIN octave errors where E5 is detected as E6 (88 instead of 76).
  /// SESSION-076b: REMOVED octave shift for different pitch classes - that created
  /// phantom reds on notes the user never played (e.g., G5→G4 when F4 expected).
  int _clampToExpectedOctave(int detectedMidi, Set<int> expectedMidis) {
    if (expectedMidis.isEmpty) {
      return detectedMidi; // No expected → keep as-is
    }

    final detectedPitchClass = detectedMidi % 12;

    // Find expected note with same pitch class
    for (final expected in expectedMidis) {
      if (expected % 12 == detectedPitchClass) {
        // Same pitch class! Snap to expected octave
        // This fixes: YIN detects E6 (88) when user played E5 (76) and E5 was expected
        if (kDebugMode && detectedMidi != expected) {
          debugPrint(
            'ROUGE_SNAP_TO_EXPECTED detected=$detectedMidi → expected=$expected '
            '(same pitch class ${_pitchClassName(detectedPitchClass)})',
          );
        }
        return expected;
      }
    }

    // No pitch class match → KEEP ORIGINAL
    // If user played G5 (79) when F4 (65) was expected, show red on G5 (79)
    // NOT on G4 (67) which is a phantom note the user never touched!
    return detectedMidi;
  }

  /// Helper: pitch class name for debug
  String _pitchClassName(int pc) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return names[pc % 12];
  }

  /// Dernière note BLEU avec son timestamp (pour debounce)
  int? _lastBlueMidi;
  int _lastBlueTimestampMs = 0;

  /// Dernier VERT (HIT_VALIDÉ) avec timestamp (pour durée flash)
  /// Note: Utilisé pour tracking interne, lecture future possible
  // ignore: unused_field
  int? _lastGreenMidi;
  int _lastGreenTimestampMs = 0;

  /// SESSION-059 ROUGE: Set des notes actuellement en rouge (multi-rouge)
  Set<int> _currentRedMidis = {};

  /// SESSION-059 ROUGE: Timestamp de dernière activité par midi rouge
  /// Permet de détecter les notes relâchées individuellement en INCONNUE
  final Map<int, int> _redMidiLastActiveMs = {};

  /// Compteur VERT pour debug (succès HIT_VALIDÉ)
  int _greenCount = 0;
  int get greenCount => _greenCount;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-059: TENUE EVALUATOR - État de tenue confirmé
  // ══════════════════════════════════════════════════════════════════════════

  /// Dernier timestamp où un pitch valide a été détecté (pour calcul tolérance)
  int _lastValidPitchTimestampMs = 0;

  /// Timestamp du début de la tenue actuelle (pour savoir si on est en tenue)
  int _tenueStartTimestampMs = 0;

  /// État de tenue actuel (évalué avec tolérance)
  TenueState _tenueState = TenueState.inconnue;

  /// MIDI de la note actuellement tenue (pour tracking par note)
  int? _tenueMidi;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-059: VALIDATION LATCH - État verrouillé jusqu'à relâche
  // ══════════════════════════════════════════════════════════════════════════

  /// validationActive: LATCHÉ à HIT_VALIDÉ, reset uniquement à RELÂCHÉE_CONFIRMÉE
  /// INTERDIT: ne dépend JAMAIS du pitch instantané
  bool _validationActive = false;

  /// MIDI associé au latch actif (pour vérifier que c'est la même note)
  int? _validationLatchMidi;

  /// État visuel précédent du VERT (pour fail-safe INCONNUE → NOOP)
  bool _previousGreenState = false;

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ══════════════════════════════════════════════════════════════════════════

  /// SESSION-059: Tolérance micro-coupures (ms)
  /// Durée maximale d'absence de pitch avant RELÂCHÉE_CONFIRMÉE
  /// PARAMÈTRE À CALIBRER - valeur initiale conservative
  // SESSION-066: 80→200ms for perceptible red flash (research: 150-200ms optimal)
  // Video evidence showed red clearing in 1 frame (~42ms) - imperceptible
  static const int toleranceMicroCoupuresMs = 200;

  /// SESSION-059: Critère d'entrée en tenue (ms de pitch stable)
  /// PARAMÈTRE À CALIBRER - valeur initiale conservative
  static const int critereEntreeTenueMs = 30;

  /// Durée de protection anti-doublon pour notifyHit (ms)
  /// SESSION-059: remplace greenFlashDurationMs pour le check anti-doublon uniquement
  static const int greenHitDebounceMs = 100;

  /// Debounce BLEU (ms) - évite le flickering sur même note
  /// SESSION-057: Réduit car le clear est maintenant piloté par freshness
  static const int blueDebounceMs = 30;

  /// Seuil de confidence minimum pour afficher BLEU
  static const double minConfidenceForBlue = 0.5;

  // ══════════════════════════════════════════════════════════════════════════
  // API PRINCIPALE
  // ══════════════════════════════════════════════════════════════════════════

  /// Met à jour le feedback avec une nouvelle détection pitch
  ///
  /// SESSION-057: [detectedMidi] DOIT être rawMidiForUi (jamais snappé/mergé).
  /// Si null = pas de pitch frais = clear immédiat du BLEU.
  ///
  /// [detectedMidi] - Note MIDI brute détectée (null si silence/stale)
  /// [confidence] - Confidence du pitch detector (0.0-1.0)
  /// [expectedMidis] - Notes MIDI attendues par la partition
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
    // 2. BLEU = rawMidiForUi (immédiat si confidence OK)
    // SESSION-057: Si detectedMidi=null, CLEAR IMMÉDIAT (pas de bleu coincé)
    // ══════════════════════════════════════════════════════════════════════
    int? blueMidi;
    if (detectedMidi != null && confidence >= minConfidenceForBlue) {
      // Debounce: éviter le flickering sur même note
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
    } else {
      // SESSION-057: CLEAR IMMÉDIAT - pas de détection = pas de bleu
      // SESSION-065: ROUGE avec TOLÉRANCE - miroir de l'audio détecté
      // Le rouge ne s'efface PAS immédiatement, il utilise toleranceMicroCoupuresMs
      final hadBlue = _lastBlueMidi != null;
      if (hadBlue && kDebugMode) {
        debugPrint(
          'UI_CLEAR_BLUE reason=${detectedMidi == null ? "no_pitch" : "low_conf"} '
          'prevBlue=$_lastBlueMidi nowMs=$nowMs',
        );
      }
      blueMidi = null;
      _lastBlueMidi = null;

      // SESSION-065: ROUGE avec TOLÉRANCE - effacer uniquement après toleranceMicroCoupuresMs
      // Ceci permet au rouge de "persister" et refléter la durée réelle de l'audio
      if (_currentRedMidis.isNotEmpty) {
        final staleReds = <int>{};
        for (final midi in _currentRedMidis) {
          final lastActive = _redMidiLastActiveMs[midi] ?? 0;
          final elapsed = nowMs - lastActive;
          if (elapsed > toleranceMicroCoupuresMs) {
            staleReds.add(midi);
          }
        }

        if (staleReds.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              'UI_CLEAR_RED_TOLERANCE staleReds=$staleReds '
              'tolerance=${toleranceMicroCoupuresMs}ms nowMs=$nowMs',
            );
          }
          _currentRedMidis.removeAll(staleReds);
          for (final midi in staleReds) {
            _redMidiLastActiveMs.remove(midi);
          }
        }
        // Si tous les rouges sont stale, le set sera vide
        // Sinon, les rouges récents sont préservés (miroir audio)
      }
      // VERT survit au clear (flash de HIT_VALIDÉ indépendant du pitch courant)
    }

    // ══════════════════════════════════════════════════════════════════════
    // 3. SESSION-059: VERT = TABLE P1>P2>P3>P4 (LOI DU SYSTÈME ANTI-FLICKER)
    // ══════════════════════════════════════════════════════════════════════
    //
    // COMPOSANTS:
    // - TenueEvaluator: évalue TENUE_CONFIRMÉE/RELÂCHÉE_CONFIRMÉE avec tolérance
    // - ValidationLatch: ACTIF à HIT_VALIDÉ, INACTIF uniquement à RELÂCHÉE_CONFIRMÉE
    //
    // TABLE DE PRIORITÉ:
    // P1: RELÂCHÉE_CONFIRMÉE → SET_ORIGINE + reset latch
    // P2: TENUE_CONFIRMÉE + validationActive=ACTIF → SET_VERT
    // P3: TENUE_CONFIRMÉE + validationActive=INACTIF → SET_ORIGINE
    // P4: INCONNUE → NOOP (maintenir état précédent)
    // ══════════════════════════════════════════════════════════════════════

    // 3a. TenueEvaluator: Calculer l'état de tenue confirmé
    final tenueState = _evaluateTenueState(
      detectedMidi: detectedMidi,
      confidence: confidence,
      nowMs: nowMs,
    );

    // 3b. Appliquer la table de décision P1>P2>P3>P4
    int? greenMidi;

    if (tenueState == TenueState.relacheeConfirmee) {
      // ══════════════════════════════════════════════════════════════════
      // P1: RELÂCHÉE_CONFIRMÉE → SET_ORIGINE + reset latch
      // ══════════════════════════════════════════════════════════════════
      if (_validationActive && kDebugMode) {
        debugPrint(
          'S59_P1_RELACHEE midi=$_validationLatchMidi '
          'tenueState=$tenueState nowMs=$nowMs → SET_ORIGINE + reset latch',
        );
      }
      greenMidi = null;
      _lastGreenMidi = null;
      // Reset du latch
      _validationActive = false;
      _validationLatchMidi = null;
      _previousGreenState = false;
    } else if (tenueState == TenueState.tenueConfirmee && _validationActive) {
      // ══════════════════════════════════════════════════════════════════
      // P2: TENUE_CONFIRMÉE + validationActive=ACTIF → SET_VERT (stable)
      // ══════════════════════════════════════════════════════════════════
      greenMidi = _validationLatchMidi;
      _lastGreenMidi = _validationLatchMidi;
      if (!_previousGreenState && kDebugMode) {
        debugPrint(
          'S59_P2_VERT_STABLE midi=$_validationLatchMidi '
          'tenueState=$tenueState validationActive=$_validationActive nowMs=$nowMs',
        );
      }
      _previousGreenState = true;
    } else if (tenueState == TenueState.tenueConfirmee && !_validationActive) {
      // ══════════════════════════════════════════════════════════════════
      // P3: TENUE_CONFIRMÉE + validationActive=INACTIF → SET_ORIGINE
      // ══════════════════════════════════════════════════════════════════
      greenMidi = null;
      // Note: _lastGreenMidi reste pour tracking, mais greenMidi output est null
      _previousGreenState = false;
    } else {
      // ══════════════════════════════════════════════════════════════════
      // P4: INCONNUE → NOOP (maintenir état précédent, anti-flicker)
      // ══════════════════════════════════════════════════════════════════
      if (_previousGreenState && _validationActive) {
        greenMidi = _validationLatchMidi;
        if (kDebugMode) {
          debugPrint(
            'S59_P4_NOOP_MAINTAIN_GREEN midi=$_validationLatchMidi '
            'tenueState=$tenueState nowMs=$nowMs → maintien état précédent',
          );
        }
      } else {
        greenMidi = null;
      }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 4. SESSION-059 ROUGE: LOI DU SYSTÈME — Multi-rouge lié à tenue
    // ══════════════════════════════════════════════════════════════════════
    //
    // ARBITRAGE SOURCE_A vs SOURCE_B:
    // - Source_A (expectedMidis param) = notes attendues selon timeline/partition
    // - Source_B (cyanMidis) = notes attendues selon UI
    // - Source_A fait foi si non vide, sinon fallback Source_B
    //
    // TABLE DE DÉCISION (par note jouée):
    // P1: midi ∈ greenMidis → BLOQUER (pas de rouge sur touche verte)
    // P2: tenueState == RELÂCHÉE → CLEAR (note relâchée)
    // P3: tenueState == INCONNUE → NOOP (maintenir état précédent)
    // P4: expectedActif ET midi ∈ expectedMidis → CLEAR (note correcte)
    // P5: expectedActif ET midi ∉ expectedMidis ET TENUE → SET_ROUGE
    // P6: NOT expectedActif ET TENUE → SET_ROUGE (rouge générique)
    // ══════════════════════════════════════════════════════════════════════

    final Set<int> redMidis = {};

    // SESSION-065: Si blueMidi == null, préserver les rouges non-stale
    // (déjà filtrés par la logique de tolérance dans le bloc else ci-dessus)
    // Ceci permet au rouge de "persister" tant que la note est tenue
    if (blueMidi == null && _currentRedMidis.isNotEmpty) {
      redMidis.addAll(_currentRedMidis);
      if (kDebugMode) {
        debugPrint(
          'RED_PRESERVE_NO_PITCH preserved=$_currentRedMidis nowMs=$nowMs',
        );
      }
    }

    // Arbitrage Source_A vs Source_B
    // Source_A = expectedMidis (paramètre passé à update, vient de la timeline)
    // Source_B = cyanMidis (état UI)
    final sourceAValid = expectedMidis.isNotEmpty;
    final sourceBValid = cyanMidis.isNotEmpty;
    final expectedActif = sourceAValid || sourceBValid;
    final effectiveExpectedMidis = sourceAValid ? expectedMidis : cyanMidis;

    if (kDebugMode && blueMidi != null) {
      debugPrint(
        'RED_ARBITRAGE sourceAValid=$sourceAValid(impliesWindowActive) '
        'sourceBValid=$sourceBValid expectedActif=$expectedActif '
        'effectiveExpected=$effectiveExpectedMidis',
      );
    }

    // Évaluer rouge pour la note jouée (blueMidi)
    if (blueMidi != null) {
      final midi = blueMidi;

      // P1: Vert sur même touche → BLOQUER
      if (greenMidi != null && midi == greenMidi) {
        if (kDebugMode) {
          debugPrint('RED_BLOCKED_GREEN midi=$midi blockedBy=green');
        }
        // Ne pas ajouter au redMidis
      }
      // P2: RELÂCHÉE → déjà géré par le clear global quand detectedMidi=null
      // P3: INCONNUE → maintenir rouges SAUF ceux relâchés (lastActive trop vieux)
      else if (tenueState == TenueState.inconnue) {
        // Préserver les rouges existants
        final preservedBefore = Set<int>.from(_currentRedMidis);
        redMidis.addAll(_currentRedMidis);

        // Null-safe: garantir que chaque rouge a un timestamp
        for (final m in _currentRedMidis) {
          _redMidiLastActiveMs.putIfAbsent(m, () => nowMs);
        }

        // Rafraîchir timestamp si blueMidi est rouge (encore actif)
        if (_currentRedMidis.contains(midi)) {
          _redMidiLastActiveMs[midi] = nowMs;
        }

        // Retirer les rouges non actifs depuis > toleranceMicroCoupuresMs
        final staleRemoved = <int>{};
        redMidis.removeWhere((m) {
          // Null-safe: si clé absente, considérer comme "juste actif" (nowMs)
          final lastActive = _redMidiLastActiveMs[m] ?? nowMs;
          final elapsed = nowMs - lastActive;
          if (elapsed > toleranceMicroCoupuresMs) {
            staleRemoved.add(m);
            return true;
          }
          return false;
        });

        if (_currentRedMidis.isNotEmpty && kDebugMode) {
          debugPrint(
            'RED_INCONNUE_MAINTAIN preserved_before=$preservedBefore '
            'staleRemoved=$staleRemoved final=$redMidis lastActive=$_redMidiLastActiveMs',
          );
        }
      }
      // P4: Note correcte (match strict)
      else if (expectedActif && effectiveExpectedMidis.contains(midi)) {
        if (kDebugMode) {
          debugPrint('RED_DECISION midi=$midi isMatch=true → CLEAR');
        }
        // Ne pas ajouter au redMidis, nettoyer timestamp
        _redMidiLastActiveMs.remove(midi);
      }
      // P5: Mauvaise note tenue + expected actif
      else if (expectedActif &&
          !effectiveExpectedMidis.contains(midi) &&
          tenueState == TenueState.tenueConfirmee) {
        // SESSION-066: PRESERVE recent reds when pitch jumps octaves
        // Problem: YIN jumps 72→73→62, old reds were lost
        // Solution: Keep reds within tolerance window (same logic as judgeFlashRouge)
        for (final entry in _redMidiLastActiveMs.entries) {
          final elapsed = nowMs - entry.value;
          if (elapsed <= toleranceMicroCoupuresMs) {
            redMidis.add(entry.key);
          }
        }
        redMidis.add(midi);
        _redMidiLastActiveMs[midi] = nowMs; // Tracker activité

        // SESSION-066: Limit to max 3 reds to avoid visual clutter
        if (redMidis.length > 3) {
          // Keep only the most recent 3
          final sorted = redMidis.toList()
            ..sort((a, b) =>
                (_redMidiLastActiveMs[b] ?? 0) - (_redMidiLastActiveMs[a] ?? 0));
          redMidis.clear();
          redMidis.addAll(sorted.take(3));
        }

        if (kDebugMode) {
          debugPrint(
            'RED_SET_ROUGES midi=$midi reason=mismatch '
            'expected=$effectiveExpectedMidis redSet=$redMidis',
          );
        }
      }
      // P6: Rouge générique (aucun expected actif) + tenue
      else if (!expectedActif && tenueState == TenueState.tenueConfirmee) {
        // SESSION-066: PRESERVE recent reds (same logic as P5)
        for (final entry in _redMidiLastActiveMs.entries) {
          final elapsed = nowMs - entry.value;
          if (elapsed <= toleranceMicroCoupuresMs) {
            redMidis.add(entry.key);
          }
        }
        redMidis.add(midi);
        _redMidiLastActiveMs[midi] = nowMs; // Tracker activité

        // SESSION-066: Limit to max 3 reds
        if (redMidis.length > 3) {
          final sorted = redMidis.toList()
            ..sort((a, b) =>
                (_redMidiLastActiveMs[b] ?? 0) - (_redMidiLastActiveMs[a] ?? 0));
          redMidis.clear();
          redMidis.addAll(sorted.take(3));
        }

        if (kDebugMode) {
          debugPrint('RED_GENERIC midi=$midi reason=no_expected_active redSet=$redMidis');
        }
      }
    }

    // Log si changement de redMidis
    if (!_setEquals(_currentRedMidis, redMidis) && kDebugMode) {
      if (redMidis.isEmpty && _currentRedMidis.isNotEmpty) {
        debugPrint(
          'RED_CLEAR previous=$_currentRedMidis reason=released_or_match',
        );
      }
    }

    // Mettre à jour l'état interne
    _currentRedMidis = redMidis;

    // ══════════════════════════════════════════════════════════════════════
    // 5. Construire nouvel état
    // ══════════════════════════════════════════════════════════════════════
    final newState = UIFeedbackState(
      blueMidi: blueMidi,
      cyanMidis: cyanMidis,
      greenMidi: greenMidi,
      redMidis: redMidis,
      timestampMs: nowMs,
      confidence: confidence,
    );

    // Notifier si changement
    if (_hasStateChanged(newState)) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  /// SESSION-059: Notifier un HIT_VALIDÉ pour LATCHÉ validationActive
  ///
  /// LOI SESSION-059:
  /// - validationActive := ACTIF à la réception de eventHitValidé
  /// - validationLatchMidi := hitMidi
  /// - Reset uniquement à RELÂCHÉE_CONFIRMÉE (dans update())
  /// - INTERDIT: ne dépend JAMAIS du pitch instantané
  ///
  /// [hitMidi] - Note MIDI du hit validé (note attendue qui a été jouée)
  /// [nowMs] - Timestamp courant en millisecondes
  void notifyHit({required int hitMidi, required int nowMs}) {
    // SESSION-059: Vérifier si on est en RELÂCHÉE_CONFIRMÉE → ignorer (P1 prioritaire)
    if (_tenueState == TenueState.relacheeConfirmee) {
      if (kDebugMode) {
        debugPrint(
          'S59_HIT_IGNORED_RELACHEE hitMidi=$hitMidi tenueState=$_tenueState nowMs=$nowMs',
        );
      }
      return;
    }

    // Éviter les doublons rapides sur même note
    if (_validationLatchMidi == hitMidi &&
        (nowMs - _lastGreenTimestampMs) < greenHitDebounceMs) {
      return;
    }

    // SESSION-059: LATCHÉ validationActive
    _validationActive = true;
    _validationLatchMidi = hitMidi;
    _lastGreenMidi = hitMidi;
    _lastGreenTimestampMs = nowMs;
    _greenCount++;

    if (kDebugMode) {
      debugPrint(
        'S59_LATCH_ACTIF hitMidi=$hitMidi greenCount=$_greenCount '
        'tenueState=$_tenueState nowMs=$nowMs',
      );
    }

    // Mettre à jour l'état immédiatement si en TENUE_CONFIRMÉE
    if (_tenueState == TenueState.tenueConfirmee) {
      final newState = _state.copyWith(greenMidi: hitMidi, timestampMs: nowMs);
      if (_hasStateChanged(newState)) {
        _state = newState;
        _previousGreenState = true;
        onStateChanged?.call(_state);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOI V3: API JUGE DE FRAPPE - Exécution directe des verdicts
  // ══════════════════════════════════════════════════════════════════════════

  /// Exécute un flash VERT ordonné par le JUGE (verdict CORRECT)
  /// Le JUGE a déjà décidé - cette méthode exécute sans logique supplémentaire
  /// SESSION-066: Clear _currentRedMidis pour éviter réapparition du rouge
  void judgeFlashVert({required int midi, required int nowMs}) {
    _lastGreenMidi = midi;
    _lastGreenTimestampMs = nowMs;
    _greenCount++;

    // Mettre à jour l'état avec le flash vert
    final newState = _state.copyWith(
      greenMidi: midi,
      timestampMs: nowMs,
      clearRed: true, // Vert efface tous les rouges
    );
    _state = newState;

    // SESSION-066: CRUCIAL - aussi clear les trackers internes
    // Sans ça, update(null) pourrait restaurer les rouges depuis _currentRedMidis
    _currentRedMidis = {};
    _redMidiLastActiveMs.clear();

    onStateChanged?.call(_state);

    if (kDebugMode) {
      debugPrint('JUDGE_FLASH_VERT midi=$midi nowMs=$nowMs clearedReds=true');
    }
  }

  /// Exécute un flash ROUGE ordonné par le JUGE (verdict INCORRECT)
  /// Le JUGE a déjà décidé - cette méthode exécute sans logique supplémentaire
  /// SESSION-065: Met à jour _redMidiLastActiveMs pour le système de tolérance
  /// SESSION-066: MERGE au lieu de REMPLACER - garder les rouges récents (octave jumps)
  /// SESSION-075: CLAMP all rouges to keyboard range (fixes octave detection errors)
  /// SESSION-076: CLAMP to expected octave FIRST (fixes YIN harmonics: 88→76)
  void judgeFlashRouge({
    required int midi,
    required int nowMs,
    Set<int> expectedMidis = const {},
  }) {
    // SESSION-076: FIRST try to snap to expected octave (fixes harmonics)
    // This handles YIN detecting E6 (88) when E5 (76) was played and expected
    int clampedMidi = _clampToExpectedOctave(midi, expectedMidis);

    // SESSION-075: THEN clamp to keyboard range as fallback
    clampedMidi = _clampMidiToKeyboard(clampedMidi);

    if (kDebugMode && clampedMidi != midi) {
      debugPrint(
        'ROUGE_CLAMP original=$midi → final=$clampedMidi '
        'expected=$expectedMidis keyboard=[$_keyboardFirstKey..$_keyboardLastKey]',
      );
    }

    // SESSION-066: MERGE avec rouges récents au lieu de REMPLACER
    // SESSION-076: Also clamp old reds to expected octave
    final recentReds = <int>{};
    for (final entry in _redMidiLastActiveMs.entries) {
      final elapsed = nowMs - entry.value;
      if (elapsed <= toleranceMicroCoupuresMs) {
        // SESSION-076: Clamp old reds to expected octave too
        int clampedOld = _clampToExpectedOctave(entry.key, expectedMidis);
        clampedOld = _clampMidiToKeyboard(clampedOld);
        recentReds.add(clampedOld);
      }
    }
    // Ajouter le nouveau rouge (déjà clampé)
    recentReds.add(clampedMidi);

    // SESSION-066: Limiter à max 3 rouges pour éviter pollution visuelle
    final newRedMidis = recentReds.length > 3
        ? {clampedMidi} // Fallback: si trop de rouges, garder seulement le nouveau
        : recentReds;

    final newState = _state.copyWith(
      redMidis: newRedMidis,
      timestampMs: nowMs,
    );
    _state = newState;
    _currentRedMidis = Set.from(newRedMidis);

    // SESSION-065: CRUCIAL - tracker le timestamp pour la tolérance
    // SESSION-076: Track with CLAMPED midi
    _redMidiLastActiveMs[clampedMidi] = nowMs;
    // Clean up old unclamped entry if different
    if (clampedMidi != midi) {
      _redMidiLastActiveMs.remove(midi);
    }

    onStateChanged?.call(_state);

    if (kDebugMode) {
      debugPrint('JUDGE_FLASH_ROUGE midi=$clampedMidi nowMs=$nowMs redSet=$newRedMidis recentMerged=${recentReds.length}');
    }
  }

  /// Met à jour uniquement les cyan (notes attendues) sans toucher vert/rouge
  /// Utilisé après judgeFlashVert/judgeFlashRouge pour maintenir l'affichage cyan
  void judgeUpdateCyan({
    required Set<int> expectedMidis,
    required int nowMs,
  }) {
    final newState = _state.copyWith(
      cyanMidis: expectedMidis,
      timestampMs: nowMs,
    );
    if (_state.cyanMidis != newState.cyanMidis) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  /// Clear tous les flashs (appelé par le JUGE pour NO_FLASH ou reset)
  void judgeClearFlash({required int nowMs}) {
    final newState = _state.copyWith(
      clearGreen: true,
      clearRed: true,
      clearBlue: true,
      timestampMs: nowMs,
    );
    _state = newState;
    _currentRedMidis = {};
    _lastGreenMidi = null;
    _lastBlueMidi = null;
    onStateChanged?.call(_state);

    if (kDebugMode) {
      debugPrint('JUDGE_CLEAR_FLASH nowMs=$nowMs');
    }
  }

  /// Reset complet de l'état
  void reset() {
    _state = UIFeedbackState.empty;
    _lastBlueMidi = null;
    _lastBlueTimestampMs = 0;
    _lastGreenMidi = null;
    _lastGreenTimestampMs = 0;
    _currentRedMidis = {};
    _redMidiLastActiveMs.clear();
    _greenCount = 0;

    // SESSION-059: Reset TenueEvaluator
    _lastValidPitchTimestampMs = 0;
    _tenueStartTimestampMs = 0;
    _tenueState = TenueState.inconnue;
    _tenueMidi = null;

    // SESSION-059: Reset ValidationLatch
    _validationActive = false;
    _validationLatchMidi = null;
    _previousGreenState = false;

    onStateChanged?.call(_state);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RENDER-ONLY API: Pré-calcul des couleurs pour le clavier
  // ══════════════════════════════════════════════════════════════════════════

  /// Calcule l'état visuel de chaque touche du clavier
  ///
  /// [firstKey] - Première note MIDI du clavier (ex: 36 = C2)
  /// [lastKey] - Dernière note MIDI du clavier (ex: 96 = C7)
  /// [blackKeys] - Liste des pitch classes noirs (ex: [1, 3, 6, 8, 10])
  ///
  /// Retourne Map avec priorité: VERT > ROUGE > BLEU > CYAN > neutre
  Map<int, KeyVisualState> computeKeyColors({
    required int firstKey,
    required int lastKey,
    required List<int> blackKeys,
  }) {
    final result = <int, KeyVisualState>{};

    for (int midi = firstKey; midi <= lastKey; midi++) {
      final isBlack = blackKeys.contains(midi % 12);

      // Priorité P1: VERT (HIT_VALIDÉ)
      if (_state.greenMidi != null && midi == _state.greenMidi) {
        result[midi] = KeyVisualState.green;
        continue;
      }

      // Priorité P2: ROUGE (erreur - notes fautives tenues)
      // SESSION-059 ROUGE: Multi-rouge supporté
      if (_state.redMidis.contains(midi)) {
        result[midi] = KeyVisualState.red;
        continue;
      }

      // Priorité P3: BLEU (rawMidi détecté sans match et sans rouge)
      if (_state.blueMidi != null &&
          midi == _state.blueMidi &&
          _state.greenMidi == null &&
          _state.redMidis.isEmpty) {
        result[midi] = KeyVisualState.blue;
        continue;
      }

      // Priorité P4: CYAN (attendu par partition)
      if (_state.cyanMidis.contains(midi)) {
        result[midi] = KeyVisualState.cyan;
        continue;
      }

      // P5: Neutre
      result[midi] = isBlack
          ? KeyVisualState.neutralBlack
          : KeyVisualState.neutralWhite;
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS PRIVÉS
  // ══════════════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-059: TenueEvaluator - État de tenue confirmé (robuste micro-coupures)
  // ══════════════════════════════════════════════════════════════════════════

  /// Évalue l'état de tenue confirmé selon la LOI SESSION-059
  ///
  /// RÈGLES:
  /// - TENUE_CONFIRMÉE = pitch détecté OU absence < TOLÉRANCE_MICRO_COUPURES
  /// - RELÂCHÉE_CONFIRMÉE = absence de pitch > TOLÉRANCE_MICRO_COUPURES
  /// - INCONNUE = impossible de trancher (première frame, etc.)
  ///
  /// INTERDIT: évaluer frame-par-frame sur pitch instantané
  TenueState _evaluateTenueState({
    required int? detectedMidi,
    required double confidence,
    required int nowMs,
  }) {
    final hasPitch = detectedMidi != null && confidence >= minConfidenceForBlue;

    if (hasPitch) {
      // Pitch détecté → mettre à jour le timestamp de dernier pitch valide
      _lastValidPitchTimestampMs = nowMs;

      // Si on n'était pas en tenue, vérifier critère d'entrée
      if (_tenueState != TenueState.tenueConfirmee) {
        if (_tenueStartTimestampMs == 0) {
          // Premier pitch détecté → démarrer le compteur d'entrée
          _tenueStartTimestampMs = nowMs;
          _tenueMidi = detectedMidi;
        }

        // Vérifier si on a atteint le critère d'entrée en tenue
        final tenueMs = nowMs - _tenueStartTimestampMs;
        if (tenueMs >= critereEntreeTenueMs) {
          // Critère atteint → TENUE_CONFIRMÉE
          _tenueState = TenueState.tenueConfirmee;
          _tenueMidi = detectedMidi;
          if (kDebugMode) {
            debugPrint(
              'S59_TENUE_ENTREE midi=$detectedMidi tenueMs=$tenueMs nowMs=$nowMs',
            );
          }
        } else {
          // Pas encore assez de temps → INCONNUE (anti-flicker)
          return TenueState.inconnue;
        }
      } else {
        // Déjà en tenue → rester en TENUE_CONFIRMÉE
        // Mise à jour du MIDI si changement (pour notes rapides)
        if (detectedMidi != _tenueMidi) {
          _tenueMidi = detectedMidi;
        }
      }

      return TenueState.tenueConfirmee;
    } else {
      // Pas de pitch détecté → vérifier tolérance micro-coupures
      if (_tenueState == TenueState.tenueConfirmee) {
        // On était en tenue → vérifier si absence > TOLÉRANCE
        final absenceMs = nowMs - _lastValidPitchTimestampMs;

        if (absenceMs > toleranceMicroCoupuresMs) {
          // Absence > TOLÉRANCE → RELÂCHÉE_CONFIRMÉE
          if (kDebugMode) {
            debugPrint(
              'S59_RELACHEE_CONFIRMEE midi=$_tenueMidi absenceMs=$absenceMs '
              'tolerance=$toleranceMicroCoupuresMs nowMs=$nowMs',
            );
          }
          _tenueState = TenueState.relacheeConfirmee;
          _tenueStartTimestampMs = 0;
          // Note: on garde _tenueMidi pour le log, sera reset au prochain cycle
          return TenueState.relacheeConfirmee;
        } else {
          // Absence < TOLÉRANCE → maintenir TENUE_CONFIRMÉE (anti-flicker)
          // C'est une micro-coupure tolérée
          return TenueState.tenueConfirmee;
        }
      } else if (_tenueState == TenueState.relacheeConfirmee) {
        // Déjà relâché et toujours pas de pitch → rester relâché
        // Reset le compteur d'entrée pour la prochaine tenue
        _tenueStartTimestampMs = 0;
        return TenueState.relacheeConfirmee;
      } else {
        // État INCONNUE et pas de pitch → rester INCONNUE
        return TenueState.inconnue;
      }
    }
  }

  // SESSION-059 ROUGE: _hasNearbyNote() SUPPRIMÉE
  // La LOI impose un MATCH STRICT: midi ∈ expectedMidis uniquement
  // Pas de "note proche" / "pitch class match" / "octave flexible"

  /// Vérifie si l'état a changé de manière significative
  bool _hasStateChanged(UIFeedbackState newState) {
    return _state.blueMidi != newState.blueMidi ||
        _state.greenMidi != newState.greenMidi ||
        !_setEquals(_state.redMidis, newState.redMidis) ||
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
