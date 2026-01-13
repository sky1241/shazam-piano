# 🎯 PROMPT CHATGPT — ANALYSE VIDÉO PRACTICE SHAZAPIANO

**DATE**: 12 janvier 2026  
**SESSION**: Session 4 — Nouveau système scoring granulaire (HIT/MISS/WRONG)  
**OBJECTIF**: Détecter et diagnostiquer bugs practice mode avec analyse vidéo + logs + code source

---

## 📋 CONTEXTE PROJET SHAZAPIANO

### Qu'est-ce que ShazaPiano?
Application **Piano Hero** avec détection pitch microphone temps réel.

**Stack Technique**:
- **Frontend**: Flutter + Riverpod (state management)
- **Backend**: Python Flask (inference audio, séparation stems, arrangement MIDI)
- **Session actuelle**: Session 4 — Système scoring granulaire HIT/MISS/WRONG

### Architecture Practice Mode — 4 Composants Critiques

#### 1️⃣ MicEngine (`app/lib/presentation/pages/practice/mic_engine.dart`)
**Rôle**: Détection pitch microphone temps réel

**Flow**:
```
Micro → Stream audio → FFT Analysis → Détection fréquence → Note MIDI + confidence + RMS
```

**Callback critique**:
```dart
onPitchDetected(int midiNote, double confidence, double rms)
```

**Filtrage qualité**:
- **RMS** (amplitude): Seuil minimum pour éviter bruit ambiant
- **Confidence** (0.0-1.0): Fiabilité détection pitch (0.12 = seuil actuel)

---

#### 2️⃣ NoteMatcher (`app/lib/core/practice/matching/note_matcher.dart`)
**Rôle**: Matcher notes attendues (partition) vs notes jouées (micro)

**Logique matching actuelle**:
- ✅ **Distance ≤3 demi-tons** SANS octave shifts: `60 (C4) → 63 (D#4)` ✅ OK
- ❌ **Distance >3 ou octave shifts**: `60 (C4) → 72 (C5)` ❌ NOK
- ⏱️ **Timing window**: Note attendue doit être **started** (active) pour être matchable

**Méthode clé**:
```dart
ExpectedNote? micPitchMatch(int playedMidi, List<ExpectedNote> expectedNotes)
```

**Tests validation** (`note_matcher_test.dart` L73-90):
- Octave shifts désactivés (bug critique si `pitch_match_octave_shift=1` dans logs)

---

#### 3️⃣ PracticeScoringEngine (`app/lib/core/practice/scoring/practice_scoring_engine.dart`)
**Rôle**: Calcul score/combo avec système granulaire

**Décisions Session 4**:
| Décision | Description | Score | Combo |
|----------|-------------|-------|-------|
| **HIT** | Note attendue correcte jouée à temps | +10 | +1 |
| **MISS** | Note attendue pas jouée (timeout window) | 0 | RESET |
| **WRONG** | Note non-attendue jouée | -5 | RESET |
| **RELEASE** | Note relâchée correctement (sustain) | +1 | Inchangé |

**Méthode clé**:
```dart
void recordDecision(
  PracticeDecision decision,
  ExpectedNote expectedNote,
  PlayedNoteEvent? playedNote,
  double timestamp
)
```

---

#### 4️⃣ PracticeController (`app/lib/presentation/pages/practice/controller/practice_controller.dart`)
**Rôle**: Orchestration loop practice (cerveau du système)

**Flow complet**:
```
1. MicEngine détecte pitch → onPitchDetected(midi, conf, rms)
2. Controller filtre qualité (gating RMS/confidence)
3. Si pass gating → NoteMatcher.micPitchMatch(midi, expectedNotes)
4. Si match trouvé → ScoringEngine.recordDecision(HIT, ...)
5. Si pas match → (attente timeout → MISS)
6. Update UI (score, combo, feedback visuel vert/rouge)
```

**Ligne critique L2477**:
```dart
if (!_practiceRunning) return; // Guard race conditions
```

---

## 🐛 BUGS RÉCEMMENT CORRIGÉS (Commits ec8d304 + 4a35be9)

### ✅ Fixes P0 Appliqués

#### 1. Race condition `_practiceRunning` (L2477)
- **Symptôme**: Callbacks micro après dispose → crashes
- **Fix**: Guard early return ajouté

