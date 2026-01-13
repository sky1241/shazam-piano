# PROMPT AUDIT CRITIQUE - PRACTICE MODE SCORING

Tu es un expert en debugging de systèmes temps-réel audio/scoring. Ton objectif: **trouver TOUS les bugs restants** dans ce système de practice mode Flutter après 7 bugs critiques déjà corrigés.

---

## CONTEXTE ARCHITECTURAL CRITIQUE

### Dual System (OLD + NEW)
1. **OLD**: MicEngine (pitch detection → HIT/MISS decisions)
   - Window: `[note.start - 120ms ... note.end + 450ms]`
   - Calcule `dt` pour chaque HIT (maintenant: 3-way logic before/during/after)
   - Buffer `_events` conservé 2 secondes pour overlapping notes

2. **NEW**: PracticeController (scoring, matching, state)
   - Reçoit `PlayedNoteEvent` + `forceMatchExpectedIndex` du bridge
   - Utilise `micEngineDtMs` passé par bridge (FIX récent)
   - Grading: perfect≤40ms, good≤100ms, ok≤450ms, >450ms=miss

3. **BRIDGE**: practice_page.dart
   - Convertit HIT decisions → onPlayedNote calls
   - Passe `micEngineDtMs: decision.dtSec! * 1000.0` (FIX récent)

### 7 BUGS DÉJÀ CORRIGÉS
1. **Crash .clamp()**: arguments inversés (min > max)
2. **NoteMatcher windowMs**: 300→450ms synchronisé avec okThreshold
3. **Timeout duration**: ignorait note duration, maintenant + (duration ?? 0)
4. **scanStartIndex backward**: octave fix, min(forced, next) au lieu de max
5. **durationMs validation**: validation > 0 else null pour éviter négatif
6. **micEngineDtMs bridge**: NEW controller recalculait dt incompatible
7. **dt logic 3-way**: avant=tPlayed-start, during=0, après=tPlayed-end

---

## TON ANALYSE DOIT SUIVRE CETTE MÉTHODOLOGIE

### PHASE 1: ANALYSE SÉQUENTIELLE DES LOGS (20 minutes minimum)

Pour **CHAQUE note** (idx=0 à N), construis cette timeline:

```
1. DETECTION PITCH
   - Timestamp premier "MIC: rms=X f0=Y note=Z"
   - Vérifier: conf ≥ seuil? RMS ≥ absMinRms?

2. AJOUT AU BUFFER
   - Timestamp "BUFFER_STATE eventsInWindow=1" (premier)
   - Latence: detection → buffer = ?ms (DOIT être <100ms)

3. HIT_DECISION
   - Timestamp "result=HIT"
   - Vérifier: detectedMidi match expectedMidi?
   - Vérifier: dt calculé avec 3-way logic (before/during/after)?
   - Calculer MANUELLEMENT dt attendu:
     * Si tPlayed < note.start: dt = tPlayed - start
     * Si start ≤ tPlayed ≤ end: dt = 0
     * Si tPlayed > note.end: dt = tPlayed - end

4. RESOLVE_NOTE
   - Timestamp + grade
   - Vérifier: grade correspond à abs(dt)?
     * abs(dt) ≤ 40ms → perfect
     * abs(dt) ≤ 100ms → good
     * abs(dt) ≤ 450ms → ok
     * abs(dt) > 450ms → miss
   - Latence: HIT → RESOLVE = ?ms (DOIT être <10ms)
```

### PHASE 2: CALCULS DE VALIDATION

Pour **CHAQUE note avec HIT**, recalcule:

```python
# Extraire de window=[X..Y]
note.start = X + 0.12  # headWindow = 120ms
note.end = Y - 0.45    # tailWindow = 450ms

# Extraire de "dt=Xs" dans HIT_DECISION
tPlayed = note.start + dt  # ANCIEN calcul (avant fix)

# NOUVEAU calcul (après fix #7)
if tPlayed < note.start:
    dt_expected = tPlayed - note.start
elif tPlayed <= note.end:
    dt_expected = 0.0  # PERFECT timing
else:
    dt_expected = tPlayed - note.end

# Comparer dt du log vs dt_expected
if abs(dt_log - dt_expected) > 0.001:  # 1ms tolérance
    ❌ BUG: dt mal calculé!
```

### PHASE 3: DÉTECTION BUGS CASCADE

Cherche ces **PATTERNS CRITIQUES**:

#### Pattern 1: Race Condition Résolution
```
Si idx=N résolu APRÈS idx=N+1 alors que N chronologiquement avant:
→ Vérifier: _nextExpectedIndex avancé prématurément?
→ Vérifier: _resolvedExpectedIndices correctement protégé?
```

#### Pattern 2: Window Overlap Conflict
```
Si 2 notes windows overlap ET même pitchClass détecté:
→ Vérifier: premier HIT consomme event?
→ Vérifier: deuxième note peut trouver autre event OU timeout proprement?
```

#### Pattern 3: Timing Drift
```
Pour chaque note, calculer:
latence_totale = tResolve - tDetection_pitch

Si latence_totale > 500ms:
→ ❌ PROBLÈME: user verra feedback trop tard
```

#### Pattern 4: Buffer Pollution
```
Compter totalEvents dans logs séquentiels:
- Si totalEvents augmente >20 pendant 8 notes:
  → ❌ FUITE: events anciens pas nettoyés (seuil 2s)
```

#### Pattern 5: Grade Inconsistency
```
Pour notes avec dt similaire (±10ms):
→ Vérifier: même grade appliqué?
→ Si dt1=38ms→perfect mais dt2=42ms→good: ✓ OK (seuil 40ms)
→ Si dt1=38ms→miss: ❌ BUG CRITIQUE
```

