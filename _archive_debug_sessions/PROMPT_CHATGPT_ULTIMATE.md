) INVARIANTS STATUS (référence timebase = songTimeSec des window=[a..b]; latences = horodatage logcat 01-12 HH:MM:SS.mmm)

I1: ✅ PASS — aucun RESOLVE_NOTE idx dupliqué (idx résolus: 0,1,2,3,4,5,6) L3540,L3613,L3637,L3755,L3756,L3854,L3889
I2: ❌ FAIL — expected_notes count=8 L2651 (aussi L3310) mais SESSION4_FINAL total résolu = 2+1+2+2 = 7 L3940 ⇒ 1 note jamais RESOLVE (idx=7)
I3: ✅ PASS — match= unique pour les HIT (ec601910, 4f6199c0, dda6afff, 5206a746, d5ed96e1) L3540,L3613,L3637,L3755,L3889
I4: ⚠️ AMBIGU — tPlayedMs non extractible proprement (HIT_DECISION tronqués sur elapsed=...) ex: L3929
I5: ✅ PASS — tous window=[X..Y] ont X<Y (ex: idx7 window=[8.450..9.775]) L3929
I6: ⚠️ AMBIGU — scanStartIndex pas présent dans ce logcat (aucune ligne exploitable)
I7: ✅ PASS — une seule session observée (sessionId=1) sur les events practice (ex: L3540,L3929)
P1: ❌ FAIL — hit→resolve >10ms sur idx0 (18ms) : HIT 17:31:10.032 L7181 → RESOLVE 17:31:10.050 L7182
P2: ✅ PASS — idx0 vs idx1 (18ms vs 3ms) Δ=15ms ≤20ms : L7181→L7182 vs L7225→L7228

2) EVIDENCE TABLE (≤12)
#	Hypothèse	Impact	Condition	Logs (L####)	Code Path (fichier:ligne + if)	Invariant	Verdict	Next
1	MISS MicEngine non “finalisé” en RESOLVE quand arrêt video_end (idx=7 jamais compté)	P0	dernière note timeout proche fin vidéo	expectedCount=8 L2651 ; HIT_DECISION ... noteIdx=7 ... result=MISS L3929 ; Practice stop reason: video_end L3931 ; SESSION4_FINAL ... total=7 L3940 ; absence de RESOLVE_NOTE idx=7 (aucune occurrence)	⚠️ practice_page.dart stop(video_end) / PracticeController finalizeMissing() absent (ligne exacte non fournie)	I2	✅	PATCH
2	hit→resolve dépasse 10ms sur 1ère note (idx0)	P1	premier HIT de session	HIT idx0 17:31:10.032 L7181 → RESOLVE idx0 17:31:10.050 L7182 (Δ=18ms)	⚠️ PracticeController.onPlayedNote / scoring+setState (ligne exacte non fournie)	P1	✅	INVESTIGATE
3	TailWindow réel = 400ms (pas 450ms) ⇒ zone dt(401–450ms) “OK” potentiellement hors fenêtre	P1	si user joue tard 401–450ms	Déduit: noteEnd 0.625 (PAINTER) L3336 et windowEnd 1.025 (HIT_DECISION idx0) L7181 ⇒ tail=0.400s (idem idx7: 9.375→9.775) L3929	⚠️ mic_engine.dart const tailWindowSec (ligne exacte non fournie)	(mismatch fenêtre↔seuil OK)	⚠️	INSTRUMENT/ALIGN
3) TIMELINE (≤8 notes, idx 0–7)
idx	tExpected (start)	window (log)	tPlayed	grade_log	dt_manual	grade_expected	Latence	✓/❌
0	0.000	[-0.300..1.025] L7181	⚠️ (dt=0 ⇒ tPlayed∈[0.000..0.625])	perfect L3540	0.000s	perfect	18ms (HIT→RESOLVE) L7181→L7182	✅
1	1.250	[0.950..2.275] L7225	1.875 + 0.169 = 2.044	ok L3613	0.169s (late)	ok (≤450ms)	3ms L7225→L7228	✅
2	1.875	[1.575..3.525] L7244	⚠️ (dt=0 ⇒ tPlayed∈[1.875..3.125])	perfect L3637	0.000s	perfect	2ms L7244→L7245	✅
3	4.375	[4.075..5.400] L7300	N/A	miss L3756	N/A	miss	424ms (MISS→RESOLVE) L7300→L7315	✅
4	5.000	[4.700..6.025] L7313	5.625 + 0.202 = 5.827	ok L3755	0.202s (late)	ok (≤450ms)	1ms L7313→L7314	✅
5	6.875	[6.575..7.900] L7375	N/A	miss L3854	N/A	miss	332ms L7375→L7380	✅
6	7.500	[7.200..9.150] L7412	8.750 + 0.072 = 8.822	good L3889	0.072s (late)	good (≤100ms)	2ms L7412→L7415	✅
7	8.750	[8.450..9.775] L7440 (aussi L3929)	N/A	⚠️ (pas de RESOLVE)	N/A	miss	⚠️ (aucun RESOLVE avant stop)	❌ BUG#1
4) BUGS P0/P1 SEULEMENT
🔴 BUG #1 (P0): idx=7 MISS détecté mais jamais “RESOLVE_NOTE” avant arrêt video_end

