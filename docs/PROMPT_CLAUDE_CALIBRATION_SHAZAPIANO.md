# MISSION : Implémenter la persistance, l'apprentissage progressif et l'auto-détection de la calibration micro dans ShazaPiano

## Contexte

Tu travailles sur **ShazaPiano** (github.com/sky1241/shazam-piano), une app Flutter de détection de notes de piano en temps réel via micro.

Le pipeline de détection est déjà implémenté et fonctionne :
```
Micro → OnsetDetector (EMA) → YIN + Goertzel (hybrid via PracticePitchRouter) → NoteTracker → DecisionArbiter → Score
```

Un **framework de calibration** existe aussi :
- `CalibrationService` (app/lib/core/practice/pitch/calibration_service.dart) : routine 9 notes (C3,E3,G3,C4,E4,G4,C5,E5,G5), mesure latence, fréquence détectée, RMS, confiance, recommande MPM vs YIN
- `CalibratedMicEngineConfig` (app/lib/core/practice/pitch/calibrated_mic_engine.dart) : traduit CalibrationResult en paramètres MicEngine (tail window, RMS threshold, clarity threshold, algo)
- `MicTuning` (app/lib/core/practice/pitch/mic_tuning.dart) : ~40 paramètres tunables + 3 ReverbProfile presets (low/medium/high)
- `PracticeCalibration` (app/lib/core/practice/device_calibration.dart) : 3 profils device statiques (lowEnd/midRange/highEnd)
- `OnsetDetector` (app/lib/core/practice/pitch/onset_detector.dart) : noise floor automatique via EMA baseline

**PROBLÈME : 3 briques manquent pour que le système soit réellement intelligent :**

1. ❌ **Persistance** — Le CalibrationResult est in-memory only. Rien n'est sauvegardé. À chaque lancement, tout est perdu.
2. ❌ **Apprentissage progressif** — Aucun historique, aucune amélioration au fil des sessions. Les profils sont des constantes compile-time.
3. ❌ **Auto-détection room/device** — Les 3 profils réverb et 3 profils device existent mais la sélection est manuelle. Le code dit : "Using lowEnd as baseline until auto-detection is implemented".

## Ce que tu dois implémenter

### BRIQUE 1 : Persistance de la calibration

**Objectif :** Sauvegarder les résultats de calibration sur le device pour qu'ils survivent entre les sessions.

**Approche recommandée :** SharedPreferences ou Hive (Hive est déjà potentiellement dans le projet, vérifie pubspec.yaml).

**Ce qu'il faut sauvegarder :**
```dart
// Données à persister :
{
  "calibration_date": DateTime,           // Quand la dernière calibration a été faite
  "avg_latency_ms": double,              // Latence moyenne mesurée
  "latency_std_ms": double,              // Écart-type latence
  "freq_offset_cents": double,           // Offset fréquentiel moyen (en cents)
  "rms_threshold": double,               // Seuil RMS calibré
  "ambient_noise_rms": double,           // Niveau de bruit ambiant mesuré
  "success_rate": double,                // Taux de succès de la calibration (0-1)
  "recommended_algorithm": String,        // "mpm" ou "yin"
  "per_note_results": List<NoteCalibrationResult>,  // Résultat par note
  "device_model": String,                // Modèle du téléphone
  "reverb_profile": String,              // low/medium/high (détecté ou manuel)
  "device_tier": String,                 // lowEnd/midRange/highEnd
  "session_count": int,                  // Nombre de sessions jouées avec cette calibration
  "cumulative_adjustments": Map,          // Ajustements accumulés (pour brique 2)
}
```

**Fichier à créer :** `app/lib/core/practice/persistence/calibration_storage.dart`

**Connexions requises :**
- Au lancement de PracticePage : charger la calibration sauvegardée si elle existe
- Si pas de calibration → proposer la routine 9 notes (CalibrationService)
- Si calibration existe → l'appliquer directement via CalibratedMicEngineConfig
- Après chaque calibration réussie → sauvegarder automatiquement
- Dans SettingsPage : bouton "Recalibrer le micro"

### BRIQUE 2 : Apprentissage progressif (le plus important)

**Objectif :** À chaque session de practice, le système collecte des stats sur la qualité de la détection et ajuste ses paramètres progressivement.

**Logique :**

```
Session N : L'utilisateur joue → on mesure les écarts
    ↓
Calcul des ajustements :
    - Si beaucoup de MISS sur notes faibles → baisser rms_threshold de 5%
    - Si beaucoup de faux positifs (WRONG sans que l'utilisateur joue) → monter rms_threshold de 5%
    - Si les HIT arrivent systématiquement en retard → augmenter latency_compensation de 10ms
    - Si les HIT arrivent systématiquement en avance → réduire latency_compensation de 10ms
    - Si erreurs d'octave fréquentes → ajuster le pitchOffsetCents du Goertzel
    ↓
Sauvegarde des ajustements cumulés → appliqués à la session N+1
```