#### 2. Octave shifts désactivés uniformément
- **Symptôme**: `60 (C4)` matchait `72 (C5)` → faux positifs massifs
- **Fix**: `micPitchMatch()` accepte SEULEMENT distance ≤3 demi-tons direct
- **Validation**: Tests `note_matcher_test.dart` L73-90

#### 3. Mic state update timing (L2661-2665)
- **Symptôme**: `_micState` pas synchronisé avec callbacks
- **Fix**: Update `_micState` AVANT `setState()`

#### 4. Dead code cleanup
- Variables `bestTestMidi`, `noteTestResult` supprimées (jamais utilisées)

### ⚠️ Bugs P2 Mineurs Restants (Non bloquants)
- Commentaire `_minConfHit` à clarifier (L2518: "0.08 base, 0.12 strong")
- Pattern `_lastMicFrameAt` consistency (assigné après utilisation)

---

## 📊 LOGS DEBUG — GUIDE COMPLET TAGS

### Format Standard Logs
```dart
debugPrint('SESSION4_TAG: key=value key2=value2');
```

### 🔍 Tags Critiques à Analyser

#### `SESSION4_FINAL` — Statistiques fin session
**Format**:
```
SESSION4_FINAL: score=X combo_max=Y hit_count=Z miss_count=W wrong_count=V
```
**Validation**: Score cohérent = `(hit_count × 10) + (release_count × 1) - (wrong_count × 5)`

---

#### `SESSION4_HIT_DECISION` — Décision granulaire enregistrée
**Format**:
```
SESSION4_HIT_DECISION: decision=HIT/MISS/WRONG note_midi=X timestamp=Y
```
**Validation**: Chaque note attendue → exactement 1 décision (HIT ou MISS)

---

#### `SESSION4_GATING_HIT` / `SESSION4_GATING_MISS` — Filtrage qualité
**Format**:
```
SESSION4_GATING_HIT: Skip low-confidence hit midi=X rms=Y conf=Z
SESSION4_GATING_MISS: Skip low-confidence miss midi=X rms=Y conf=Z
```
**Attendu APRÈS fixes**: Moins de "Skip" si jeu correct (thresholds ajustés)

**⚠️ BUG POTENTIEL**: Si >50% pitchs skipped alors que vidéo montre jeu correct  
→ Thresholds trop stricts (vérifier L2518-2520 `practice_controller.dart`)

---

#### `SESSION4_MIC_PITCH` — Pitch détecté brut
**Format**:
```
SESSION4_MIC_PITCH: midi=X conf=Y rms=Z
```
**Validation**: Stream continu pendant jeu actif (pas interruptions longues)

---

#### `SESSION4_MATCH_RESULT` — Résultat matching
**Format**:
```
SESSION4_MATCH_RESULT: played_midi=X matched_midi=Y distance=Z pitch_match_octave_shift=0
```
**⚠️ VALIDATION CRITIQUE**: `pitch_match_octave_shift=0` **TOUJOURS**  
→ Si `=1` trouvé: BUG critique octave shifts réactivés par erreur

---

### 🛠️ Commandes Grep Analyse Rapide

```bash
# Score final
grep "SESSION4_FINAL" logcatdebug

# Timeline décisions
grep "HIT_DECISION" logcatdebug

# Pitchs rejetés par filtrage
grep "GATING" logcatdebug | grep "Skip"

# VÉRIFICATION CRITIQUE: Doit être vide (octave shifts désactivés)
grep "pitch_match_octave_shift=1" logcatdebug

# Nombre total décisions par type
grep -c "decision=HIT" logcatdebug
grep -c "decision=MISS" logcatdebug
grep -c "decision=WRONG" logcatdebug
```

---

## 🎯 MISSION ANALYSE VIDÉO

### 📦 Ressources Fournies
1. ✅ **Vidéo practice**: Enregistrement session jeu utilisateur
2. ✅ **Logcat** (`logcatdebug`): Logs Flutter complets session
3. ✅ **Code source**: ZIP dossier `shazam-piano/`

---

## 🔬 QUESTIONS ANALYSE DÉTAILLÉE (Réponds à TOUTES)

### 1️⃣ COMPORTEMENT OBSERVÉ vs ATTENDU

#### Dans la vidéo — Observations visuelles
- ❓ **Séquence notes jouées**: Quelles notes l'utilisateur joue-t-il au microphone?  
  *(Identifie approximativement: Do, Ré, Mi, Fa, Sol, La, Si ou MIDI 60-72)*
  