Evidence: expected_notes ... count=8 L2651 ; HIT_DECISION ... noteIdx=7 ... result=MISS reason=timeout_no_match L3929 ; Practice stop reason: video_end L3931 ; SESSION4_FINAL ... total=7 L3940 ; aucune ligne RESOLVE_NOTE ... idx=7

Invariant: I2 ❌

Root Cause: pipeline stop coupe la phase qui convertit les timeouts en RESOLVE_NOTE (flush/finalize manquant)

Fix (action minimal): au moment du stop video_end, forcer la résolution de toutes notes non résolues jusqu’à la fin (ex: “markRemainingAsMiss(finalSongTimeSec=+∞ ou windowEnd)”)

Impact: 1/8 notes = 12.5% (score final + cohérence session)

🟠 BUG #2 (P1): hit→resolve idx0 = 18ms (>10ms)

Evidence: L7181 (17:31:10.032 result=HIT) → L7182 (17:31:10.050 RESOLVE idx0) Δ=18ms

Invariant: P1 ❌

Root Cause: scheduling/UI thread ou étape sync entre décision et résolution (non localisable précisément sans lignes code)

Fix: ⚠️ seulement si tu veux tenir le 10ms strict — instrumenter temps CPU dans onPlayedNote (voir ci-dessous) et supprimer tout await/work lourd dans le chemin HIT→RESOLVE

Impact: 1/5 HIT = 20% des HIT (mais latence faible en pratique)

5) INSTRUMENTATION (≤3 logs)
// INSTRUMENT 1: Finalisation à l’arrêt (prouve BUG#1)
// practice_page.dart (handler stop reason=video_end) OU practice_controller.dart stop()
print('FINALIZE: reason=$reason resolved=${resolvedCount} expected=${expectedCount} unresolved=${expectedCount-resolvedCount}');

// INSTRUMENT 2: Timebase + tPlayed explicite (débloque I4)
// mic_engine.dart juste avant emission de NoteDecision
print('TIMING: noteIdx=$noteIdx midi=$midi tPlayed=$tPlayedSec start=$noteStartSec end=$noteEndSec dt=$dtSec window=[$wStart..$wEnd]');

// INSTRUMENT 3: scanStartIndex monotonie (débloque I6)
// practice_controller.dart dans le matcher loop
print('SCAN: next=$_nextExpectedIndex forced=$forceMatchExpectedIndex scanStart=$scanStartIndex scanEnd=$scanEndIndex');

VIDEO OBSERVATION

NON fournie → tout diagnostic purement UX (freeze visuel, saut, feedback retardé perceptible) = ⚠️ NON VÉRIFIABLE VISUELLEMENT

EDGE CASES (présence dans ce logcat)

1 start==end: ❌ (durées ≥0.625s via PAINTER L3336…)
2 chords: ❌
3 répétitions <200ms: ❌
4 sustain/harmoniques: ⚠️ (pas prouvable via ces logs)
5 out-of-order events: ⚠️ (I4 non mesurable)
6 octave-fix cascade: ❌ (aucun “OCTAVE”)
7 end<start: ❌
8 double source notes: ⚠️ (load attendu vu 2 fois L2651/L3310, mais 8 notes uniques via PAINTER)
9 async stale callbacks: ❌ (sessionId=1 partout)
10 first note freeze: ❌ côté hit→resolve (P2 PASS), ⚠️ côté visuel (pas de table vidéo)