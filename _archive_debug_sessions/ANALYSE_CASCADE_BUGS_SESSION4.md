# ANALYSE CASCADE BUGS CRITIQUES - SESSION 4 CORRECTIONS

**Date**: 2026-01-11  
**Contexte**: Analyse post-correctifs bugs runtime scoring system  
**Sévérité**: 🔴 CRITIQUE - 3 bugs P0, 🟡 MAJEUR - 4 bugs P1, 🟢 MINEUR - 2 bugs P2

---

## 🚨 RÉSUMÉ EXÉCUTIF

**Statut des corrections appliquées**: ⚠️ **PARTIELLEMENT DÉFECTUEUSES**

**Bugs critiques introduits**: **3 bugs P0** + **4 bugs P1** + **2 bugs P2**

**Impact**: 
- 🔴 Anti-spam bloque notes correctes (faux négatifs)
- 🔴 HUD ne se rafraîchit toujours pas (setState manquant)
- 🔴 Variables anti-spam jamais réinitialisées entre sessions
- 🟡 MIDI échappe à l'anti-spam (incohérence micro/MIDI)
- 🟡 Gating appliqué uniquement aux wrongs (hit contaminés)
- 🟡 Constantes dupliquées (magic numbers)

**Action requise**: Correctifs urgents avant tests manuels

---

## 🔴 BUGS CRITIQUES (P0) - BLOCANTS

### BUG CASCADE #1: Anti-spam bloque notes correctes successives

**Sévérité**: 🔴 **P0 - BLOCANT**

#### Description
L'anti-spam `_lastProcessedMidi` et `_lastProcessedAt` sont **partagés entre hit ET wrongFlash**. Si une note wrong est détectée (ex: D2 fantôme RMS bas), puis immédiatement après une note correcte avec le même MIDI (ex: D2 réel), la note correcte sera bloquée par l'anti-spam.

#### Code problématique
```dart
// Ligne 337-338
int? _lastProcessedMidi;  // GLOBAL: partagé entre hit et wrongFlash
DateTime? _lastProcessedAt;

// Ligne 2693-2702 (hook micro hit)
if (_lastProcessedMidi == decision.detectedMidi &&
    _lastProcessedAt != null &&
    now.difference(_lastProcessedAt!) < const Duration(milliseconds: 200)) {
  debugPrint('SESSION4_ANTISPAM: Skip duplicate midi=${decision.detectedMidi} (< 200ms)');
  break; // ⚠️ Skip note correcte si même MIDI détecté < 200ms avant (même wrong)
}
```

#### Scénario de reproduction
1. **t=0ms**: Détection fantôme D2 (RMS=0.001, conf=0.08) → wrongFlash → `_lastProcessedMidi = 50`
2. **t=100ms**: Joueur joue vraiment D2 (RMS=0.150, conf=1.00) → hit
3. **Résultat**: Hit bloqué par anti-spam (même MIDI < 200ms) → **Note correcte ignorée**

#### Impact
- Faux négatifs: notes correctes non comptabilisées
- Score/combo restent à 0 même quand joueur joue bien
- Précision calculée incorrecte

#### Correctif requis
**Option A (recommandée)**: Séparer anti-spam hit et wrongFlash
```dart
// Variables état distinctes
int? _lastHitMidi;
DateTime? _lastHitAt;
int? _lastWrongMidi;
DateTime? _lastWrongAt;

// Hook hit: utiliser _lastHitMidi/_lastHitAt
if (_lastHitMidi == decision.detectedMidi && ...) { ... }

// Hook wrongFlash: utiliser _lastWrongMidi/_lastWrongAt
if (_lastWrongMidi == decision.detectedMidi && ...) { ... }
```

**Option B (simple)**: Anti-spam uniquement pour hit (supprimer du wrongFlash)
```dart
// Garder anti-spam uniquement dans hit (sapin = notes correctes tenues)
// wrongFlash déjà filtré par gating RMS/conf → moins besoin debounce
```

---

### BUG CASCADE #2: HUD ne se rafraîchit toujours pas (setState manquant)

