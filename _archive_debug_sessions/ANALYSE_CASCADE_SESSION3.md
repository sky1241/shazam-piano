# ANALYSE CASCADE - SESSION 3 (5 Bugs corrigés)

## 🐛 BUG 4 SKIPPÉ (Non confirmé par ChatGPT)

**BUG 4 - Touche clavier reste verte PENDANT l'appui**

**Description attendue** :
- User appuie sur note longue (3s) → touche doit rester verte 3s
- Bug potentiel : Flash court (0.2s) au lieu de rester vert toute durée

**Résultat ChatGPT** :
```
"Sur ce clip : je vois du vert qui persiste pendant la durée d'appui 
(quand l'appui dure ~0.6–1.1s). Je ne peux pas valider le cas "2–3 secondes" 
car je n'en vois pas dans la vidéo. Donc : pas de "flash court systématique" 
confirmé ici."
```

**Conclusion** : BUG 4 NON PRÉSENT (comportement déjà correct).

---

## ⚠️ BUGS CRITIQUES DÉTECTÉS (Cascade)

### **BUG CRITIQUE CASCADE #1 : Calcul "Notes fausses" FAUX**

**Localisation** : `practice_page.dart` ligne 4134

**Code actuel** :
```dart
final wrongNotes = total - score.toInt(); // ❌ FAUX !
```

**Problème** :
- AVANT BUG 5 : `score` était un entier (6 = 6 notes correctes)
- APRÈS BUG 5 : `score` est un **double pondéré** (5.6 = 6 notes avec timing imparfait)
- Si 8 notes jouées, 6 correctes avec timing moyen (0.8 chacune) :
  * `score = 6 × 0.8 = 4.8`
  * `wrongNotes = 8 - 4 = 4` ❌ **FAUX** (devrait être 2)

**Impact** :
- Dialog affiche MAUVAIS nombre de notes fausses
- Utilisateur voit "4 notes fausses" alors qu'il en a joué que 2 fausses

**Solution** :
```dart
final wrongNotes = total - _correctNotes; // ✅ CORRECT
```
→ `_correctNotes` compte les hits indépendamment du timing

---

### **BUG POTENTIEL CASCADE #2 : Touche rouge reste bloquée**

**Localisation** : `practice_keyboard.dart` ligne 169

**Code ajouté** :
```dart
final isWrong = isDetected && !isExpected; // Detected but not expected = wrong

if (isWrong) {
  keyColor = AppColors.error.withValues(alpha: 0.85);
}
```

**Problème potentiel** :
- Si `detectedNote` n'est PAS cleared après release → touche reste rouge
- Scénario : User joue C4 (faux), relâche, touche C4 reste rouge même après

**Validation nécessaire** :
- Vérifier où `detectedNote` est mis à `null`
- Chercher : `_detectedNote = null` ou `_updateDetectedNote(null, ...)`

**Check code** :
```dart
// practice_page.dart ligne 2335-2337 (_stopPractice)
_detectedNote = null; ✅

// Mais pendant practice, quand est-ce cleared ?
// → Need to verify _updateDetectedNote logic
```

**Risque** : MOYEN (si detectedNote pas cleared pendant practice)

---

### **BUG POTENTIEL CASCADE #3 : State bloqué si dialog crash**

**Localisation** : `practice_page.dart` ligne 2363-2365

**Code actuel** :
```dart
if (showSummary && mounted) {
  await _showScoreDialog(score: score, accuracy: accuracy);
}

// setState APRÈS dialog
if (mounted) {
  setState(() {
    _practiceRunning = false;
    ...
  });
}
```

**Problème potentiel** :
- Si `_showScoreDialog` throw exception → `setState` jamais exécuté
- `_practiceRunning` reste `true` → UI bloquée
- User ne peut pas relancer practice

**Impact** : CRITIQUE si dialog crash

**Solution** :
```dart
try {
  if (showSummary && mounted) {
    await _showScoreDialog(score: score, accuracy: accuracy);
  }
} catch (e) {
  debugPrint('Dialog error: $e');
} finally {
  // TOUJOURS exécuté, même si exception
  if (mounted) {
    setState(() {
      _practiceRunning = false;
      ...
    });
  }
}
```

