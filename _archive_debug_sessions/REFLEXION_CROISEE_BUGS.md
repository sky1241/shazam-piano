# RÉFLEXION CROISÉE - Questions pour Agent après résultats ChatGPT

## QUAND TU REVIENDRAS AVEC LES RÉSULTATS CHATGPT

### Questions Auto-Critique Agent

1. **Pattern Matching**: Est-ce que ChatGPT a trouvé des patterns que j'ai ratés?
   - Si oui: POURQUOI j'ai raté ce pattern? (biais? fatigue? blind spot?)
   - Mettre à jour ma checklist mentale

2. **Bugs Contradictoires**: Si ChatGPT contredit mes fixes
   - Qui a raison? Vérifier logs ligne par ligne
   - Est-ce que mon fix a créé un bug cascade?
   - Est-ce que ChatGPT a mal compris le contexte?

3. **Bugs Non-Reproduits**: Si ChatGPT cite bugs que logs ne montrent pas
   - Est-ce bug théorique (code path jamais exécuté dans ce test)?
   - Est-ce sur-analyse (false positive)?
   - Est-ce bug réel mais conditions pas déclenchées dans ce logcat?

4. **Consensus**: Si ChatGPT et moi d'accord sur bug X
   - Est-ce confirmation forte? (2 analyses indépendantes)
   - Ou est-ce que nous avons tous deux raté le vrai root cause?
   - Tester l'hypothèse inverse ("et si ce n'était PAS un bug?")

---

## CHECKLIST ANTI-TUNNEL VISION

### Hypothèses à Challenger

