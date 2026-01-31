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

  /// Dernière note BLEU avec son timestamp (pour debounce)
  int? _lastBlueMidi;
  int _lastBlueTimestampMs = 0;

  /// Dernier VERT (HIT_VALIDÉ) avec timestamp (pour durée flash)
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
  static const int toleranceMicroCoupuresMs = 80;

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
      // SESSION-059 ROUGE: Clear rouge aussi (rouge lié à tenue, pas de pitch = relâche)
      final hadFeedback = _lastBlueMidi != null || _currentRedMidis.isNotEmpty;
      if (hadFeedback) {
        if (kDebugMode) {
          debugPrint(
            'UI_CLEAR_TRIGGER reason=${detectedMidi == null ? "no_pitch" : "low_conf"} '
            'prevBlue=$_lastBlueMidi prevRed=$_currentRedMidis prevGreen=$_lastGreenMidi nowMs=$nowMs',
          );
        }
      }
      blueMidi = null;
      _lastBlueMidi = null;
      // SESSION-059 ROUGE: Clear tous les rouges (rouge lié à tenue)
      // VERT survit au clear (flash de HIT_VALIDÉ indépendant du pitch courant)
      _currentRedMidis = {};
      _redMidiLastActiveMs.clear();
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
        redMidis.add(midi);
        _redMidiLastActiveMs[midi] = nowMs; // Tracker activité
        if (!_currentRedMidis.contains(midi) && kDebugMode) {
          debugPrint(
            'RED_SET_ROUGES midi=$midi reason=mismatch '
            'expected=$effectiveExpectedMidis played=$midi',
          );
        }
      }
      // P6: Rouge générique (aucun expected actif) + tenue
      else if (!expectedActif && tenueState == TenueState.tenueConfirmee) {
        redMidis.add(midi);
        _redMidiLastActiveMs[midi] = nowMs; // Tracker activité
        if (!_currentRedMidis.contains(midi) && kDebugMode) {
          debugPrint('RED_GENERIC midi=$midi reason=no_expected_active');
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