**Sévérité**: 🔴 **P0 - BLOCANT**

#### Description
Le HUD lit `_newController!.currentScoringState` mais **aucun `setState()` n'est appelé** après les mises à jour du controller dans les hooks micro/MIDI. Le widget `_buildTopStatsLine()` ne se rebuild jamais → HUD reste figé à 0.

#### Code problématique
```dart
// Ligne 2730 (hook micro hit) - PAS de setState après onPlayedNote
_newController!.onPlayedNote(playedEvent);
// Check if NEW SYSTEM registered a correct hit
final stateAfter = _newController!.currentScoringState;
// ... flash green ...
// ⚠️ AUCUN setState() ici

// Ligne 710-726 (HUD) - Lit state mais widget jamais rebuild
if (_useNewScoringSystem && _newController != null) {
  final newState = _newController!.currentScoringState; // ⚠️ Lecture statique, pas reactive
  final matched = newState.perfectCount + newState.goodCount + newState.okCount;
  statsText = 'Précision: ... Score: ${newState.totalScore} ...';
}
```

#### Scénario de reproduction
1. Joueur joue note correcte
2. `onPlayedNote()` appelé → controller met à jour `PracticeScoringState`
3. HUD `build()` **pas déclenché** → affiche toujours valeurs initiales (0/0/0)

#### Impact
- HUD figé à "Précision: 0% Notes justes: 0/X Score: 0 Combo: 0"
- Joueur pense que le système ne fonctionne pas
- Impossible de valider que le scoring marche sans logs

#### Correctif requis
**Option A (recommandée)**: setState après chaque mise à jour controller
```dart
// Après onPlayedNote dans hook hit (ligne ~2730)
_newController!.onPlayedNote(playedEvent);

if (correctCountAfter > correctCountBefore) {
  _registerCorrectHit(...);
  setState(() {}); // ⚠️ AJOUTER: Force rebuild HUD
}

// Après onPlayedNote dans hook wrongFlash (ligne ~2815)
_newController!.onPlayedNote(playedEvent);

if (wrongCountAfter > wrongCountBefore) {
  _registerWrongHit(...);
  setState(() {}); // ⚠️ AJOUTER: Force rebuild HUD
}

// Après onPlayedNote dans hook MIDI (ligne ~3783)
_newController!.onPlayedNote(playedEvent);
_newController!.onTimeUpdate(elapsed * 1000.0);

if (correctCountAfter > correctCountBefore) {
  _registerCorrectHit(...);
  setState(() {}); // ⚠️ AJOUTER: Force rebuild HUD
} else if (wrongCountAfter > wrongCountBefore) {
  _registerWrongHit(...);
  setState(() {}); // ⚠️ AJOUTER: Force rebuild HUD
}
```

**Option B (architecture propre - plus complexe)**: 
- Convertir `PracticeController` en `StateNotifier<PracticeViewState>`
- Écouter le state via `ref.watch()` (Riverpod)
- Rebuilds automatiques quand state change
→ **Hors scope Session 4** (refactor trop lourd)

---

### BUG CASCADE #3: Variables anti-spam jamais réinitialisées

**Sévérité**: 🔴 **P0 - CRITIQUE**

#### Description
Les variables `_lastProcessedMidi` et `_lastProcessedAt` **ne sont jamais reset** entre sessions. Si une session se termine avec `_lastProcessedMidi = 60`, la session suivante démarre avec cette valeur → première note MIDI 60 sera bloquée.

#### Code problématique
```dart
// Ligne 2495-2517 (setState dans _stopPractice) - anti-spam PAS reset
setState(() {
  _detectedNote = null;
  _lastMicFrameAt = null;
  _micRms = 0.0;
  // ... autres resets ...
  _micConfigLogged = false;
  _micLatencyCompSec = 0.0;
  // ⚠️ MANQUANT: _lastProcessedMidi = null;
  // ⚠️ MANQUANT: _lastProcessedAt = null;
});
```

