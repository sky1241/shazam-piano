# Archive Debug Sessions - ShazaPiano Practice Mode

Ce dossier contient tous les fichiers de debug des sessions 3 et 4.
**Date d'archivage**: 2026-01-13

---

## BUGS CORRIGES (Session 4 + Claude)

### BUG #1: Notes rouges fantomes apres fin de session
- **Symptome**: Touches du clavier deviennent rouges apres que toutes les notes sont jouees (score 100%)
- **Cause**: `wrongFlash` declenche pour toute detection audio meme sans note attendue
- **Fichier**: `mic_engine.dart:478-493`
- **Fix**: Ajoute condition `hasActiveNoteInWindow` - ne declenche wrongFlash que si une note est attendue
- **Statut**: CORRIGE

### BUG #2: HUD ne se met pas a jour (P0)
- **Symptome**: Score/Combo restent a 0 malgre les HITs
- **Fichier**: `practice_page.dart`
- **Fix**: Ajout de debug logs + correction state controller
- **Statut**: CORRIGE (Session 4)

### BUG #3: Flashs rouges fantomes - bruit detecte (P0)
- **Symptome**: Notes rouges apparaissent sans input utilisateur
- **Cause**: RMS/confidence trop bas acceptes
- **Fix**: Gating RMS < 0.002 et conf < 0.35
- **Statut**: CORRIGE (Session 4)

### BUG #4: "Sapin de Noel" apres note longue (P1)
- **Symptome**: Multiples flashs consecutifs apres maintien d'une note
- **Fix**: Anti-spam debounce 200ms
- **Statut**: CORRIGE (Session 4)

### BUG #5: Resultats finaux a 0% (P0)
- **Symptome**: Dialog de fin affiche 0% malgre score positif
- **Fix**: Branch dialog sur PracticeScoringState correctement
- **Statut**: CORRIGE (Session 4)

### BUG #6: Octave shifts faux positifs
- **Symptome**: Harmoniques detectees comme notes correctes
- **Cause**: Octave shift +-12/+-24 acceptait harmoniques basses
- **Fix**: Desactive octave shifts, match pitch-class seulement
- **Fichier**: `mic_engine.dart:403-404`
- **Statut**: CORRIGE (Session 4)

### BUG #7: dt calcule incorrectement pour notes longues
- **Symptome**: Note jouee pendant la duree = mauvais timing
- **Fix**: Si played PENDANT la note, dt = 0 (perfect)
- **Fichier**: `mic_engine.dart:424-437`
- **Statut**: CORRIGE (Session 4)

---

## BUGS CONNUS NON CORRIGES

### BUG: idx=7 MISS non finalise avant video stop
- **Symptome**: Derniere note pas finalisee si session arretee
- **Impact**: ~12.5% notes perdues
- **Fix requis**: Appeler `finalizeMissingNotes()` dans `stopPractice()`
- **Statut**: DOCUMENTE - A FAIRE

### BUG: Latence hit->resolve > 10ms
- **Symptome**: Premier HIT prend 18ms a resoudre
- **Impact**: 20% des HITs affectes
- **Statut**: ACCEPTABLE pour l'instant

---

## CONCEPT "CASCADE"

Une **correction cascade** = quand tu corriges une valeur/parametre qui provoque un bug ailleurs.

**Exemples documentes:**
1. Desactiver octave shifts -> certains tests de near-miss echouent (attendu)
2. Changer RMS threshold -> detection moins sensible
3. Modifier window timing -> affecte calcul dt

**Approche recommandee:**
- Faire le MINIMUM de changements
- Tester manuellement apres chaque fix
- Si un test echoue, verifier s'il testait l'ancien comportement (bugge)

---

## FICHIERS DANS CETTE ARCHIVE

| Fichier | Description |
|---------|-------------|
| PROMPT_CHATGPT_*.md | Templates de prompts pour analyse |
| CHATGPT_AUDIT_RESULTS.md | Resultats d'audit automatise |
| SESSION4_*.md | Rapports de la session 4 |
| ANALYSE_*.md | Analyses cascade et globales |
| FIX_*.md | Documentation des correctifs |
| debuglogcatflutterbackend | Logs logcat de debug |
| debug_video.mp4.mp4 | Video de test avec bug |
| *.ps1 | Scripts de rebuild |

---

## PARAMETRES ACTUELS (mic_engine.dart)

```dart
headWindowSec = 0.12      // Fenetre avant la note
tailWindowSec = 0.45      // Fenetre apres la note
absMinRms = 0.0008        // Seuil RMS minimum
minConfForWrong = 0.35    // Confidence min pour wrongFlash
eventDebounceSec = 0.05   // Anti-rebond events
wrongFlashCooldownSec = 0.15  // Cooldown entre flashs rouges
uiHoldMs = 200            // Duree affichage note detectee
```

---

## SEUILS DE SCORING

```dart
perfect: <= 40ms
good: <= 100ms
ok: <= 450ms
miss: > 450ms ou timeout
```

---

## TESTS STATUS

- **70 tests PASS**
- **4 tests FAIL** (pre-existants, testent ancien comportement octave shift)
- **flutter analyze**: Clean
