# CHATGPT AUDIT RESULTS — Practice Mode

**Date**: 2026-01-12  
**Logcat**: Session avec 8 notes attendues, 7 résolues  
**Timebase Référence**: songTimeSec (window=[a..b])  
**Latences**: horodatage logcat `01-12 HH:MM:SS.mmm`

---

## 1) INVARIANTS STATUS

**I1: ✅ PASS** — Aucun RESOLVE_NOTE idx dupliqué  
- idx résolus: 0,1,2,3,4,5,6  
- Lignes: L3540, L3613, L3637, L3755, L3756, L3854, L3889

**I2: ❌ FAIL** — expected_notes count=8 mais SESSION4_FINAL total=7  
- Expected: 8 notes (L2651, L3310)  
- Résolu: 2 perfect + 1 good + 2 ok + 2 miss = 7 (L3940)  
- **MANQUANT: idx=7 (jamais RESOLVE)**

**I3: ✅ PASS** — match= unique pour tous HIT  
- match IDs: ec601910, 4f6199c0, dda6afff, 5206a746, d5ed96e1  
- Lignes: L3540, L3613, L3637, L3755, L3889

**I4: ⚠️ AMBIGU** — tPlayedMs non extractible proprement  
- HIT_DECISION tronqués sur elapsed=...  
- Exemple: L3929

**I5: ✅ PASS** — Tous window=[X..Y] avec X<Y  
- Exemple: idx=7 window=[8.450..9.775] (L3929)

**I6: ⚠️ AMBIGU** — scanStartIndex pas présent dans logcat  
- Aucune ligne exploitable

**I7: ✅ PASS** — Une seule session (sessionId=1)  
- Exemple: L3540, L3929

**P1: ❌ FAIL** — hit→resolve >10ms sur idx=0 (18ms)  
- HIT: 17:31:10.032 (L7181)  
- RESOLVE: 17:31:10.050 (L7182)  
- Δ = 18ms

**P2: ✅ PASS** — idx=0 vs idx=1 latence similaire  
- idx=0: 18ms (L7181→L7182)  
- idx=1: 3ms (L7225→L7228)  
- Δ = 15ms ≤ 20ms (tolérance)

---

## 2) EVIDENCE TABLE

| # | Hypothèse | Impact | Condition | Logs (L####) | Code Path | Invariant | Verdict | Next |
|---|-----------|--------|-----------|--------------|-----------|-----------|---------|------|
| 1 | MISS MicEngine non "finalisé" en RESOLVE quand arrêt video_end (idx=7 jamais compté) | P0 | dernière note timeout proche fin vidéo | expectedCount=8 L2651; HIT_DECISION noteIdx=7 result=MISS L3929; Practice stop reason: video_end L3931; SESSION4_FINAL total=7 L3940; absence RESOLVE_NOTE idx=7 | ⚠️ practice_page.dart stop(video_end) / PracticeController finalizeMissing() absent | I2 | ✅ | PATCH |
| 2 | hit→resolve dépasse 10ms sur 1ère note (idx0) | P1 | premier HIT de session | HIT idx0 17:31:10.032 L7181 → RESOLVE idx0 17:31:10.050 L7182 (Δ=18ms) | ⚠️ PracticeController.onPlayedNote / scoring+setState | P1 | ✅ | INVESTIGATE |
| 3 | TailWindow réel = 400ms (pas 450ms) ⇒ zone dt(401–450ms) "OK" potentiellement hors fenêtre | P1 | si user joue tard 401–450ms | noteEnd 0.625 L3336; windowEnd 1.025 L7181 ⇒ tail=0.400s; idx7: 9.375→9.775 L3929 | ⚠️ mic_engine.dart const tailWindowSec | mismatch fenêtre↔seuil OK | ⚠️ | INSTRUMENT/ALIGN |

---

## 3) TIMELINE (≤8 notes)

| idx | tExpected (start) | window (log) | tPlayed | grade_log | dt_manual | grade_expected | Latence | ✓/❌ |
|-----|-------------------|--------------|---------|-----------|-----------|----------------|---------|------|
| 0 | 0.000 | [-0.300..1.025] L7181 | ⚠️ (dt=0 ⇒ tPlayed∈[0.000..0.625]) | perfect L3540 | 0.000s | perfect | 18ms | ✅ |
| 1 | 1.250 | [0.950..2.275] L7225 | 2.044 (1.875+0.169) | ok L3613 | 0.169s (late) | ok (≤450ms) | 3ms | ✅ |
| 2 | 1.875 | [1.575..3.525] L7244 | ⚠️ (dt=0 ⇒ tPlayed∈[1.875..3.125]) | perfect L3637 | 0.000s | perfect | 2ms | ✅ |
| 3 | 4.375 | [4.075..5.400] L7300 | N/A | miss L3756 | N/A | miss | 424ms | ✅ |
| 4 | 5.000 | [4.700..6.025] L7313 | 5.827 (5.625+0.202) | ok L3755 | 0.202s (late) | ok (≤450ms) | 1ms | ✅ |
| 5 | 6.875 | [6.575..7.900] L7375 | N/A | miss L3854 | N/A | miss | 332ms | ✅ |
| 6 | 7.500 | [7.200..9.150] L7412 | 8.822 (8.750+0.072) | good L3889 | 0.072s (late) | good (≤100ms) | 2ms | ✅ |
| 7 | 8.750 | [8.450..9.775] L7440 (L3929) | N/A | ⚠️ (pas RESOLVE) | N/A | miss | ⚠️ | ❌ BUG#1 |