#### Scénario de reproduction
1. **Session 1**: Termine avec note C4 (midi=60) jouée à t=15.0s
   - `_lastProcessedMidi = 60`
   - `_lastProcessedAt = 2026-01-11 19:46:25.000`
2. **Session 2**: Démarre 1 seconde plus tard (19:46:26.000)
3. **t=0.1s Session 2**: Joueur joue C4 immédiatement
4. **Résultat**: 
   - `now - _lastProcessedAt = 1.1s` → **> 200ms, OK**
   - **MAIS** si Session 2 démarre < 200ms après Session 1 fin → **C4 bloqué**

#### Impact
- Première(s) note(s) de session suivante potentiellement ignorées
- Comportement non-déterministe selon timing entre sessions
- Bug difficile à reproduire (dépend timing utilisateur)

#### Correctif requis
```dart
// Ajouter dans setState() de _stopPractice (ligne ~2495)
setState(() {
  // ... existing resets ...
  _micConfigLogged = false;
  _micLatencyCompSec = 0.0;
  
  // ⚠️ AJOUTER: Reset anti-spam
  _lastProcessedMidi = null;
  _lastProcessedAt = null;
});
```

**Également ajouter** dans `_startPractice()` (défense en profondeur):
```dart
// Ligne ~2200 dans _startPractice
_score = 0;
_correctNotes = 0;
_totalNotes = _noteEvents.length;
// ... existing resets ...

// ⚠️ AJOUTER: Reset anti-spam au démarrage (defense in depth)
_lastProcessedMidi = null;
_lastProcessedAt = null;
```

---

## 🟡 BUGS MAJEURS (P1) - FONCTIONNALITÉ DÉGRADÉE

### BUG CASCADE #4: MIDI échappe à l'anti-spam (incohérence micro/MIDI)

**Sévérité**: 🟡 **P1 - MAJEUR**

#### Description
L'anti-spam s'applique uniquement aux événements **micro** (lignes 2693-2702). Les événements **MIDI** n'ont aucun debounce → comportement incohérent entre les 2 sources d'entrée.

#### Code problématique
```dart
// Hook micro hit (ligne 2693) - anti-spam ACTIVÉ
if (_lastProcessedMidi == decision.detectedMidi && ...) {
  break; // Skip duplicate
}

// Hook MIDI (ligne 3763) - anti-spam ABSENT
if (_useNewScoringSystem && _newController != null) {
  // ⚠️ PAS de check anti-spam ici
  final playedEvent = PracticeController.createPlayedEvent(
    midi: note,
    tPlayedMs: elapsed * 1000.0,
    source: NoteSource.midi,
  );
  _newController!.onPlayedNote(playedEvent);
}
```

#### Scénario de reproduction
1. **Mode micro**: Note tenue C4 → spam détecté → anti-spam filtre doublons → OK
2. **Mode MIDI**: Note tenue C4 → **aucun filtre** → spam envoyé au controller → potential sapin

**Mais**: MIDI hardware génère typiquement note-on/note-off propres (pas de spam naturel comme micro pitch detector). Donc **moins critique** que bug #1.

#### Impact
- Incohérence comportement micro vs MIDI
- Potentiel "sapin" en mode MIDI si contrôleur génère spam (rare)
- Code dupliqué entre micro et MIDI (pas DRY)

#### Correctif requis
**Option A**: Appliquer anti-spam également au MIDI
```dart
// Hook MIDI (ajouter avant ligne 3763)
if (_useNewScoringSystem && _newController != null) {
  // ⚠️ AJOUTER: Anti-spam aussi pour MIDI
  if (_lastProcessedMidi == note &&
      _lastProcessedAt != null &&
      now.difference(_lastProcessedAt!) < const Duration(milliseconds: 200)) {
    return; // Skip duplicate MIDI event
  }
  
  _lastProcessedMidi = note;
  _lastProcessedAt = now;
  
  // ... reste du code ...
}
```

**Option B**: Garder MIDI sans anti-spam (documenter différence)
```dart
// Hook MIDI: Pas d'anti-spam car MIDI hardware génère events propres
// Contrairement au micro (pitch detector continu), MIDI envoie note-on/off discrets
```

