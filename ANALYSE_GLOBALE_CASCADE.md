# ANALYSE GLOBALE CASCADE - TOUTES SESSIONS (18 Fixes)

**Date** : 2026-01-11  
**Objectif** : Détecter TOUS bugs critiques en cascade suite aux 18 modifications

---

## 📋 INVENTAIRE COMPLET DES FIXES

### **SESSION 1-2 : 11 Fixes Core**
1. ✅ Frequency compensation (sampleRate 32-52 kHz → 44100 Hz)
2. ✅ Constant fallLead 2.0s (pas de jump countdown→running)
3. ✅ Layout stability guard (pas de preview flash)
4. ✅ Anti-replay 2s guard
5. ✅ Rectangle color change (vert quand hit)
6. ✅ Coloration sélective V4 (rectangle intersection)
7. ✅ Score dialog await (pas de flash Play)
8. ✅ UX cleanup (texte "Chargement...")
9. ✅ Fix duplicate rectTop variable
10. ✅ (Autres fixes mineurs)

### **SESSION 3 : 5 Fixes UX**
11. ✅ Suppression "ECOUTE LA NOTE"
12. ✅ Ordre écrans (Score→Play)
13. ✅ "Notes fausses" au lieu de "Score"
14. ✅ Touche rouge note fausse
15. ✅ Précision timing (±10ms=100%)

### **CASCADE SESSION 3 : 2 Fixes**
16. ✅ wrongNotes = total - _correctNotes
17. ✅ try-finally dialog protection

**TOTAL : 18 FIXES**

---

## 🔍 ANALYSE CASCADE GLOBALE

### **ZONE CRITIQUE #1 : TIMING & SCORING**

**Modifications impliquées** :
- FIX 1 : Frequency compensation
- FIX 15 : Précision timing
- FIX 16 : wrongNotes calcul

**Analyse flux** :
```
1. Audio chunk arrive
2. Frequency compensée (FIX 1) : freq = freqRaw × (44100 / detectedSampleRate)
3. MIDI détecté : midi = 12 × log2(freq/440) + 69
4. Note hit décidée par MicEngine
5. Timing error calculé : dtSec
6. Score pondéré (FIX 15) : _score += _calculateTimingScore(|dtSec| × 1000)
7. Dialog affiche (FIX 16) : wrongNotes = total - _correctNotes
```

**BUG CRITIQUE CASCADE #A : Double comptage notes**

**Scénario** :
- User joue C4 pendant 1.5s (note tenue)
- MicEngine envoie PLUSIEURS decisions `hit` pour la même note
- Chaque hit → `_correctNotes += 1` ET `_score += timingScore`
- Résultat : 1 note jouée comptée comme 3-4 hits

**Validation code** :
```dart
// practice_page.dart ligne ~2502
case mic.DecisionType.hit:
  _correctNotes += 1; // ❌ Incrémenté à chaque decision
  _score += timingScore;
```

**Vérification MicEngine** (besoin de lire le code) :
- Est-ce que MicEngine envoie 1 hit par note OU plusieurs hits par note tenue ?
- Chercher : `DecisionType.hit` émission logic

**Impact** :
- Si plusieurs hits : `_correctNotes` > `_totalNotes` → wrongNotes NÉGATIF
- Dialog : "Notes fausses: -2" ❌ CRITIQUE

**Risque** : **TRÈS ÉLEVÉ** 🚨

---

### **ZONE CRITIQUE #2 : STATE MANAGEMENT**

**Modifications impliquées** :
- FIX 7 : Score dialog await
- FIX 12 : setState après dialog
- FIX 17 : try-finally protection

**Analyse flux** :
```
1. Practice termine (_stopPractice)
2. Video pause
3. _micSub?.cancel()
4. setState supprimé (déplacé après dialog)
5. await _showScoreDialog (dans try-finally)
6. setState(_practiceRunning = false) dans finally
7. _lastVideoEndAt = DateTime.now()
```

**BUG POTENTIEL CASCADE #B : Mic streaming après stop**