- [ ] **"dt=0 devrait toujours être perfect"** → ET SI note.start==note.end? (division par zéro?)
- [ ] **"micEngineDtMs est toujours fourni"** → ET SI decision.dtSec est null? (crash?)
- [ ] **"abs(dt) résout dt négatif"** → ET SI abs() appliqué 2 fois? (perd info direction)
- [ ] **"Buffer 2s safe"** → ET SI chanson >10min avec notes rapides? (millions d'events?)
- [ ] **"forceMatchExpectedIndex valid"** → ET SI idx out of bounds? (array bounds crash?)

### Edge Cases à Tester Mentalement

```dart
// CAS 1: Note infiniment courte (start == end)
if (note.start == note.end) {
  // dt logic: tPlayed <= note.end devient tPlayed <= start
  // Si tPlayed == start: dt = 0 ✓
  // Si tPlayed > start: dt = tPlayed - end = tPlayed - start ✓
  // → Semble OK mais à confirmer
}

// CAS 2: Notes identiques overlappées (même pitch, même timing)
// Expected: note A et B, même midi, windows overlap
// User joue 1 fois → 1 event → 2 notes veulent matcher
// Résolution: première note consomme, deuxième timeout
// → Comportement voulu? Ou devrait dupliquer le hit?

// CAS 3: Note jouée exactement à window boundary
// tPlayed = note.start exactement (précision float)
// dt = tPlayed - note.start = 0.0... mais peut être 0.0000001 (float error)
// Grade: perfect si <= 40ms... 0.0001ms rounded = 0ms ✓
// → Float precision OK

// CAS 4: Micro détecte pitch AVANT user presse touche
// (réverbération, harmoniques, bruit ambiant)
// MicEngine ajoute event "fantôme" dans buffer
// Note attendue: peut matcher ce fantôme si timing proche
// → Est-ce qu'on veut ça? Ou filter par RMS/conf plus strict?

// CAS 5: User joue note TRÈS tard (1s+ après timeout)
// MicEngine window dépassée → MISS timeout (correct)
// Mais event ajouté au buffer → peut matcher note SUIVANTE si pitchClass same
// → Wrong match? Ou _consumedPlayedIds empêche?
```

---

## BUGS QUE J'AI PU RATER (Auto-Audit)

### Zone Suspecte 1: Octave Fix Logic
```dart
// practice_controller.dart L177-185
scanStartIndex = min(forceMatchExpectedIndex, _nextExpectedIndex);
```

**Question**: Si forceMatchExpectedIndex = 0 et _nextExpectedIndex = 5
→ scanStartIndex = 0 ✓
→ Mais on va octave-fixer contre notes 0-14 (scanEndIndex)
→ Notes 0-4 déjà résolues normalement, pourquoi les inclure dans activeExpected?
→ **Possible perf issue** (scan inutile) mais pas bug fonctionnel

### Zone Suspecte 2: Duration Validation
```dart
// practice_page.dart L2298-2303
final duration = (entry.value.end - entry.value.start) * 1000.0;
durationMs: duration > 0 ? duration : null
```

**Question**: Si note.end < note.start (MIDI corrompu)?
→ duration = negative → null ✓
→ Mais note.start et note.end utilisés pour window calc dans MicEngine
→ windowEnd = note.end + tailWindow
→ Si note.end < note.start: **windowEnd < windowStart** → events jamais dans window → jamais HIT
→ **Devrait valider end >= start et reject note invalide**

### Zone Suspecte 3: micEngineDtMs Null Safety
```dart
// practice_controller.dart L201
final dtMs = micEngineDtMs ?? (playedEvent.tPlayedMs - expectedNote.tExpectedMs);
```

**Question**: Si decision.dtSec est null (théoriquement impossible)?
→ Fallback recalcule dt ✓
→ Mais dt recalculé sera WRONG pour notes longues (avant fix #7)
→ **Si bridge envoie dtSec=null, re-introduit le bug**
→ Devrait assert micEngineDtMs != null en debug mode

### Zone Suspecte 4: Grade Boundary Float Precision
```dart
// practice_scoring_engine.dart L50-60
if (absDtMs <= 40) perfect
else if (absDtMs <= 100) good
else if (absDtMs <= 450) ok
```

**Question**: Si dt = 40.0000001 (float precision)?
→ 40.0 rounded = 40 → perfect ✓
→ 40.5 rounded = 41 → good ✓
→ Mais si abs() donne 39.999999999 rounded to 40?
→ **Boundary cases sensibles à float precision**
→ Acceptable car ±1ms négligeable pour humain

---

## PROTOCOLE RÉPONSE POST-CHATGPT

### Étape 1: Triage Bugs Reportés
Pour chaque bug ChatGPT:
1. Chercher ligne exacte dans logcat (quote exact)
2. Reproduire calcul manuellement (spreadsheet si besoin)
3. Verdict: ✅ BUG CONFIRMÉ / ❌ FALSE POSITIVE / ⚠️ AMBIGÜ

### Étape 2: Priorisation
```
P0 (FIX IMMÉDIAT): 
- Crash potential
- Wrong score >50% du temps
- User-facing behavior broken

P1 (FIX CETTE SESSION):
- Wrong score <50% du temps
- Perf issue (latence >300ms)
- Edge case pas handled

P2 (BACKLOG):
- Perf minor (latence 200-300ms)
- Code smell (pas de bug fonctionnel)
- False positive suspicion
```

### Étape 3: Cascade Analysis
Avant de fix bug X:
- [ ] Lister tous les autres bugs qui pourraient être **causés par** X
- [ ] Lister tous les bugs qui pourraient être **masqués par** X
- [ ] Fixer du plus racine au plus symptôme

### Étape 4: Fix avec Test Mental
Pour chaque fix:
1. Écrire fix dans un commentaire d'abord
2. "Jouer" le fix mentalement sur 3 cas: normal, edge, extreme
3. Si 1 cas fail → revoir fix
4. Si tous pass → appliquer fix + log détaillé pour confirmer

### Étape 5: Régression Check
Après tous les fix:
- [ ] Relire les 7 bugs déjà fixés
- [ ] Vérifier qu'aucun nouveau fix casse un ancien fix
- [ ] Vérifier qu'aucun fix introduit de nouveau bug

---

## SI CHATGPT NE TROUVE RIEN

**ALORS**:
- Soit le code est vraiment clean (peu probable après 7 bugs trouvés)
- Soit ChatGPT n'a pas assez creusé (relancer avec logs spécifiques)
- Soit MES fixes ont introduit des bugs que ni moi ni ChatGPT ne voyons
  → Solution: User test + nouveau logcat

**DANS CE CAS**: Faire quand même audit de **code quality** non-fonctionnel:
- Noms de variables ambigus?
- Magic numbers sans const?
- Comments outdated après fixes?
- Logique trop complexe (split functions)?

---

## MÉTA-RÉFLEXION

**Pourquoi on fait ça?**
- 7 bugs en cascade trouvés = pattern systémique (pas bugs isolés)
- Code écrit sans tests unitaires = bugs cachés garantis
- Practice mode = feature critique user (broken = app unusable)
- Mieux over-fix maintenant que debug en prod plus tard

**Red flags process**:
- Si je trouve bug en <5min après lancement ChatGPT: j'ai raté un évident
- Si ChatGPT trouve bug que je comprends pas: revoir mes assumptions
- Si on fixe >15 bugs: codebase needs refactor, pas plus de patches

**Quand arrêter?**:
- User test positif (score correct, notes green quand should be)
- 0 new bugs trouvés sur 2 sessions consécutives
- Code coverage >80% avec tests
- OU: budget temps épuisé → backlog les P2