---

### BUG CASCADE #5: Gating RMS/conf appliqué uniquement aux wrongs

**Sévérité**: 🟡 **P1 - MAJEUR**

#### Description
Le gating strict `RMS < 0.002 || conf < 0.35` est appliqué uniquement dans `wrongFlash` (ligne 2802). Les événements `hit` **ne sont pas filtrés** → si le micro détecte une note correcte avec RMS très bas (fantôme), elle sera comptabilisée comme hit.

#### Code problématique
```dart
// Hook wrongFlash (ligne 2802) - gating ACTIVÉ
if (_micRms < minRmsThreshold || _micConfidence < minConfThreshold) {
  debugPrint('SESSION4_GATING: Skip wrongFlash ...');
  break; // Filtre wrongs fantômes
}

// Hook hit (ligne 2693) - gating ABSENT
if (_useNewScoringSystem && _newController != null && decision.detectedMidi != null) {
  // ⚠️ PAS de check RMS/conf ici
  // Si MicEngine dit "hit" avec RMS=0.001, on l'accepte aveuglément
}
```

#### Scénario de reproduction
1. **MicEngine** détecte note correcte C4 (expected) avec RMS=0.0015, conf=0.20
2. MicEngine émet `DecisionType.hit` (car pitch match + timing OK)
3. Hook hit **accepte sans vérifier RMS/conf** → comptabilise hit fantôme
4. **Résultat**: Faux positif (note jamais jouée comptée correcte)

**Pourquoi moins grave que wrongs fantômes**:
- MicEngine a déjà ses propres seuils internes (`absMinRms`, `minConfCorrect`)
- `DecisionType.hit` émis seulement si pitch match + timing + conf suffisante
- Donc double gating (MicEngine + hook) **redondant** pour hits
- Mais **nécessaire** pour wrongs car MicEngine peut émettre wrongFlash sur bruits bas

#### Impact
- Théoriquement: Faux positifs (hits fantômes)
- En pratique: MicEngine filtre déjà donc impact faible
- Incohérence: gating dans wrongFlash mais pas hit

#### Correctif requis
**Option A** (défense en profondeur): Ajouter gating aussi dans hit
```dart
// Hook hit (ajouter après ligne 2693)
if (_useNewScoringSystem && _newController != null && decision.detectedMidi != null) {
  // ⚠️ AJOUTER: Gating strict aussi pour hits (defense in depth)
  const minRmsThreshold = 0.0020;
  const minConfThreshold = 0.35; // Ou minConfCorrect (plus strict que minConfWrong)
  if (_micRms < minRmsThreshold || _micConfidence < minConfThreshold) {
    if (kDebugMode) {
      debugPrint('SESSION4_GATING_HIT: Skip hit midi=${decision.detectedMidi} rms=${_micRms.toStringAsFixed(3)} conf=${_micConfidence.toStringAsFixed(2)} (below threshold)');
    }
    break; // Ignore hit fantôme
  }
  
  // ... reste du code ...
}
```

**Option B** (documenter): Garder gating uniquement wrongFlash (justifier dans commentaire)
```dart
// Hook wrongFlash: Gating strict nécessaire car MicEngine peut émettre wrongFlash sur bruits
// Hook hit: Pas de gating car MicEngine filtre déjà avec absMinRms/minConfCorrect
```

---

### BUG CASCADE #6: Constantes dupliquées (magic numbers)

**Sévérité**: 🟡 **P1 - MAJEUR (maintenabilité)**

#### Description
Les seuils `minRmsThreshold = 0.0020` et `minConfThreshold = 0.35` sont **hardcodés** dans le hook wrongFlash au lieu d'utiliser les valeurs du `MicEngine` (qui les a déjà configurées).

