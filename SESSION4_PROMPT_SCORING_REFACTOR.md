# SESSION 4 — SCORING SYSTEM + REFACTOR PRACTICE_PAGE

**TU ES CODEX DANS LE REPO SHAZAPIANO (Flutter/Dart). TU AS ACCÈS À TOUS LES FICHIERS.**

---

## 🎯 OBJECTIF PRINCIPAL

Implémenter un nouveau système de scoring **Pitch/Timing/Sustain/Wrong notes** + **Refactor massif** de `practice_page.dart` en extrayant la logique métier dans des modules dédiés, avec tests et logs debug stables.

---

## ⚠️ MÉTHODOLOGIE OBLIGATOIRE (BASÉE SESSION 3)

### 📋 FLUX DE TRAVAIL

**OBLIGATOIRE pour CHAQUE tâche :**

1. **PLAN** (≤6 lignes)
   - Lister les étapes claires et numérotées
   - Identifier les fichiers à modifier/créer
   - Estimer les risques de régression

2. **CHANGEMENTS** (code/diff)
   - Implémenter par petites étapes validables
   - 1 changement logique à la fois
   - Commenter les zones critiques

3. **VÉRIFICATION** (commandes)
   - `flutter analyze --no-fatal-infos` après CHAQUE changement
   - Grep pour valider l'impact (ex: `grep -n "_score"` pour voir tous les usages)
   - Read file pour vérifier le contexte

4. **ANALYSE CASCADE CRITIQUE**
   - Pour CHAQUE modification, identifier 5-7 zones d'impact potentiel
   - Lire le code des zones impactées
   - Valider mathématiquement/logiquement (pas d'assumptions)
   - Documenter les validations dans un fichier `ANALYSE_CASCADE_SESSION4.md`

5. **TEST MANUEL** (≤5 étapes)
   - Fournir checklist précise de ce qu'on va tester
   - Inclure edge cases (timing exact 40ms, 100ms, 200ms, etc.)

### 🚫 INTERDICTIONS STRICTES

- **AUCUN nouveau package** sans accord explicite (pubspec.yaml/requirements.txt)
- **AUCUN refactor global en une fois** : procéder par étapes de ≤6 fichiers
- **AUCUN renommage/déplacement massif** sans `git mv`
- **AUCUNE assumption** : si un comportement n'est pas clair, LIRE LE CODE source
- **AUCUN placeholder** dans le code (pas de `// TODO implement`, finir chaque fonction)

### ✅ RÈGLES DE VALIDATION

1. **Double-check avec grep** avant chaque modification
   - Exemple : avant de changer `_score` de int à double, faire `grep -n "_score"` pour voir TOUS les usages
   
2. **Lire le contexte** (±20 lignes) autour de chaque modification
   - Ne jamais modifier une ligne sans comprendre son contexte

3. **Validation mathématique** des formules
   - Si une formule change, prouver qu'elle est correcte (pas d'approximation)
   - Tester les edge cases : valeurs exactes des seuils (40ms, 100ms, 200ms)

4. **SessionId et état async**
   - Respecter STRICTEMENT les mécanismes anti-replay existants
   - Ne JAMAIS compter un événement d'une session précédente

5. **Performance**
   - Pas de matching O(N²) par frame
   - Utiliser indexation par pitch + time window

---

## 🎯 NOUVEAU SYSTÈME DE SCORING (SPEC COMPLÈTE)

### A) GRADES DE TIMING (onset)

Sur note avec **pitch correct** uniquement :

```dart
enum HitGrade { perfect, good, ok, miss, wrong }

HitGrade gradeFromDt(int absDtMs) {
  if (absDtMs <= 40) return HitGrade.perfect;
  else if (absDtMs <= 100) return HitGrade.good;
  else if (absDtMs <= 200) return HitGrade.ok;
  else return HitGrade.miss;
}
```