**Scénario** :
- Practice termine
- `_micSub?.cancel()` appelé MAIS `_isListening` pas encore false
- MicEngine continue à traiter chunks pendant 50-200ms
- `onAudioChunk` appelé → `setState` → Crash si `mounted = false`

**Validation nécessaire** :
```dart
// practice_page.dart ligne ~2290
_micSub?.cancel();
_micSub = null;

// MAIS _isListening encore true jusqu'à finally block
// Delay entre cancel et setState(_isListening = false)
```

**Fix potentiel** :
```dart
// Mettre _isListening = false IMMÉDIATEMENT
_isListening = false; // Before cancel
_micSub?.cancel();
_micSub = null;
```

**Risque** : **MOYEN** ⚠️

---

### **ZONE CRITIQUE #3 : VISUAL RENDERING**

**Modifications impliquées** :
- FIX 5 : Rectangle color change vert
- FIX 6 : Coloration V4 intersection
- FIX 14 : Touche rouge note fausse

**Analyse flux** :
```
1. Paint notes tombantes
2. Check intersection keyboard (FIX 6)
3. isTarget = isCrossingKeyboard && targetNotes.contains(pitch)
4. Rectangle couleur : successFlash > wrongFlash > isTarget > default

5. Paint keyboard
6. Check isWrong = isDetected && !isExpected (FIX 14)
7. Touche couleur : successFlash > wrongFlash > isWrong > isDetected > default
```

**BUG POTENTIEL CASCADE #C : Conflit couleurs note VS touche**

**Scénario** :
- User joue C4 (fausse note)
- Rectangle C4 tombant : devient vert (successFlash) OU rouge (wrongFlash) ?
- Touche C4 clavier : devient rouge (isWrong)
- Conflit visuel : rectangle vert + touche rouge

**Validation logique** :
```dart
// practice_keyboard.dart ligne ~169
if (successFlashActive && ...) {
  keyColor = success; // ✅ Priority 1
} else if (wrongFlashActive && ...) {
  keyColor = error; // ✅ Priority 2
} else if (isWrong) {
  keyColor = error; // ✅ Priority 3
}

// practice_page.dart ligne ~4580 (notes tombantes)
if (successFlash) {
  color = success; // ✅ Priority 1
} else if (wrongFlash) {
  color = error; // ✅ Priority 2
} else if (isTarget) {
  color = highlight; // ✅ Priority 3
}
```

**Observation** :
- Si wrongFlash actif → Rectangle rouge ET touche rouge ✅ COHÉRENT
- Si successFlash actif → Rectangle vert ET touche verte ✅ COHÉRENT

**Risque** : **FAIBLE** ✅

---

### **ZONE CRITIQUE #4 : COUNTDOWN & PRACTICE STATE**

**Modifications impliquées** :
- FIX 2 : Constant fallLead 2.0s
- FIX 11 : Suppression "ECOUTE LA NOTE"
- FIX 12 : setState après dialog

**Analyse flux** :
```
1. User clique Play
2. _practiceState = countdown
3. Countdown 3s (notes tombent, mic actif mais MIDI disabled)
4. Countdown termine → _practiceState = running
5. Mic events → MicEngine → decisions
```

**BUG POTENTIEL CASCADE #D : Mic events pendant countdown**

**Scénario** :
- User clique Play
- Countdown 3s
- User joue des notes pendant countdown
- MicEngine traite ces notes → decisions `hit` / `wrongFlash`
- `_correctNotes` incrémenté AVANT practice start

**Validation code** :
```dart
// Chercher : countdown state check dans onAudioChunk
// Est-ce que MicEngine ignore events pendant countdown ?
```

**Si pas de check** :
```dart
// practice_page.dart ligne ~2490
if (elapsed != null && _micEngine != null) {
  // ❌ Pas de check _practiceState == running
  final decisions = _micEngine!.onAudioChunk(samples, now, elapsed);
  for (final decision in decisions) {
    _correctNotes += 1; // Incrémenté pendant countdown !
  }
}
```

**Impact** :
- Score faussé si user joue pendant countdown
- `_correctNotes` déjà à 5 quand practice start