#### Code problématique
```dart
// Hook wrongFlash (ligne 2803-2804)
const minRmsThreshold = 0.0020; // ⚠️ Dupliqué: même valeur que MicEngine.absMinRms
const minConfThreshold = 0.35;  // ⚠️ Dupliqué: même valeur que MicEngine.minConfWrong

// MicEngine init (ligne ~2256)
_micEngine = mic.MicEngine(
  // ...
  absMinRms: 0.0020,
  minConfCorrect: 0.60,
  minConfWrong: 0.35,
  // ...
);
```

#### Impact
- **Maintenance**: Si on change seuils dans MicEngine, faut aussi changer dans hook wrongFlash
- **Désynchronisation**: Risque que les 2 valeurs divergent (MicEngine dit 0.0050, hook dit 0.0020)
- **Confusion**: Deux "sources de vérité" pour mêmes seuils

#### Correctif requis
**Option A** (recommandée): Stocker seuils en variables instance
```dart
// Ligne ~325 (variables d'état)
double _absMinRms = 0.0020;
double _minConfWrong = 0.35;
double _minConfCorrect = 0.60;

// Init MicEngine (ligne ~2256)
_micEngine = mic.MicEngine(
  // ...
  absMinRms: _absMinRms,
  minConfCorrect: _minConfCorrect,
  minConfWrong: _minConfWrong,
  // ...
);

// Hook wrongFlash (ligne ~2803)
if (_micRms < _absMinRms || _micConfidence < _minConfWrong) {
  // ... filtre ...
}
```

**Option B**: Créer classe `MicConfig` partagée
```dart
class MicConfig {
  static const double absMinRms = 0.0020;
  static const double minConfCorrect = 0.60;
  static const double minConfWrong = 0.35;
}

// Usage partout
_micEngine = mic.MicEngine(absMinRms: MicConfig.absMinRms, ...);
if (_micRms < MicConfig.absMinRms || _micConfidence < MicConfig.minConfWrong) { ... }
```

---

### BUG CASCADE #7: `stopPractice()` appelé 2 fois (duplication)

**Sévérité**: 🟡 **P1 - MAJEUR (idempotence)**

#### Description
`_newController!.stopPractice()` est appelé **deux fois** dans `_stopPractice()`: une fois dans le branchement dialog (ligne 2473), une autre fois après le setState (ligne 2526).

#### Code problématique
```dart
// Ligne 2460-2482 (branchement dialog)
if (_useNewScoringSystem && _newController != null) {
  // NEW SYSTEM: Use PracticeScoringState
  _newController!.stopPractice(); // ⚠️ APPEL #1
  final newState = _newController!.currentScoringState;
  // ...
}

// Ligne 2520-2530 (après setState)
// ═══════════════════════════════════════════════════════════════
// SESSION 4: Stop NEW controller and finalize p95 timing metric
// ═══════════════════════════════════════════════════════════════
if (_useNewScoringSystem && _newController != null) {
  _newController!.stopPractice(); // ⚠️ APPEL #2 (même condition)
  if (kDebugMode) {
    // ...
  }
}
```

#### Scénario
1. `_stopPractice()` appelé
2. Condition `_useNewScoringSystem && _newController != null` → true
3. **Appel #1**: `stopPractice()` → calcule p95, set `isActive = false`
4. `setState()` + dialog
5. **Appel #2**: `stopPractice()` → re-calcule p95 (valeurs inchangées)

#### Impact
- **Actuellement**: Pas de crash (méthode idempotente)
- **Risque futur**: Si `stopPractice()` modifie state (ex: exporte logs), double effet
- **Performance**: Calcul p95 dupliqué (négligeable mais inutile)
- **Maintenabilité**: Code confus (pourquoi 2 appels ?)

#### Correctif requis
**Supprimer le deuxième appel** (garder uniquement le premier):
```dart
// Ligne 2460-2482: GARDER cet appel
if (_useNewScoringSystem && _newController != null) {
  _newController!.stopPractice(); // ✅ OK ici
  final newState = _newController!.currentScoringState;
  score = newState.totalScore.toDouble();
  accuracy = total > 0 ? (matched / total * 100.0) : 0.0;
  
  if (kDebugMode) {
    debugPrint('SESSION4_CONTROLLER: Stopped. Final score=...');
    debugPrint('SESSION4_FINAL: perfect=... good=... ok=...');
  }
}

// Ligne 2520-2530: SUPPRIMER ce bloc entier
// ⚠️ À SUPPRIMER (dupliqué)
/*
if (_useNewScoringSystem && _newController != null) {
  _newController!.stopPractice();
  if (kDebugMode) {
    // ...
  }
}
*/
```