- ❓ **Partition affichée**: Quelles notes bleues sont attendues (haut écran)?

- ❓ **Feedback visuel**:
  - Notes **VERTES** (HIT validé)?
  - Notes **ROUGES** (MISS/WRONG)?
  - Notes **ORANGE** ou autre couleur?
  - **Comportement anormal**: Note verte devient rouge après? Touches rouges jamais jouées?

- ❓ **Score/Combo affichés**: Cohérents avec le jeu observé?

#### Dans les logs — Cohérence technique
- ❓ **Comptage décisions**:
  ```bash
  grep -c "decision=HIT" logcatdebug    # Nombre HIT
  grep -c "decision=MISS" logcatdebug   # Nombre MISS
  grep -c "decision=WRONG" logcatdebug  # Nombre WRONG
  ```
  → Correspondent-ils au nombre de notes attendues visibles dans vidéo?

- ❓ **Pitchs détectés non matchés**:  
  Si logs montrent `MIC_PITCH: midi=63` mais pas `MATCH_RESULT` correspondant  
  → Note détectée mais pas utilisée (possible bug matching)

- ❓ **Notes attendues non décidées**:  
  Si partition affiche 10 notes bleues mais logs montrent seulement 7 décisions (HIT+MISS)  
  → 3 notes "oubliées" (bug timing window)

- ❓ **Timestamps cohérents**:  
  Timestamp vidéo note jouée vs timestamp `HIT_DECISION` log  
  → Si décalage >500ms: latence processing loop excessive

---

### 2️⃣ ANOMALIES DÉTECTION PITCH

#### Filtrage trop strict? (GATING)
**Commande analyse**:
```bash
grep "GATING.*Skip" logcatdebug | wc -l  # Compte pitchs rejetés
grep "MIC_PITCH" logcatdebug | wc -l     # Compte pitchs détectés total
```

❓ **Question**: Si >50% pitchs skipped alors que vidéo montre jeu correct clair:
- Vérifier valeurs `rms` et `conf` dans logs  
- Comparer avec thresholds code:
  - `_minConfHit` (L2518 practice_controller.dart)
  - `_minConfWrong` (L2520)

#### Faux positifs/négatifs?
- ❓ **Faux négatif**: Note jouée clairement (vidéo) mais pas détectée?  
  → Chercher absence `MIC_PITCH` pendant jeu actif

- ❓ **Faux positif**: `MIC_PITCH` détecté mais vidéo montre silence?  
  → Bruit ambiant, RMS threshold trop bas

---

### 3️⃣ ANOMALIES MATCHING (CRITIQUE)

#### Octave shifts résiduels? ⚠️
**Commande vérification**:
```bash
grep "pitch_match_octave_shift=1" logcatdebug
```

❓ **DOIT ÊTRE VIDE**  
- Si trouvé: **BUG P0 CRITIQUE**  
- Code `note_matcher.dart` L73-90 pas respecté (octave shifts réactivés)

#### Distance matching incorrecte?
❓ **Scénarios bugs**:
1. Note jouée **proche** (distance ≤3) pas matchée?  
   Ex: Joue `midi=60 (C4)`, partition attend `midi=62 (D4)`, distance=2 → DEVRAIT matcher
   
2. Note jouée **loin** (distance >3) matchée par erreur?  
   Ex: Joue `midi=60 (C4)`, partition attend `midi=67 (G4)`, distance=7 → NE DEVRAIT PAS matcher

**Vérification logs**:
```bash
grep "MATCH_RESULT" logcatdebug  # Voir distances matchées
```

---

### 4️⃣ ANOMALIES SCORING

#### Score incohérent?
**Calcul manuel**:
```
expected_score = (hit_count × 10) + (release_count × 1) - (wrong_count × 5)
```

❓ **Comparer avec** `SESSION4_FINAL score=X`  
- Si différence >10 points: BUG dans `practice_scoring_engine.dart`

#### Combo pas reset après MISS/WRONG?
**Règle**: MISS ou WRONG devrait reset combo à 0

❓ **Vérification logs**:
```bash
grep -A2 "decision=MISS\|decision=WRONG" logcatdebug | grep "combo="
```
→ Le prochain `combo=` devrait être 0 ou 1 (pas >1)

---

### 5️⃣ ANOMALIES TIMING

#### Décisions en retard?
❓ **Comparer timestamps**:
- Timestamp vidéo (hh:mm:ss) note jouée
- Timestamp `HIT_DECISION` log correspondant
- **Si décalage >500ms**: Latence processing loop excessive