**Fichier à créer :** `app/lib/core/practice/learning/session_analyzer.dart`

**Ce que le SessionAnalyzer doit faire :**
1. Pendant la session : collecter les événements (HIT, MISS, WRONG, wrongFreeplay) avec timestamps et MIDI notes
2. En fin de session : analyser les patterns :
   - `miss_rate_by_register` : taux de MISS par registre (grave/medium/aigu)
   - `false_positive_rate` : taux de WRONG quand l'utilisateur ne jouait probablement pas
   - `timing_bias_ms` : biais temporel moyen des HIT (positif = retard, négatif = avance)
   - `octave_error_rate` : taux d'erreurs d'octave
   - `avg_confidence_on_hit` : confiance moyenne sur les bonnes détections
3. Calculer des **micro-ajustements** (petits deltas, pas de changements brutaux) :
   - Chaque ajustement est borné (max ±10% par session pour RMS, max ±20ms pour latence)
   - Les ajustements sont **cumulatifs** mais avec un plafond global (max ±50% de la valeur calibrée initiale)
4. Sauvegarder via CalibrationStorage (brique 1)

**Connexions requises :**
- Le DecisionArbiter ou le PracticeController doit alimenter le SessionAnalyzer avec chaque événement
- En fin de session (quand l'utilisateur quitte PracticePage) : appeler `sessionAnalyzer.analyzeAndSave()`
- Au prochain lancement : les ajustements sont appliqués en plus de la calibration de base

**Fichier à créer aussi :** `app/lib/core/practice/learning/adaptive_parameters.dart`
```dart
class AdaptiveParameters {
  final double rmsAdjustment;        // multiplicateur (ex: 0.95 = -5%)
  final double latencyAdjustment;    // en ms (ex: +15ms)
  final double confidenceAdjustment; // delta (ex: -0.05)
  final int sessionsCount;           // nombre de sessions analysées
  final DateTime lastUpdated;

  /// Applique les ajustements sur un CalibratedMicEngineConfig
  CalibratedMicEngineConfig apply(CalibratedMicEngineConfig base);

  /// Fusionne avec les résultats d'une nouvelle session
  AdaptiveParameters merge(SessionAnalysisResult newSession);
}
```

### BRIQUE 3 : Auto-détection room + device

**Objectif :** Détecter automatiquement le type de pièce (réverbération) et le tier du device sans intervention utilisateur.

**3A — Détection du device tier :**

**Fichier à créer :** `app/lib/core/practice/detection/device_detector.dart`

Utilise `device_info_plus` (probablement déjà dans pubspec.yaml) pour récupérer le modèle du device, puis classifie :
```dart
DeviceTier detectDeviceTier() {
  // Heuristiques :
  // - Si year >= 2023 ET (brand == Samsung S/Note/Z || Pixel 7+ || iPhone 13+) → highEnd
  // - Si year >= 2021 ET (brand connu) → midRange
  // - Sinon → lowEnd
  // Fallback sur RAM si dispo : >6GB = highEnd, 4-6GB = midRange, <4GB = lowEnd
}
```

**Connexion :** Appelé une seule fois au premier lancement, résultat sauvegardé dans CalibrationStorage.

**3B — Détection automatique de la réverbération :**

**Fichier à créer :** `app/lib/core/practice/detection/room_detector.dart`

**Logique :** Pendant les 2 premières secondes de la calibration (ou au début de chaque session) :
1. L'utilisateur joue une note franche
2. On mesure le **decay time** du signal RMS après l'attaque :
   - Decay rapide (< 200ms pour -20dB) → `ReverbProfile.low` (pièce sèche, moquette)
   - Decay moyen (200-500ms) → `ReverbProfile.medium` (pièce normale)
   - Decay lent (> 500ms) → `ReverbProfile.high` (grande pièce, carrelage, réverb)
3. On mesure aussi le **noise floor** pendant 1 seconde de silence

```dart
class RoomDetector {
  /// Analyse un buffer audio post-attaque pour estimer la réverbération
  ReverbProfile detectReverb(List<double> postAttackRms, double sampleRate);

  /// Mesure le bruit ambiant sur 1 seconde de silence
  double measureAmbientNoise(List<double> silenceRms);
}
```

**Connexion :**
- Intégrer au début de CalibrationService : avant les 9 notes, demander 1 seconde de silence + 1 note franche pour détecter la pièce
- Le ReverbProfile détecté est appliqué dans MicTuning et sauvegardé
- Optionnel : re-détecter à chaque session (la pièce peut changer) → comparer avec le profil sauvegardé, si différent → appliquer le nouveau

## Architecture finale

```
app/lib/core/practice/
├── persistence/
│   └── calibration_storage.dart        ← NOUVEAU (brique 1)
├── learning/
│   ├── session_analyzer.dart           ← NOUVEAU (brique 2)
│   └── adaptive_parameters.dart        ← NOUVEAU (brique 2)
├── detection/
│   ├── device_detector.dart            ← NOUVEAU (brique 3A)
│   └── room_detector.dart              ← NOUVEAU (brique 3B)
├── device_calibration.dart             ← MODIFIER (utiliser device_detector au lieu de constantes)
├── pitch/
│   ├── calibration_service.dart        ← MODIFIER (intégrer room_detector au début)
│   ├── calibrated_mic_engine.dart      ← MODIFIER (appliquer adaptive_parameters)
│   ├── mic_tuning.dart                 ← MODIFIER (appliquer ReverbProfile auto-détecté)
│   └── ... (ne pas toucher au reste du pipeline pitch)
```

## Flow complet après implémentation

```
PREMIER LANCEMENT :
  1. device_detector → détecte tier (sauvegarde)
  2. CalibrationService démarre :
     a. 1 sec silence → room_detector mesure ambient noise
     b. 1 note franche → room_detector détecte réverb profile
     c. 9 notes → calibration complète (latence, freq offset, RMS)
  3. CalibrationResult → calibration_storage.save()
  4. CalibratedMicEngineConfig créé → Practice prêt

LANCEMENTS SUIVANTS :
  1. calibration_storage.load() → calibration existante
  2. adaptive_parameters.load() → ajustements accumulés
  3. CalibratedMicEngineConfig + AdaptiveParameters.apply() → Practice prêt
  (optionnel : quick room check de 2 sec au début)

FIN DE CHAQUE SESSION :
  1. SessionAnalyzer reçoit tous les events (HIT/MISS/WRONG)
  2. Analyse patterns → calcule micro-ajustements
  3. AdaptiveParameters.merge(newSession) → sauvegarde
  4. Prochaine session = calibration + ajustements cumulés de toutes les sessions passées
```

## Règles importantes

1. **Ne touche PAS au pipeline de détection** (YIN, Goertzel, PracticePitchRouter, OnsetDetector, NoteTracker, DecisionArbiter). Il fonctionne, il a 80+ sessions de debug. On n'y touche pas.

2. **Les ajustements doivent être conservatifs.** Max ±10% par session, max ±50% cumulé. Si un paramètre diverge trop, reset à la valeur calibrée.

3. **Toujours fallback gracieux.** Si CalibrationStorage est vide/corrompu → utiliser PracticeCalibration.lowEnd (le profil safe actuel). L'app ne doit JAMAIS crasher à cause de la calibration.

4. **Pas de dépendance lourde.** SharedPreferences ou Hive, pas de SQLite ou de solution cloud. Tout reste local.

5. **Tester sur le flow existant.** Après implémentation, vérifier que PracticePage démarre toujours correctement, que les résultats de practice ne sont pas dégradés, et que l'app ne ralentit pas.

## Fichiers à lire en priorité avant de coder

1. `app/lib/core/practice/pitch/calibration_service.dart` — comprendre CalibrationResult
2. `app/lib/core/practice/pitch/calibrated_mic_engine.dart` — comprendre comment les résultats sont traduits en config
3. `app/lib/core/practice/device_calibration.dart` — comprendre les profils actuels
4. `app/lib/core/practice/pitch/mic_tuning.dart` — comprendre MicTuning et ReverbProfile
5. `app/lib/presentation/pages/practice/mic_engine.dart` — comprendre MicEngine et ses paramètres
6. `app/lib/presentation/pages/practice/practice_page.dart` — comprendre le lifecycle de la page
7. `app/lib/core/practice/pitch/practice_pitch_router.dart` — comprendre le pipeline (NE PAS MODIFIER)
8. `app/lib/core/practice/pitch/decision_arbiter.dart` — comprendre les events HIT/MISS/WRONG (NE PAS MODIFIER, juste lire pour savoir quoi collecter)

## Pubspec check

Avant de coder, vérifie `app/pubspec.yaml` pour :
- `shared_preferences` ou `hive` / `hive_flutter` — si absent, ajoute `shared_preferences`
- `device_info_plus` — si absent, ajoute-le
- Ne pas ajouter de dépendances inutiles