---

## 🟢 BUGS MINEURS (P2) - POLISH

### BUG CASCADE #8: Logs debug non conditionnés à nouveau système

**Sévérité**: 🟢 **P2 - MINEUR**

#### Description
Les logs `SESSION4_DEBUG_HIT` et `SESSION4_SCORING_DIFF` apparaissent même si `_useNewScoringSystem = false`. Devrait être conditionné.

#### Correctif
Déjà dans des blocs `if (_useNewScoringSystem)` donc **pas de bug réel**. Garder tel quel.

---

### BUG CASCADE #9: Pas de logs pour MIDI events

**Sévérité**: 🟢 **P2 - MINEUR**

#### Description
Les hooks micro ont logs `SESSION4_DEBUG_HIT` et `SESSION4_DEBUG_WRONG`, mais le hook MIDI n'a **aucun log équivalent**. Rend debugging mode MIDI plus difficile.

#### Correctif requis
```dart
// Hook MIDI (ajouter après ligne 3783)
if (kDebugMode) {
  debugPrint('SESSION4_DEBUG_MIDI: Before onPlayedNote - midi=$note correctCount=$correctCountBefore wrongCount=$wrongCountBefore');
}

_newController!.onPlayedNote(playedEvent);
_newController!.onTimeUpdate(elapsed * 1000.0);

if (kDebugMode) {
  debugPrint('SESSION4_DEBUG_MIDI: After onPlayedNote - correctCount=$correctCountAfter wrongCount=$wrongCountAfter score=${stateAfter.totalScore}');
}
```

---

## 📊 SYNTHÈSE BUGS PAR PRIORITÉ

| ID | Priorité | Nom | Impact | Complexité fix |
|----|----------|-----|--------|----------------|
| #1 | 🔴 P0 | Anti-spam bloque notes correctes | **CRITIQUE** - Faux négatifs | Moyenne (refactor variables) |
| #2 | 🔴 P0 | HUD ne se rafraîchit pas | **CRITIQUE** - Pas de feedback visuel | Facile (3x setState) |
| #3 | 🔴 P0 | Variables anti-spam jamais reset | **CRITIQUE** - Bug inter-sessions | Facile (2 lignes) |
| #4 | 🟡 P1 | MIDI échappe à anti-spam | Majeur - Incohérence | Facile (copier anti-spam) |
| #5 | 🟡 P1 | Gating uniquement wrongs | Majeur - Faux positifs potentiels | Facile (copier gating) |
| #6 | 🟡 P1 | Constantes dupliquées | Majeur - Maintenabilité | Moyenne (refactor config) |
| #7 | 🟡 P1 | stopPractice() appelé 2x | Majeur - Idempotence | Facile (supprimer bloc) |
| #8 | 🟢 P2 | Logs debug non conditionnés | Mineur - Polish | Aucun (déjà OK) |
| #9 | 🟢 P2 | Pas de logs MIDI | Mineur - Debug MIDI | Facile (copier logs) |

---

## 🔧 PLAN CORRECTIFS RECOMMANDÉ

### Phase 1: Fixes P0 (blocants) - 30min