**CRITICAL:** Tester les valeurs exactes : 39ms, 40ms, 41ms / 99ms, 100ms, 101ms / 199ms, 200ms, 201ms.

### B) PITCH (RÉUTILISER L'EXISTANT)

**TU NE DOIS PAS INVENTER** un nouveau critère pitch. 

**OBLIGATOIRE :**
1. Grep cherche : `pitchClass`, `midiNote`, `compareNotes`, `matchPitch`
2. Identifier la fonction EXISTANTE qui décide "pitch correct"
3. Créer un `PitchComparator` typedef qui wrappe cette fonction
4. Utiliser ce comparator dans le nouveau matcher

**Comportement probable actuel :**
- Soit : midi exact (60 == 60)
- Soit : pitchClass + octave ignorée (C4 == C5)
- Soit : transposition/normalisation

**NE PAS CASSER** ce comportement. Si le système actuel fait pitchClass, garder pitchClass.

### C) FENÊTRE DE MATCHING

```dart
const int MATCH_WINDOW_MS = 200; // ±200ms autour de t_expected
```

**Matching algorithm :**
1. Pour chaque note attendue avec `t_expected`
2. Chercher dans buffer des notes jouées : `t_played` dans `[t_expected - 200, t_expected + 200]`
3. Filtrer par pitch (selon comparator existant)
4. Sélectionner candidat avec **min |t_played - t_expected|**
5. Marquer le playedId comme "consommé" (exclusivité : 1 played ≠ match qu'1 expected)

**Optimisation OBLIGATOIRE :**
- Indexer buffer par `pitchKey` (Map<int, List<PlayedEvent>>)
- Ne scanner que les events avec le bon pitch
- Éviter O(N²) : pour 100 notes × 50 events buffer = 5000 comparaisons → NON

### D) SUSTAIN (OPTIONNEL, SAFE)

Si `duration_expected` et `duration_played` disponibles :

```dart
double sustainFactor(double durPlayed, double durExpected) {
  if (durExpected == null || durExpected <= 0) return 1.0;
  
  final durErr = (durPlayed - durExpected).abs();
  final threshold = max(0.15, durExpected); // 150ms ou durée attendue
  final factor = 1.0 - (durErr / threshold);
  
  return factor.clamp(0.7, 1.0); // Pénalité max 30%
}
```

**IMPORTANT :** Si duration non disponible (micro mode probablement), `sustainFactor = 1.0` (aucune pénalité).

### E) WRONG NOTES

**Définition :** Note jouée (note-on event) qui ne peut matcher AUCUNE note attendue.

**Critères WRONG :**
1. Note jouée avec pitch qui n'existe dans aucune note attendue "proche" (temporellement)
2. OU note jouée hors fenêtre de toutes les notes attendues (trop tôt / trop tard)
3. OU note jouée alors que toutes les notes matchables sont déjà consommées

**CRITICAL - Anti-faux-positifs :**
- Respecter `sessionId` : ne PAS marquer WRONG des events d'une ancienne session
- Ne PAS marquer WRONG trop tôt (attendre que la fenêtre soit vraiment passée)
- Si le système actuel a un "buffer grace period", le respecter

**Pénalité WRONG :**
- Points: 0
- Combo: reset à 0
- Option pénalité -10 points : DÉSACTIVÉE par défaut (flag dans ScoringConfig)

### F) POINTS + COMBO

```dart
// Points de base
const POINTS_PERFECT = 100;
const POINTS_GOOD = 70;
const POINTS_OK = 40;
const POINTS_MISS = 0;
const POINTS_WRONG = 0;

// Combo
int combo = 0; // Hit (perfect/good/ok) => combo++, sinon => combo = 0

// Multiplicateur
double computeMultiplier(int combo) {
  final mult = 1.0 + (combo ~/ 10) * 0.1;
  return min(mult, 2.0); // Cap à 2.0x
}

// Points ajoutés
int computeFinalPoints(HitGrade grade, int combo, double sustainFactor) {
  final basePoints = switch (grade) {
    HitGrade.perfect => 100,
    HitGrade.good => 70,
    HitGrade.ok => 40,
    _ => 0,
  };
  
  final withSustain = basePoints * sustainFactor;
  final mult = computeMultiplier(combo);
  
  return (withSustain * mult).round();
}
```

**Test combo cap :**
- Combo 9 → mult 1.0x
- Combo 10 → mult 1.1x
- Combo 19 → mult 1.1x
- Combo 20 → mult 1.2x
- Combo 100 → mult 2.0x (cap)
- Combo 200 → mult 2.0x (cap)

### G) MÉTRIQUES (FIN DE PARTIE / HUD)

```dart
class PracticeScoringState {
  int totalScore = 0;
  
  int combo = 0;
  int maxCombo = 0;
  
  int perfectCount = 0;
  int goodCount = 0;
  int okCount = 0;
  int missCount = 0;
  int wrongCount = 0;
  
  // Accuracy pitch = notes matchées / notes attendues totales
  double get accuracyPitch {
    final matched = perfectCount + goodCount + okCount;
    final total = matched + missCount;
    return total > 0 ? matched / total : 0.0;
  }
  
  // Timing moyen sur notes matchées
  double timingAvgAbsMs = 0.0; // Calculé en accumulant |dt| et divisant par matched
  
  // Optionnel
  double timingP95AbsMs = 0.0; // Percentile 95 des |dt|
  double sustainAvgFactor = 1.0; // Moyenne des sustainFactors
}
```

**HUD en temps réel :**
- Score actuel
- Combo actuel + max
- Dernier grade (Perfect/Good/OK/Miss/Wrong) avec animation

**Dialog fin de partie :**
- Score total
- Accuracy pitch (%)
- Timing moyen (ms)
- Distribution grades (Perfect: X, Good: Y, OK: Z, Miss: W, Wrong: Q)
- Max combo

---

## 🧱 REFACTOR OBLIGATOIRE (ARCHITECTURE)

### 📁 NOUVELLE STRUCTURE

**Créer ces fichiers :**

```
app/lib/core/practice/
├── model/
│   └── practice_models.dart          # Tous les modèles de données
├── scoring/
│   └── practice_scoring_engine.dart  # Logique scoring pure (testable)
├── matching/
│   └── note_matcher.dart             # Algorithme matching optimisé
└── debug/
    └── practice_debug_logger.dart    # Logs stables, export JSON

app/lib/presentation/pages/practice/controller/
└── practice_controller.dart          # Orchestration (Riverpod StateNotifier?)
```

### 📦 MODÈLES (practice_models.dart)

```dart
// Note attendue
class ExpectedNote {
  final int index;
  final int midi; // ou pitchClass selon système existant
  final double tExpectedMs;
  final double? durationMs;
  
  const ExpectedNote({
    required this.index,
    required this.midi,
    required this.tExpectedMs,
    this.durationMs,
  });
}

// Event note jouée
class PlayedNoteEvent {
  final String id; // UUID pour unicité
  final int midi; // ou pitchClass
  final double tPlayedMs;
  final double? durationMs;
  final NoteSource source; // mic ou midi
  
  PlayedNoteEvent({
    required this.id,
    required this.midi,
    required this.tPlayedMs,
    this.durationMs,
    required this.source,
  });
}

enum NoteSource { microphone, midi }

// Candidat de match
class MatchCandidate {
  final int expectedIndex;
  final String playedId;
  final double dtMs;
  
  const MatchCandidate({
    required this.expectedIndex,
    required this.playedId,
    required this.dtMs,
  });
}

// Résolution d'une note attendue
class NoteResolution {
  final int expectedIndex;
  final HitGrade grade;
  final double? dtMs;
  final int pointsAdded;
  final String? matchedPlayedId;
  final double sustainFactor;
  
  const NoteResolution({
    required this.expectedIndex,
    required this.grade,
    this.dtMs,
    required this.pointsAdded,
    this.matchedPlayedId,
    this.sustainFactor = 1.0,
  });
}

enum HitGrade { perfect, good, ok, miss, wrong }
```

### ⚙️ SCORING ENGINE (practice_scoring_engine.dart)

**Contrainte : AUCUNE dépendance Flutter. Pure Dart. 100% testable.**

```dart
class ScoringConfig {
  final int perfectThresholdMs;
  final int goodThresholdMs;
  final int okThresholdMs;
  final bool enableWrongPenalty;
  final int wrongPenaltyPoints;
  final double sustainMinFactor;
  
  const ScoringConfig({
    this.perfectThresholdMs = 40,
    this.goodThresholdMs = 100,
    this.okThresholdMs = 200,
    this.enableWrongPenalty = false,
    this.wrongPenaltyPoints = -10,
    this.sustainMinFactor = 0.7,
  });
}

class PracticeScoringEngine {
  final ScoringConfig config;
  
  PracticeScoringEngine({required this.config});
  
  HitGrade gradeFromDt(int absDtMs) {
    // Implémentation basée sur config thresholds
  }
  
  int basePoints(HitGrade grade) {
    // 100/70/40/0/0
  }
  
  double computeSustainFactor(double? durPlayed, double? durExpected) {
    // Logique sustain ou 1.0
  }
  
  double computeMultiplier(int combo) {
    // 1.0 + floor(combo/10)*0.1, cap 2.0
  }
  
  int computeFinalPoints(HitGrade grade, int combo, double sustainFactor) {
    // basePoints * sustainFactor * mult, arrondi
  }
  
  // Méthode pour appliquer une résolution à l'état
  void applyResolution(PracticeScoringState state, NoteResolution resolution) {
    // Mettre à jour score, combo, compteurs, etc.
  }
}
```

### 🎯 NOTE MATCHER (note_matcher.dart)

**Objectif : matching rapide et exclusif.**

```dart
typedef PitchComparator = bool Function(int pitch1, int pitch2);

class NoteMatcher {
  final int windowMs;
  final PitchComparator pitchEquals;
  
  NoteMatcher({
    required this.windowMs,
    required this.pitchEquals,
  });
  
  // Trouve le meilleur candidat pour une note attendue
  MatchCandidate? findBestMatch(
    ExpectedNote expected,
    List<PlayedNoteEvent> buffer,
    Set<String> alreadyUsedPlayedIds,
  ) {
    // 1. Filtrer buffer : t_played dans [t_expected - window, t_expected + window]
    // 2. Filtrer pitch : pitchEquals(played.midi, expected.midi)
    // 3. Exclure alreadyUsedPlayedIds
    // 4. Sélectionner min |dt|
    // 5. Retourner MatchCandidate ou null
  }
  
  // Optimisation: indexer buffer par pitch
  Map<int, List<PlayedNoteEvent>> indexBufferByPitch(List<PlayedNoteEvent> buffer) {
    // Grouper events par midi/pitchClass
  }
}
```

### 🎮 CONTROLLER (practice_controller.dart)

**Rôle : orchestration entre UI, matcher, scoring engine.**

```dart
class PracticeController extends StateNotifier<PracticeViewState> {
  final PracticeScoringEngine _scoringEngine;
  final NoteMatcher _matcher;
  final PracticeDebugLogger _logger;
  
  String? _currentSessionId;
  List<ExpectedNote> _expectedNotes = [];
  List<PlayedNoteEvent> _playedBuffer = [];
  Set<String> _consumedPlayedIds = {};
  
  int _noteIndex = 0;
  PracticeScoringState _scoringState = PracticeScoringState();
  
  PracticeController({
    required PracticeScoringEngine scoringEngine,
    required NoteMatcher matcher,
    required PracticeDebugLogger logger,
  }) : _scoringEngine = scoringEngine,
       _matcher = matcher,
       _logger = logger,
       super(PracticeViewState.initial());
  
  void startPractice(String sessionId, List<ExpectedNote> notes) {
    // Initialiser session
  }
  
  void onPlayedNote(PlayedNoteEvent event) {
    // Vérifier sessionId
    // Ajouter à buffer
    // Tenter matching avec notes en attente
    // Si WRONG, logger et appliquer
  }
  
  void onTimeUpdate(double currentTimeMs) {
    // Checker les notes dépassées (miss)
    // Avancer noteIndex si nécessaire
  }
  
  void stopPractice() {
    // Finaliser metrics
    // Nettoyer état
  }
  
  PracticeScoringState getScoringState() => _scoringState;
}
```

### 🖥️ PRACTICE_PAGE.DART (ALLÉGÉE)

**Objectif : passer de 4765 lignes à ~800-1000 lignes (UI only).**

**Garder :**
- Layout / UI rendering
- Gestures / buttons
- Provider/controller listening
- Navigation

**DÉPLACER hors page :**
- Toute logique scoring → `PracticeScoringEngine`
- Toute logique matching → `NoteMatcher`
- Orchestration → `PracticeController`
- Logs debug → `PracticeDebugLogger`

**Exemple structure finale :**

```dart
class PracticePage extends ConsumerStatefulWidget {
  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  @override
  Widget build(BuildContext context) {
    final viewState = ref.watch(practiceControllerProvider);
    
    return Scaffold(
      body: Column(
        children: [
          _buildHUD(viewState.scoringState),
          _buildNoteArea(viewState.notesToRender),
          _buildControlButtons(),
        ],
      ),
    );
  }
  
  void _onPlayPressed() {
    ref.read(practiceControllerProvider.notifier).startPractice(...);
  }
  
  // Aucune logique métier ici, juste UI
}
```

---

## 🔎 ÉTAPES D'IMPLÉMENTATION (OBLIGATOIRES)

### ÉTAPE 0 — REPÉRAGE (30 min)

**Objectif : comprendre le système existant sans rien casser.**

1. **Grep recherches obligatoires :**
   ```
   grep -rn "HIT_DECISION" app/lib/
   grep -rn "REJECT" app/lib/
   grep -rn "pitchClass" app/lib/
   grep -rn "midiNote" app/lib/
   grep -rn "sessionId" app/lib/
   grep -rn "noteIdx" app/lib/
   grep -rn "effectiveLeadIn" app/lib/
   grep -rn "_correctNotes" app/lib/
   ```

2. **Lire fichiers clés :**
   - `practice_page.dart` : trouver où les notes sont matchées (ligne 2500-2600 probablement)
   - `mic_engine.dart` : comment les events pitch sont produits
   - Si MIDI : trouver le handler MIDI note-on

3. **Identifier le critère pitch actuel :**
   - Fonction qui compare deux notes (midi exact ? pitchClass ?)
   - Créer un wrapper `PitchComparator` qui réutilise cette logique EXACTEMENT

4. **Documenter les findings :**
   - Créer `REPERAGE_SESSION4.md` avec :
     - Où se fait le matching actuel
     - Quelle fonction compare pitch
     - Comment les notes attendues sont stockées
     - Comment les notes jouées arrivent
     - Mécanisme sessionId existant

### ÉTAPE 1 — MODÈLES (1h)

1. Créer `app/lib/core/practice/model/practice_models.dart`
2. Implémenter tous les modèles listés ci-dessus
3. `flutter analyze` → doit passer
4. **Cascade analysis :** aucun impact (nouveaux fichiers)

### ÉTAPE 2 — SCORING ENGINE (2h)

1. Créer `app/lib/core/practice/scoring/practice_scoring_engine.dart`
2. Implémenter toutes les méthodes (pure Dart, testable)
3. `flutter analyze` → doit passer
4. **Tests unitaires obligatoires :**
   ```dart
   // app/test/core/practice/scoring/practice_scoring_engine_test.dart
   
   test('gradeFromDt - edge cases', () {
     expect(engine.gradeFromDt(39), HitGrade.perfect);
     expect(engine.gradeFromDt(40), HitGrade.perfect);
     expect(engine.gradeFromDt(41), HitGrade.good);
     expect(engine.gradeFromDt(99), HitGrade.good);
     expect(engine.gradeFromDt(100), HitGrade.good);
     expect(engine.gradeFromDt(101), HitGrade.ok);
     expect(engine.gradeFromDt(199), HitGrade.ok);
     expect(engine.gradeFromDt(200), HitGrade.ok);
     expect(engine.gradeFromDt(201), HitGrade.miss);
   });
   
   test('combo multiplier cap', () {
     expect(engine.computeMultiplier(0), 1.0);
     expect(engine.computeMultiplier(9), 1.0);
     expect(engine.computeMultiplier(10), 1.1);
     expect(engine.computeMultiplier(19), 1.1);
     expect(engine.computeMultiplier(20), 1.2);
     expect(engine.computeMultiplier(100), 2.0);
     expect(engine.computeMultiplier(200), 2.0); // cap
   });
   
   test('sustainFactor clamp', () {
     expect(engine.computeSustainFactor(1.0, 1.0), 1.0);
     expect(engine.computeSustainFactor(0.5, 1.0), greaterThanOrEqualTo(0.7));
     expect(engine.computeSustainFactor(2.0, 1.0), greaterThanOrEqualTo(0.7));
   });
   ```

5. **Cascade analysis :** aucun impact (module isolé)

### ÉTAPE 3 — NOTE MATCHER (2h)

1. Créer `app/lib/core/practice/matching/note_matcher.dart`
2. Implémenter `findBestMatch` avec optimisation pitch indexing
3. Créer le `PitchComparator` typedef qui wrappe la fonction existante
4. `flutter analyze` → doit passer
5. **Tests unitaires obligatoires :**
   ```dart
   // app/test/core/practice/matching/note_matcher_test.dart
   
   test('findBestMatch - closest dt wins', () {
     final expected = ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000);
     final buffer = [
       PlayedNoteEvent(id: 'a', midi: 60, tPlayedMs: 950), // dt = 50ms
       PlayedNoteEvent(id: 'b', midi: 60, tPlayedMs: 980), // dt = 20ms ← BEST
       PlayedNoteEvent(id: 'c', midi: 60, tPlayedMs: 1100), // dt = 100ms
     ];
     
     final match = matcher.findBestMatch(expected, buffer, {});
     expect(match?.playedId, 'b');
     expect(match?.dtMs, 20);
   });
   
   test('findBestMatch - exclusivity', () {
     final expected = ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000);
     final buffer = [
       PlayedNoteEvent(id: 'a', midi: 60, tPlayedMs: 1000),
     ];
     
     final match1 = matcher.findBestMatch(expected, buffer, {});
     expect(match1?.playedId, 'a');
     
     // Déjà consommé
     final match2 = matcher.findBestMatch(expected, buffer, {'a'});
     expect(match2, isNull);
   });
   ```

6. **Cascade analysis :** aucun impact (module isolé)

### ÉTAPE 4 — DEBUG LOGGER (1h)

1. Créer `app/lib/core/practice/debug/practice_debug_logger.dart`
2. Méthodes :
   - `logResolveExpected(sessionId, expectedIdx, grade, dtMs, pointsAdded, combo, totalScore)`
   - `logWrongPlayed(sessionId, playedId, pitchKey, tPlayed, reason)`
   - Option export JSON des logs
3. Flag `enableDebugLogs` dans config
4. `flutter analyze` → doit passer
5. **Cascade analysis :** aucun impact (logs seulement)

### ÉTAPE 5 — CONTROLLER (4h)

**CRITICAL : Cette étape modifie le flow existant.**

1. Créer `app/lib/presentation/pages/practice/controller/practice_controller.dart`
2. Implémenter orchestration :
   - `startPractice(sessionId, notes)`
   - `onPlayedNote(event)` : matching + scoring
   - `onTimeUpdate(currentTime)` : checker miss
   - `stopPractice()` : finaliser metrics
3. Intégrer avec provider Riverpod
4. **NE PAS encore brancher dans practice_page.dart** (juste créer le controller)
5. `flutter analyze` → doit passer
6. **Cascade analysis :**
   - Aucun impact immédiat (controller non utilisé)

### ÉTAPE 6 — BRANCHEMENT CONTROLLER (6h)

**CRITICAL : Modification du code existant dans practice_page.dart**

**Sous-étapes obligatoires (ne PAS faire tout d'un coup) :**

1. **BACKUP :** Copier `practice_page.dart` → `practice_page_backup_session3.dart`

2. **Étape 6a : Instancier controller (30 min)**
   - Ajouter provider en haut de practice_page
   - `flutter analyze` + test build → doit passer
   - **Cascade analysis :** Aucun comportement changé, juste init

3. **Étape 6b : Déléguer startPractice (1h)**
   - Trouver où `_startPractice()` est appelé
   - Appeler `controller.startPractice(sessionId, notes)` en plus
   - **NE PAS ENCORE supprimer l'ancien code**
   - `flutter analyze` + test app → valider que ça marche toujours
   - **Cascade analysis :** Double init temporaire OK, aucun side-effect

4. **Étape 6c : Déléguer onPlayedNote Mic (2h)**
   - Trouver où les mic events sont traités (probablement dans `_handleMicEngineDecision`)
   - Appeler `controller.onPlayedNote(event)` en parallèle
   - Logger les résultats des deux systèmes (ancien vs nouveau)
   - Valider que les deux donnent le même résultat
   - **Cascade analysis :** Aucune régression, logs confirment équivalence

5. **Étape 6d : Déléguer onPlayedNote MIDI (1h)**
   - Idem pour MIDI note-on handler
   - Logger + valider équivalence
   - **Cascade analysis :** MIDI + Mic en parallèle OK

6. **Étape 6e : Switcher HUD vers nouveau state (1h)**
   - Remplacer affichage score/combo par `controller.scoringState`
   - Valider visuellement que les valeurs sont correctes
   - **Cascade analysis :** Affichage uniquement, aucun impact logique

7. **Étape 6f : Supprimer ancien code scoring (30 min)**
   - Maintenant que le nouveau marche, supprimer les anciennes variables `_score`, `_correctNotes`, etc.
   - Supprimer les fonctions scoring de practice_page.dart
   - `flutter analyze` → doit passer
   - **Cascade analysis :**
     - Grep `_score` → doit disparaître de practice_page
     - Grep `_correctNotes` → doit disparaître
     - Valider aucune référence orpheline

### ÉTAPE 7 — EXTRACTION LOGIQUE MÉTIER (4h)

**Objectif : Vider practice_page.dart de toute logique non-UI.**

1. **Identifier les fonctions à déplacer :**
   - Grep dans practice_page.dart : chercher toutes les fonctions privées (lignes commençant par `void _`)
   - Classifier : UI (garder) vs Logique métier (déplacer)

2. **Déplacer par petits batches :**
   - Batch 1 : Fonctions matching/buffer (vers controller)
   - Batch 2 : Fonctions calcul/timers (vers controller)
   - Batch 3 : Fonctions note processing (vers controller)

3. **Après chaque batch :**
   - `flutter analyze` → doit passer
   - Test app → valider aucune régression
   - **Cascade analysis :** Documenter les déplacements

4. **Objectif final :**
   - practice_page.dart < 1000 lignes
   - Aucune logique scoring/matching dans build() ou widgets

### ÉTAPE 8 — TESTS FINAUX (2h)

1. **Tests unitaires :**
   - `flutter test` → tous les tests doivent passer
   - Ajouter tests pour controller si nécessaire

2. **Tests manuels (checklist) :**
   - [ ] Play practice mic → grades affichés (Perfect/Good/OK/Miss)
   - [ ] Combo fonctionne (s'incrémente, reset sur miss)
   - [ ] Score augmente avec multiplicateur
   - [ ] Wrong note détectée + combo reset
   - [ ] MIDI mode fonctionne (si supporté)
   - [ ] Fin de partie : dialog avec metrics correctes
   - [ ] Pas de double count (1 played = 1 expected max)
   - [ ] SessionId respecté (pas d'events ancienne session)

3. **Tests edge cases :**
   - [ ] Note à exactement 40ms → Perfect
   - [ ] Note à exactement 100ms → Good
   - [ ] Note à exactement 200ms → OK
   - [ ] Note à 201ms → Miss
   - [ ] Combo 100 → mult 2.0x (cap)
   - [ ] Sustain très court/long → factor dans [0.7, 1.0]

4. **Vérification performance :**
   - Jouer chanson avec 200+ notes
   - Pas de lag visible
   - CPU/memory normaux

---

## ✅ CRITÈRES D'ACCEPTATION FINALE

### CODE

- ✅ `flutter analyze --no-fatal-infos` → 0 erreurs
- ✅ `flutter test` → tous les tests passent
- ✅ practice_page.dart < 1000 lignes (idéalement ~800)
- ✅ Aucune logique métier dans build() / widgets UI

### FONCTIONNEL

- ✅ Grades affichés correctement (Perfect/Good/OK/Miss/Wrong)
- ✅ Score/combo cohérents avec formules
- ✅ Sustain appliqué si durées disponibles
- ✅ Wrong notes détectées sans faux positifs
- ✅ Pas de double count
- ✅ SessionId respecté
- ✅ Illumination des notes fonctionne toujours
- ✅ Rendering/audio OK
- ✅ Micro ET MIDI fonctionnent

### PERFORMANCE

- ✅ Pas de lag sur chanson 200+ notes
- ✅ CPU/memory normaux
- ✅ Matching optimisé (indexation pitch)

### DOCUMENTATION

- ✅ `REPERAGE_SESSION4.md` créé (findings étape 0)
- ✅ `ANALYSE_CASCADE_SESSION4.md` créé (toutes les validations)
- ✅ Commentaires dans code pour zones critiques

---

## 📦 LIVRABLE ATTENDU

À la fin de la session, fournir :

1. **Résumé exécutif** (≤20 lignes) :
   - Quels fichiers créés
   - Quels fichiers modifiés (+ nb lignes avant/après)
   - Où le nouveau scoring est branché
   - Comment activer les logs debug
   - Réduction practice_page.dart : X lignes → Y lignes

2. **Documentation cascade** :
   - `ANALYSE_CASCADE_SESSION4.md` complet
   - Toutes les zones d'impact validées
   - Tous les grep/reads effectués

3. **Checklist tests** :
   - Tests unitaires : X/X passés
   - Tests manuels : checklist complétée
   - Edge cases : validés

4. **Patch final** :
   - Tous les fichiers créés/modifiés prêts
   - Code prêt à rebuild

---

## 🚀 GO

Tu peux commencer par **ÉTAPE 0 - REPÉRAGE**. Ne code RIEN avant d'avoir compris le système existant.

**Rappel méthodologie :**
1. Grep/search
2. Read fichiers
3. Documenter findings
4. Poser questions si comportement ambigu
5. Ensuite seulement → coder

BONNE CHANCE ! 🎯