#### Décisions manquantes?
❓ **Comptage notes**:
1. Compter notes attendues visibles partition (vidéo)
2. Compter décisions logs:
   ```bash
   grep "HIT_DECISION\|MISS_DECISION\|WRONG_DECISION" logcatdebug | wc -l
   ```
3. **Si différence**: Certaines notes pas décidées → Bug timing window ou race condition

---

### 6️⃣ RACE CONDITIONS / STATE MANAGEMENT

#### Callbacks après dispose?
❓ **Vérification**:
- Chercher logs après timestamp "Practice disposed" ou "Session ended"
- Si `MIC_PITCH` ou `HIT_DECISION` présents après: Guard `_practiceRunning` L2477 pas suffisant

#### State mutations concurrentes?
❓ **Pattern suspect**:
```bash
grep "setState\|notifyListeners" logcatdebug
```
→ Si 2 `setState()` avec timestamp <50ms écart: Possible conflit Riverpod

---

## 🗂️ FICHIERS CRITIQUES (Si bugs détectés)

### 1. Détection pitch
**Fichier**: `app/lib/presentation/pages/practice/mic_engine.dart`  
**Focus**: L150-250 (callback `onPitchDetected`, thresholds RMS/confidence L180-190)

### 2. Matching logique
**Fichier**: `app/lib/core/practice/matching/note_matcher.dart`  
**Focus**: L73-120 (`micPitchMatch`, calcul distance, octave shifts L80-90)

### 3. Scoring calcul
**Fichier**: `app/lib/core/practice/scoring/practice_scoring_engine.dart`  
**Focus**: L50-150 (`recordDecision`, score increment/decrement, combo reset L80-100)

### 4. Orchestration loop
**Fichier**: `app/lib/presentation/pages/practice/controller/practice_controller.dart`  
**Focus**: L2450-2550 (`onPitchDetected`, flow detection → matching → scoring → UI)

---

## 📝 FORMAT RÉPONSE ATTENDU

### Structure Rapport Obligatoire

```markdown
# 🔍 ANALYSE VIDÉO PRACTICE — BUGS DÉTECTÉS

## 1️⃣ RÉSUMÉ EXÉCUTIF (≤3 lignes par bug)
- **BUG #1**: [Titre court descriptif]
  - **Symptôme**: [Description 1 phrase]
  - **Sévérité**: P0 (bloquant) / P1 (majeur) / P2 (mineur)
  - **Fichier**: [path/file.dart:line]

- **BUG #2**: [...]

## 2️⃣ ANALYSE DÉTAILLÉE PAR BUG

### 🐛 BUG #1: [Titre Complet]

#### Symptôme Vidéo
[Description précise ce qui se passe visuellement]  
Timestamp vidéo: [hh:mm:ss]

#### Symptôme Logs
**Commande grep**:
```bash
grep "[TAG]" logcatdebug
```

**Extrait pertinent**:
```
[Copier 3-5 lignes logs clés]
```

#### Code Suspect
**Fichier**: `path/file.dart` **Lignes**: X-Y

```dart
[Copier bloc code 5-10 lignes avec contexte]
```

#### Hypothèse Root Cause
[Explication technique précise pourquoi le bug se produit]

#### Impact Utilisateur
[Conséquences pratiques: score incorrect? notes manquées? crash?]

---

### 🐛 BUG #2: [...]
[Même structure]

---

## 3️⃣ MÉTRIQUES SESSION

| Métrique | Valeur Logs | Valeur Attendue | Écart |
|----------|-------------|-----------------|-------|
| Notes attendues | X | Y | ❌ Z |
| HIT count | A | B | ✅/❌ |
| MISS count | C | 0 (si perfect) | ❌ |
| WRONG count | D | 0 | ❌ |
| Score final | S | (A×10)-(D×5) | ✅/❌ |
| Combo max | M | N | ✅/❌ |
| Pitchs détectés | P | Q | ✅/❌ |
| Pitchs skipped (gating) | R | <20% | ✅/❌ |

---

## 4️⃣ ACTIONS CORRECTIVES RECOMMANDÉES

### BUG #1
**Action**: [Description précise modification]  
**Fichier**: `path/file.dart`  
**Ligne**: X  
**Changement**:
```dart
// Avant
[ancien code]