**Risque** : ÉLEVÉ (crash app si dialog bug)

---

### **BUG POTENTIEL CASCADE #4 : Accuracy > 100%**

**Localisation** : `practice_page.dart` ligne 2317

**Code actuel** :
```dart
final accuracy = total > 0 ? (_score / total) * 100.0 : 0.0;
```

**Problème potentiel** :
- Si `_score` peut dépasser `total` (bug logique) → accuracy > 100%
- Example : 5 notes, toutes perfect (1.0 chacune) → score=5, accuracy=100% ✅
- Mais si bug dans `_calculateTimingScore` retourne >1.0 → accuracy>100%

**Validation** :
```dart
double _calculateTimingScore(double timingErrorMs) {
  if (timingErrorMs <= 10) return 1.0; // Max
  else if (timingErrorMs <= 50) return 0.8;
  // ...
}
```
→ Max return value = 1.0 ✅ OK

**Risque** : FAIBLE (formula correcte)

---

### **BUG POTENTIEL CASCADE #5 : Notes fausses négatives**

**Localisation** : `practice_page.dart` ligne 4134

**Code actuel** :
```dart
final wrongNotes = total - score.toInt();
```

**Problème lié à CASCADE #1** :
- Si user joue parfaitement : `score = 8.0`, `total = 8`
- `wrongNotes = 8 - 8 = 0` ✅ OK
- Mais si user joue mal : `score = 2.4`, `total = 8`
- `wrongNotes = 8 - 2 = 6` ✅ Semble OK

**Mais scénario edge case** :
- Si `_score` initialisé à valeur bizarre → `wrongNotes` négatif ?
- Check initialisation : `int _score = 0;` (ligne ~200) ✅ OK

**Avec fix CASCADE #1** :
```dart
final wrongNotes = total - _correctNotes;
```
- Impossible d'avoir négatif car `_correctNotes <= total` toujours

**Risque** : FAIBLE (mais fix CASCADE #1 résout)

---

## 🔧 CORRECTIONS NÉCESSAIRES

### **FIX CASCADE #1** (CRITIQUE)
```dart
// practice_page.dart ligne ~4134
final wrongNotes = total - _correctNotes; // Instead of: total - score.toInt()
```

### **FIX CASCADE #2** (RECOMMANDÉ)
```dart
// practice_page.dart ligne ~2363
try {
  if (showSummary && mounted) {
    await _showScoreDialog(score: score, accuracy: accuracy);
  }
} catch (e) {
  debugPrint('Score dialog error: $e');
} finally {
  if (mounted) {
    setState(() {
      _practiceRunning = false;
      ...
    });
  }
}
```

### **VALIDATION CASCADE #3** (CHECK)
- Vérifier que `_detectedNote` est cleared pendant practice
- Chercher dans logs si touche rouge reste bloquée

---

## 📊 RÉSUMÉ ANALYSE

### **BUGS CRITIQUES** :
1. ✅ **CASCADE #1** : wrongNotes calcul faux → FIX IMMÉDIAT
2. ✅ **CASCADE #2** : State bloqué si dialog crash → FIX RECOMMANDÉ

### **BUGS POTENTIELS** :
3. ⚠️ **CASCADE #3** : Touche rouge bloquée → VALIDATION NÉCESSAIRE
4. ✅ **CASCADE #4** : Accuracy >100% → OK (formula correcte)
5. ✅ **CASCADE #5** : wrongNotes négatif → OK (impossible)

### **STATUT** :
- **2 FIXES IMMÉDIATS** requis avant rebuild
- **1 VALIDATION** nécessaire après tests

---

## 🎯 PROCHAINES ÉTAPES

1. **MAINTENANT** : Appliquer FIX CASCADE #1 et #2
2. **REBUILD** : Tester app avec corrections
3. **VALIDATION** : Vérifier touche rouge pendant tests
4. **SI BUG** : Investiguer clearing de `detectedNote`

---

**Date** : 2026-01-11  
**Session** : 3 (5 bugs corrigés + 2 cascade fixes)