**Risque** : **MOYEN** ⚠️

---

### **ZONE CRITIQUE #5 : FREQUENCY COMPENSATION EDGE CASES**

**Modifications impliquées** :
- FIX 1 : Frequency compensation
- FIX 15 : Précision timing

**Analyse flux** :
```
1. Device sampleRate détecté : 48000 Hz
2. Frequency raw détectée : 261.0 Hz
3. Compensation : freq = 261.0 × (44100 / 48000) = 239.9 Hz ❌
4. MIDI calculé : faux pitch
5. Hit enregistré sur fausse note
```

**BUG CRITIQUE CASCADE #E : Over-compensation**

**Problème** :
- Si device sampleRate > 44100 Hz → compensation BAISSE frequency
- C4 (261 Hz) devient B3 (246 Hz)
- Toutes notes détectées 1 demi-ton trop bas

**Validation formula** :
```dart
// mic_engine.dart ligne ~161
freq = freqRaw × (44100 / _detectedSampleRate)

Si detectedSampleRate = 48000 :
freq = freqRaw × 0.919 → Fréquence BAISSE ❌
```

**Correction nécessaire ?**
- Vérifier si formula est inversée
- Devrait être : `freq = freqRaw × (_detectedSampleRate / 44100)` ?

**OU** :
- Formula correcte car audio échantillonné à sampleRate donné
- Need validation mathématique

**Risque** : **CRITIQUE SI FORMULA FAUSSE** 🚨

---

### **ZONE CRITIQUE #6 : MEMORY LEAKS & CLEANUP**

**Modifications impliquées** :
- FIX 4 : Anti-replay 2s
- FIX 12 : setState déplacé
- FIX 17 : try-finally

**Analyse flux** :
```
1. _stopPractice appelé
2. _micSub?.cancel() (async)
3. _videoController?.pause() (async)
4. await _showScoreDialog (peut prendre 10s si user AFK)
5. setState enfin exécuté dans finally
```

**BUG POTENTIEL CASCADE #F : Subscriptions non-cancellées**

**Scénario** :
- User termine practice
- Dialog s'affiche
- User laisse dialog ouvert 5 minutes (AFK)
- `_micSub` cancel mais `_recorder` pas stopped ?
- Memory leak : audio recorder continue

**Validation code** :
```dart
// practice_page.dart ligne ~2298
try {
  await _recorder.stop(); // ✅ Stopped AVANT cancel
} catch (_) {}
_micSub?.cancel();
```

**Observation** :
- `_recorder.stop()` AVANT `_micSub.cancel()` ✅ OK
- try-catch protège contre errors ✅ OK

**Risque** : **FAIBLE** ✅

---

### **ZONE CRITIQUE #7 : NULL SAFETY & RACE CONDITIONS**

**Modifications impliquées** :
- Toutes les modifications qui touchent state variables

**Variables critiques** :
```dart
int? _detectedNote;
int? _lastCorrectNote;
int? _lastWrongNote;
VideoPlayerController? _videoController;
MicEngine? _micEngine;
```

**BUG POTENTIEL CASCADE #G : Race condition setState**

**Scénario** :
```
Thread 1 (UI):
- _stopPractice() appelé
- await _showScoreDialog (bloqué 5s)

Thread 2 (Mic callback - delayed):
- onAudioChunk appelé (mic pas encore cancel)
- setState(() => _detectedNote = 60)
- CRASH si widget unmounted pendant dialog
```

**Protection actuelle** :
```dart
// practice_page.dart ligne ~2514
if (mounted) {
  setState(() {});
}
```

**Mais** :
```dart
// Si mounted check AVANT setState, pas DANS setState
// Race possible entre check et setState execution
```

**Fix robuste** :
```dart
if (mounted) {
  setState(() {
    // Safe: mounted déjà vérifié
  });
}
```

**Risque** : **FAIBLE** (protection déjà en place) ✅

---

## 🚨 BUGS CRITIQUES IDENTIFIÉS

### **PRIORITÉ CRITIQUE** 🔴