---

## QUESTIONS OBLIGATOIRES À RÉPONDRE

### Grading System
1. Pour CHAQUE note MISS: **POURQUOI miss au lieu de ok/good/perfect?**
   - Est-ce que abs(dt) > 450ms? (légitime)
   - Est-ce que dt mal calculé? (BUG)
   - Est-ce que note pas détectée du tout? (problème pitch detection)

2. Pour notes avec dt=0 (during note): **TOUTES doivent être perfect**
   - Vérifier: aucune n'est good/ok/miss
   - Si une seule avec dt=0 n'est pas perfect: ❌ BUG CRITIQUE grading

### Timing & Latency
3. **Latence max detection→resolve**: doit être <200ms
   - Calculer pour chaque note
   - Si >300ms: identifier goulot (pitch detection? matching? autre?)

4. **Sample rate impact**: log montre sampleRate=37354 vs expected=44100
   - Est-ce que TOUS les detectedMidi matchent expectedMidi malgré ça?
   - Si UN SEUL pitch wrong: ❌ BUG sample rate compensation

### State Management
5. **Ordre résolution vs ordre chronologique**:
   - Lister ordre résolution: [idx dans ordre RESOLVE_NOTE]
   - Lister ordre chrono: [idx dans ordre tPlayed]
   - Si différents: expliquer pourquoi (acceptable si notes jouées out-of-order)

6. **Buffer size évolution**:
   - Plot totalEvents au fil du temps
   - Si croissance linéaire sans plateau: ❌ FUITE MÉMOIRE

---

## BUGS SPÉCIFIQUES À CHERCHER

### BUG POTENTIEL #8: dt Négatif Mal Géré
```
Chercher: dt=-X dans logs
Pour chaque cas:
  - Si note jouée AVANT start: dt négatif NORMAL
  - Vérifier: abs(dt) utilisé pour grading? (DOIT être abs)
  - Si grade=miss alors que abs(dt) < 450ms: ❌ BUG abs() manquant
```

### BUG POTENTIEL #9: Force Match Bypass Fail
```
Pour CHAQUE HIT_DECISION:
  - Doit être suivi IMMÉDIATEMENT par RESOLVE_NOTE (même idx)
  - Si HIT sans RESOLVE: ❌ BUG bridge call raté
  - Si RESOLVE autre idx: ❌ BUG forceMatchExpectedIndex ignoré
```

### BUG POTENTIEL #10: Octave Fix Over-Correction
```
Chercher: detectedMidi vs expectedMidi
Si abs(detectedMidi - expectedMidi) = 12 ou 24:
  → Possible octave shift
  → Vérifier: octave fix corrigé OU harmonique légitime?
Si distance = 12 et pitch class match: ❌ BUG octave fix raté
```

### BUG POTENTIEL #11: Timeout Pas Déclenché
```
Pour notes JAMAIS HIT (pas de HIT_DECISION pour idx=X):
  - Calculer timeout attendu: tExpected + duration + 750ms
  - Vérifier dans logs: session terminée avant timeout?
  - Si session continue >1s après timeout ET pas RESOLVE: ❌ BUG timeout logic
```

### BUG POTENTIEL #12: Score Calculation Wrong
```
Recalculer score manuellement:
  - perfect=100pts, good=70pts, ok=40pts, miss=0pts
  - Appliquer combo multiplier (1.05x per consecutive hit)
  - Comparer avec "SESSION4_FINAL: total=X"
  - Si différence >5pts: ❌ BUG scoring math
```

---

## FORMAT RÉPONSE ATTENDU

```markdown
## ANALYSE COMPLÈTE

### Notes Traitées (Tableau)
| idx | expectedMidi | detectedMidi | dt_log | dt_calc | grade_log | grade_expected | ✓/❌ |
|-----|--------------|--------------|--------|---------|-----------|----------------|------|
| 0   | 66 (F#4)     | 66           | 570ms  | 0ms     | miss      | perfect        | ❌   |
| ... |              |              |        |         |           |                |      |

### BUGS TROUVÉS

#### BUG #X: [Titre Court]
**Sévérité**: 🔴 CRITIQUE / 🟡 MAJEUR / 🟢 MINEUR

**Symptôme**: [Description précise]

**Preuve logs**:
```
[lignes exactes du logcat]
```

**Root Cause**: [Explication technique]

**Fix Requis**: [Code exact à modifier]

**Impact**: X/Y notes affectées (Z% des cas)

---

### BUGS POTENTIELS (Suspects)

[Même format mais marqués "À CONFIRMER"]

---

### MÉTRIQUES SANTÉ SYSTÈME

- Latence moyenne detection→resolve: Xms (objectif <200ms)
- Buffer size max: X events (limite safe: <50)
- Taux match correct: X% (objectif 100%)
- Score accuracy vs manual: ±X pts (tolérance ±5pts)

---

### ZONES À RISQUE RESTANTES

[Code paths qui semblent fragiles mais pas de preuve bug]
```

---

## RÈGLES ABSOLUES

1. **JAMAIS** dire "le code semble correct" sans preuve logs
2. **TOUJOURS** recalculer dt/grade manuellement (ne pas faire confiance aux logs)
3. **CHAQUE** anomalie doit avoir ligne log exacte citée
4. Si tu trouves <3 bugs: **TU N'AS PAS ASSEZ CHERCHÉ**
5. Si 2 bugs semblent liés: **chercher le bug cascade racine**

---

## LOGCAT À ANALYSER

[Coller ici le logcat complet de la session de test]

---

**GO - Analyse exhaustive attendue. Temps estimé: 30-45 minutes d'analyse approfondie.**