---

## 4) BUGS P0/P1

### 🔴 BUG #1 (P0): idx=7 MISS détecté mais jamais RESOLVE_NOTE avant arrêt video_end

**Evidence**:
- expected_notes count=8 (L2651)
- HIT_DECISION noteIdx=7 result=MISS reason=timeout_no_match (L3929)
- Practice stop reason: video_end (L3931)
- SESSION4_FINAL total=7 (L3940)
- Aucune ligne RESOLVE_NOTE idx=7

**Invariant**: I2 ❌ (hitCount + missCount ≠ expectedCount)

**Root Cause**: Pipeline stop coupe la phase qui convertit les timeouts en RESOLVE_NOTE (flush/finalize manquant)

**Fix Minimal**: Au moment du stop video_end, forcer résolution de toutes notes non résolues jusqu'à la fin (ex: `markRemainingAsMiss(finalSongTimeSec=∞)`)

**Impact**: 1/8 notes = 12.5% (score final + cohérence session)

---

### 🟠 BUG #2 (P1): hit→resolve idx0 = 18ms (>10ms)

**Evidence**:
- L7181 (17:31:10.032 result=HIT) → L7182 (17:31:10.050 RESOLVE idx0)
- Δ = 18ms

**Invariant**: P1 ❌ (traitement hit→resolve < 10ms)

**Root Cause**: Scheduling/UI thread ou étape sync entre décision et résolution (non localisable précisément sans lignes code)

**Fix**: ⚠️ Seulement si strictement 10ms requis
- Instrumenter temps CPU dans onPlayedNote
- Supprimer tout await/work lourd dans chemin HIT→RESOLVE

**Impact**: 1/5 HIT = 20% des HIT (mais latence faible en pratique, 18ms acceptable)

---

### ⚠️ BUG #3 (P1): TailWindow réel = 400ms (pas 450ms)

**Evidence**:
- noteEnd 0.625 (PAINTER L3336)
- windowEnd 1.025 (HIT_DECISION idx0 L7181)
- tail = 0.400s (également idx7: 9.375→9.775 L3929)

**Invariant**: Mismatch fenêtre↔seuil OK (450ms code vs 400ms runtime)

**Root Cause**: ⚠️ Constante `tailWindowSec` désynchronisée ou calcul window incorrect

**Fix**: ⚠️ INSTRUMENT d'abord (vérifier constante réelle en code)

**Impact**: Zone dt(401–450ms) pourrait être hors fenêtre → faux MISS si user joue tard

---

## 5) INSTRUMENTATION PROPOSÉE (≤3 logs)

```dart
// INSTRUMENT 1: Finalisation à l'arrêt (prouve BUG#1)
// practice_page.dart (handler stop reason=video_end) OU practice_controller.dart stop()
print('FINALIZE: reason=$reason resolved=${resolvedCount} expected=${expectedCount} unresolved=${expectedCount-resolvedCount}');

// INSTRUMENT 2: Timebase + tPlayed explicite (débloque I4)
// mic_engine.dart juste avant emission de NoteDecision
print('TIMING: noteIdx=$noteIdx midi=$midi tPlayed=$tPlayedSec start=$noteStartSec end=$noteEndSec dt=$dtSec window=[$wStart..$wEnd]');

// INSTRUMENT 3: scanStartIndex monotonie (débloque I6)
// practice_controller.dart dans le matcher loop
print('SCAN: next=$_nextExpectedIndex forced=$forceMatchExpectedIndex scanStart=$scanStartIndex scanEnd=$scanEndIndex');
```

---

## 6) EDGE CASES (Présence dans logcat)

1. **start==end**: ❌ (durées ≥0.625s via PAINTER L3336)
2. **chords**: ❌
3. **répétitions <200ms**: ❌
4. **sustain/harmoniques**: ⚠️ (pas prouvable via ces logs)
5. **out-of-order events**: ⚠️ (I4 non mesurable)
6. **octave-fix cascade**: ❌ (aucun "OCTAVE")
7. **end<start**: ❌
8. **double source notes**: ⚠️ (load attendu vu 2x L2651/L3310, mais 8 notes uniques via PAINTER)
9. **async stale callbacks**: ❌ (sessionId=1 partout)
10. **first note freeze**: ❌ côté hit→resolve (P2 PASS), ⚠️ côté visuel (pas table vidéo)

---

## VIDEO OBSERVATION

**NON fournie** → Tout diagnostic purement UX (freeze visuel, saut, feedback retardé perceptible) = ⚠️ NON VÉRIFIABLE VISUELLEMENT

---

## RÉSUMÉ EXÉCUTIF

**CONFIRMÉS** (✅):
- **BUG #1 (P0)**: idx=7 non finalisé avant stop → **FIX IMMÉDIAT REQUIS**
- **BUG #2 (P1)**: 18ms hit→resolve → acceptable en pratique, P1 strict non critique

**AMBIGUS** (⚠️):
- **BUG #3 (P1)**: TailWindow 400ms vs 450ms → **INSTRUMENT AVANT FIX**

**Priorisation**:
1. **P0**: Corriger BUG #1 (finalize missing notes at stop)
2. **P1**: Instrumenter BUG #3 (vérifier constante tailWindowSec)
3. **P2**: Ignorer BUG #2 (18ms acceptable)