#### **BUG CASCADE #A : Double comptage notes**
- **Impact** : wrongNotes négatif, scores faussés
- **Probabilité** : TRÈS ÉLEVÉE
- **Fix nécessaire** : Vérifier MicEngine hit emission logic

#### **BUG CASCADE #E : Frequency over-compensation**
- **Impact** : Toutes notes détectées faux pitch
- **Probabilité** : ÉLEVÉE si sampleRate > 44100 Hz
- **Fix nécessaire** : Valider formula mathématiquement

### **PRIORITÉ HAUTE** 🟡

#### **BUG CASCADE #B : Mic streaming après stop**
- **Impact** : setState sur unmounted widget
- **Probabilité** : MOYENNE
- **Fix recommandé** : `_isListening = false` avant cancel

#### **BUG CASCADE #D : Mic events pendant countdown**
- **Impact** : Score faussé
- **Probabilité** : MOYENNE
- **Fix recommandé** : Check `_practiceState == running`

### **PRIORITÉ FAIBLE** 🟢

#### **BUG CASCADE #C : Conflit couleurs**
- **Impact** : Visuel confus
- **Probabilité** : FAIBLE
- **Status** : Logique cohérente ✅

#### **BUG CASCADE #F : Memory leak**
- **Impact** : RAM usage
- **Probabilité** : TRÈS FAIBLE
- **Status** : Protection déjà en place ✅

#### **BUG CASCADE #G : Race condition**
- **Impact** : Crash setState
- **Probabilité** : TRÈS FAIBLE
- **Status** : Protection mounted check ✅

---

## 🔧 FIXES IMMÉDIATS REQUIS

### **FIX CRITIQUE #1 : Vérifier MicEngine hit logic**

**Besoin** : Lire `mic_engine.dart` pour confirmer :
- 1 hit par note OU multiple hits par note tenue ?
- Si multiple : Ajouter deduplication logic

**Localisation** : `app/lib/presentation/pages/practice/mic_engine.dart`

---

### **FIX CRITIQUE #2 : Valider frequency compensation formula**

**Besoin** : Vérifier mathématiquement :
```dart
freq = freqRaw × (44100 / detectedSampleRate)
```

**Tests** :
- Device 48000 Hz : C4 (261 Hz) → doit donner C4 MIDI 60
- Device 32000 Hz : C4 (261 Hz) → doit donner C4 MIDI 60

**Si faux** : Inverser formula

---

### **FIX HAUTE PRIORITÉ #3 : Stop mic events pendant countdown**

```dart
// practice_page.dart ligne ~2490
if (elapsed != null && _micEngine != null && _practiceState == _PracticeState.running) {
  // Ignore events si pas running
  final decisions = _micEngine!.onAudioChunk(samples, now, elapsed);
  // ...
}
```

---

### **FIX HAUTE PRIORITÉ #4 : _isListening false immédiat**

```dart
// practice_page.dart ligne ~2295
_isListening = false; // IMMÉDIAT
_micDisabled = false;

_micSub?.cancel();
_micSub = null;
```

---

## 📊 RÉSUMÉ ANALYSE GLOBALE

### **BUGS CRITIQUES** : 2 🚨
1. Double comptage notes (CASCADE #A)
2. Frequency over-compensation (CASCADE #E)

### **BUGS HAUTE PRIORITÉ** : 2 ⚠️
3. Mic streaming après stop (CASCADE #B)
4. Mic events countdown (CASCADE #D)

### **BUGS FAIBLE PRIORITÉ** : 3 ✅
5. Conflit couleurs (CASCADE #C) - OK
6. Memory leak (CASCADE #F) - OK
7. Race condition (CASCADE #G) - OK

### **ACTIONS REQUISES** :
1. ✅ Lire MicEngine hit emission logic
2. ✅ Valider frequency compensation math
3. ✅ Appliquer FIX #3 et #4
4. ✅ Tester avec devices différents sampleRate

---

**Status** : **2 CRITIQUES + 2 HAUTES PRIORITÉS à investiguer/fixer**  
**Next** : Lire `mic_engine.dart` pour CASCADE #A