```dart
// FIX #2 (P0): Ajouter setState dans hooks (3 emplacements)
// practice_page.dart ligne ~2740
if (correctCountAfter > correctCountBefore) {
  _registerCorrectHit(...);
  setState(() {}); // AJOUT
}

// practice_page.dart ligne ~2825
if (wrongCountAfter > wrongCountBefore) {
  _registerWrongHit(...);
  setState(() {}); // AJOUT
}

// practice_page.dart ligne ~3793
if (correctCountAfter > correctCountBefore) {
  _registerCorrectHit(...);
  setState(() {}); // AJOUT
} else if (wrongCountAfter > wrongCountBefore) {
  _registerWrongHit(...);
  setState(() {}); // AJOUT
}

// FIX #3 (P0): Reset anti-spam dans _stopPractice
// practice_page.dart ligne ~2515
setState(() {
  // ... existing resets ...
  _lastProcessedMidi = null;  // AJOUT
  _lastProcessedAt = null;    // AJOUT
});

// FIX #1 (P0): Séparer anti-spam hit et wrongFlash
// practice_page.dart ligne ~337
int? _lastHitMidi;       // AJOUT
DateTime? _lastHitAt;    // AJOUT
int? _lastWrongMidi;     // AJOUT
DateTime? _lastWrongAt;  // AJOUT

// Supprimer _lastProcessedMidi et _lastProcessedAt

// Hook hit ligne ~2693: utiliser _lastHitMidi/_lastHitAt
if (_lastHitMidi == decision.detectedMidi && ...) { ... }
_lastHitMidi = decision.detectedMidi;
_lastHitAt = now;

// Hook wrongFlash ligne ~2810: utiliser _lastWrongMidi/_lastWrongAt
if (_lastWrongMidi == decision.detectedMidi && ...) { ... }
_lastWrongMidi = decision.detectedMidi;
_lastWrongAt = now;
```

### Phase 2: Fixes P1 (majeurs) - 45min

```dart
// FIX #7 (P1): Supprimer duplication stopPractice
// practice_page.dart ligne ~2526-2530: SUPPRIMER ce bloc

// FIX #6 (P1): Extraire constantes en variables instance
// practice_page.dart ligne ~325
double _absMinRms = 0.0020;
double _minConfWrong = 0.35;

// Utiliser partout au lieu de const

// FIX #4 (P1): Anti-spam MIDI
// practice_page.dart ligne ~3763: copier logique anti-spam du micro

// FIX #5 (P1): Gating hit (optionnel, défense en profondeur)
// practice_page.dart ligne ~2693: copier logique gating du wrongFlash
```

### Phase 3: Fixes P2 (polish) - 15min

```dart
// FIX #9 (P2): Logs MIDI
// practice_page.dart ligne ~3783: ajouter logs SESSION4_DEBUG_MIDI
```

**Total estimé**: ~1h30

---

## ✅ CHECKLIST VALIDATION POST-CORRECTIFS

### Tests statiques
- [ ] `flutter analyze --no-fatal-infos` → No issues found
- [ ] `flutter test --no-pub` → All tests passed

### Tests runtime (avec logs)
- [ ] **HUD se met à jour**: Vérifier que "Score" et "Combo" changent en temps réel
- [ ] **Pas de faux négatifs**: Note correcte après note wrong (même MIDI) comptabilisée
- [ ] **Pas de faux positifs**: Silence ne génère pas de hits fantômes
- [ ] **Anti-spam cohérent**: Note tenue ne génère pas de sapin (micro ET MIDI)
- [ ] **Reset entre sessions**: Session 2 démarre propre (pas d'état résiduel Session 1)

### Tests edge cases
- [ ] Session très courte (< 200ms entre notes)
- [ ] Alternance rapide micro/MIDI
- [ ] Note tenue > 5 secondes
- [ ] Dialog fermé puis nouvelle session immédiate

---

## 📝 CONCLUSION

**Corrections Session 4 initiales**: Ont corrigé bugs identifiés mais **introduit 9 nouveaux bugs** (3 critiques).

**Cause racine**: 
- Manque de `setState()` (architecture reactive pas respectée)
- Variables globales partagées sans isolation
- Duplication logique micro/MIDI (pas DRY)
- Pas de reset état entre sessions

**Recommandation**: Appliquer **Phase 1 (P0) immédiatement** avant tests manuels. Phase 2/3 peuvent attendre validation terrain.

**Effort total**: ~1h30 correctifs + ~30min tests = **2h**

**Post-correctifs**: Relancer analyse cascade pour vérifier qu'aucun nouveau bug introduit.