// Après
[nouveau code]
```
**Justification**: [Pourquoi ce fix corrige le root cause]

### BUG #2
[Même structure]

---

## 5️⃣ COMMANDES VÉRIFICATION POST-FIX

```bash
# Tests unitaires
flutter test app/test/core/practice/matching/note_matcher_test.dart
flutter test app/test/core/practice/scoring/practice_scoring_engine_test.dart

# Analyse statique
flutter analyze

# Logs validation (après nouveau test practice)
grep "SESSION4_FINAL" logcatdebug           # Score cohérent?
grep "pitch_match_octave_shift=1" logcatdebug  # Doit être vide
grep "GATING.*Skip" logcatdebug | wc -l    # Doit diminuer
```

---

## 6️⃣ QUESTIONS CLARIFICATION (Si applicable)

- ❓ **Question #1**: [Comportement attendu ambigu nécessitant précision user]?
- ❓ **Question #2**: [...]

---

## 7️⃣ TESTS ADDITIONNELS À GÉNÉRER (Bonus)

### Si bug matching détecté
**Fichier**: `app/test/core/practice/matching/note_matcher_test.dart`  
**Test à ajouter**:
```dart
test('description cas edge bug', () {
  // Setup cas reproduction bug
  // Assert comportement correct attendu
});
```

### Si bug scoring détecté
**Fichier**: `app/test/core/practice/scoring/practice_scoring_engine_test.dart`  
**Test à ajouter**: [...]

---

## 8️⃣ LOGS DEBUG ADDITIONNELS SUGGÉRÉS (Bonus)

Si manque visibilité certaines zones, ajouter ces tags:

**Fichier**: `practice_controller.dart`  
**Ligne**: [X]
```dart
debugPrint('SESSION4_NEW_TAG: key=$value key2=$value2');
```

**Justification**: [Pourquoi ce log aiderait debugging]

---

## 9️⃣ PERFORMANCE ANALYSIS (Bonus)

### Latence détectée?
**Analyse timestamps**:
```bash
grep "timestamp=" logcatdebug | [analyse écarts]
```

**Optimisations suggérées**:
- Debounce callback micro (actuellement: aucun)
- Throttle updates UI (actuellement: chaque frame)
- Async guards (vérifier L2477-2480)
```

---

## ⚠️ CONTRAINTES ANALYSE STRICTES

### ❌ NE PAS
- Proposer refactor global architecture (modifications ciblées uniquement)
- Suggérer nouveaux packages Flutter/Dart sans justification critique P0
- Modifier >6 fichiers par bug (regrouper fixes si possible)
- Deviner comportement attendu si ambigu → **poser question clarification**

### ✅ TOUJOURS
- Citer **numéros lignes précis** (±5 lignes contexte)
- Fournir **commandes grep reproductibles**
- Classer bugs **P0** (bloquant) / **P1** (majeur) / **P2** (mineur)
- Valider **cohérence inter-fichiers**: MicEngine ↔ NoteMatcher ↔ Controller ↔ ScoringEngine

---

## ✅ CHECKLIST AVANT RÉPONSE FINALE

- [ ] Vidéo visionnée entièrement (timestamps clés notés)
- [ ] Logs analysés avec commandes grep fournies ci-dessus
- [ ] Code source fichiers critiques examiné (MicEngine, NoteMatcher, ScoringEngine, Controller)
- [ ] Chaque bug documenté avec: **symptôme vidéo + logs + code suspect + hypothèse + impact**
- [ ] Actions correctives ≤6 fichiers par bug
- [ ] Commandes vérification post-fix fournies (`flutter test`, `grep` tags)
- [ ] Questions clarification listées si comportement ambigu
- [ ] Métriques session calculées et comparées attendu vs réel

---

## 🎯 OBJECTIF FINAL

Fournir **diagnostic précis complet** permettant au développeur de:
1. **Corriger tous bugs en 1 session** (workflow AGENTS.md)
2. **Valider fixes** avec commandes grep + tests unitaires
3. **Committer atomiquement** avec format:
   ```
   fix(practice): Bugs vidéo analysis P0 - [titre court]
   
   BUGS CORRIGÉS:
   - Bug #1: [description]
   - Bug #2: [description]
   
   DÉTAILS TECHNIQUES:
   - Fichier X ligne Y: [changement]
   
   ATTENDU LOGS:
   - Tag SESSION4_FINAL score devrait augmenter
   - Tag GATING Skip devrait diminuer
   ```

**Merci de ton analyse détaillée! 🚀**
