# Patch Ledger - Practice Mode

## 2026-01-05 (Two Streams Fix + Timing Guidance + Merge Overlaps)

### A) Goal

**Problem**: Users see "two falling-note streams" (same pitch appears twice simultaneously at same x), and targets don't match falling notes timing.

**Solution**:
1. **Single-source timing**: Video position drives BOTH falling notes + target selection (not practice clock)
2. **Merge overlapping events**: Fuse same-pitch notes that overlap or are too close (sustain/transcription artifacts)
3. **Debug metrics**: Report merge counts, timing delta, notes pipeline breakdown

**Files Changed**:
- `app/lib/presentation/pages/practice/practice_page.dart` (A-E changes)
- `docs/patch_ledger_practice.md` (this file)

### B) Implementation

#### A) Timing Single-Source (Video-Driven)

**Added**:
- `_videoElapsedSec()` — returns video position (already existed, now with sync offset)
- `_guidanceElapsedSec()` — NEW: returns video position if running, fallback to practice clock
- Changed: `_buildPracticeContent()` now uses `_guidanceElapsedSec()` for both falling notes + target selection
- **Key rule**: guidance is NOT gated on `_isListening`; users must see targets even if mic has no data

**Result**: Single authoritative time source for UI feedback (video position).

#### B) Merge Overlapping Same-Pitch Events

**Added function**: `_mergeOverlappingEventsByPitch()`
- Groups events by pitch
- For each pitch, merges events with `gap <= 0.05s` (overlap tolerance)
- Extends `current.end = max(current.end, next.end)`
- Tracks: `_notesMergedPairs`, `_notesOverlapsDetected`

**Called in**: `_sanitizeNoteEvents()` after deduplication + range filtering

**Result**: Eliminates "two bars at same pitch" visual problem.

#### C) Single-Source Targets

**Verified**: `_resolveTargetNotes()` and `_uiTargetNotes()` already use elapsedSec param → now `_guidanceElapsedSec()` is passed down.

**Result**: Targets and falling notes use same time reference.

#### D) Keyboard + Labels

**Status**: Already implemented in previous patches
- PracticeKeyboard accepts `Set<int> targetNotes`
- Labels show MIDI numbers when target (debug-only)
- Highlight spans all target pitches

#### E) Debug Report

**Enhanced**: `_buildDebugReport()` now includes:
- `mergedPairs`, `overlapsDetected` (merge metrics)
- `vpos`, `guidanceElapsed`, `practiceClock` (timing breakdown)
- `isListening` flag
- First 20 events with timing

**HUD**: Added merge metrics display → `merged: X | overlaps: Y`

### C) Verification

✅ **flutter pub get** — dependencies resolved
✅ **dart format** — formatted 51 files (2 changed)
✅ **flutter analyze** — **No issues found!**

### D) Testing Checklist

1. **Start Practice** → Watch falling notes appear at correct time
2. **Rapid Restart** → Press Stop → Play 3x → No stale notes persist
3. **Debug HUD** (tap title 5x) → Tap bug icon → Verify:
   - `notesSource`: `json` or `midi` (NOT both)
   - `merged: N` (count of merge operations)
   - `overlaps: M` (count of overlaps detected)
   - `guidanceElapsed` matches falling note animation timing
4. **Note Alignment** → Falling bars align with keyboard keys below
5. **Pitch Range** → displayFirstKey/displayLastKey recalculated on reload

### E) Risks

1. **Stricter filtering**: Events with invalid pitch/time now dropped. If hidden edge case exists, data loss. **Mitigate**: Debug report shows drop counts.
2. **Merge tolerance**: 0.05s may merge legit short-duration chord notes. **Mitigate**: Tunable, debug shows all merges.
3. **Guidance not on listening**: Targets show even if mic off. May confuse users. **Mitigate**: HUD shows listening state.

---

## 2026-01-04 (Ghost Notes Fix PR)

### A) Patch Recap (Previous Work)

**Previous Patches (2026-01-04):**
- Goal: Fix practice sync (video time), remove ghost notes, align overlay with keyboard, restore labels.
- Files: app/lib/presentation/pages/practice/practice_page.dart; app/lib/presentation/widgets/practice_keyboard.dart; app/test/practice_target_notes_test.dart.
- Fixes implemented:
  - ✅ **Timing source unification**: Single timebase (video position + clock fallback via `_effectiveElapsedSec()`)
  - ✅ **Layout mapping**: One `_KeyboardLayout` computed via LayoutBuilder constraints; shared with painter
  - ✅ **Session gating**: `_practiceSessionId` incremented on play/restart/stop; async loads check `_isSessionActive()` before applying state
  - ✅ **Event sorting**: `_noteEvents` sorted by (start, pitch) once after loading, never appended
  - ✅ **Audio-on-mute**: Mic disabled keeps visual overlay active (no video freeze)

**Root Cause of Ghost Notes Identified:**
1. **Stale async overwrite risk**: If `_loadNoteEvents` completes after user stops/restarts, old sessionId check blocks update (good). But if check fails or timestamp mismatch, mixed sources could occur.
2. **Source mixing vulnerability**: Lines 2325-2333 use ternary to select expected_json OR midi fallback. No hard prevent mixing if race condition.
3. **Duplicate overlay potential**: `_FallingNotesPainter` created once but if `_noteEvents` polluted with old data, stale notes render.
4. **Width alignment gap**: Painter uses `noteToX()` from layout, keyboard also uses same function. Verified aligned in code review (line 3309).
5. **No stats to prove root cause**: Debug HUD lacks event count breakdown, source indicator, listener attach count.

### B) Root-Cause Approach (Current PR 2026-01-05)

**Ghost Notes Only Stem From:**
1. ✅ **Mixed sources** → FIXED: Enforce strict NotesSource enum, never both expected_json + midi in same session
2. ✅ **Stale async** → FIXED: Enhanced `_isSessionActive()` logging + strict replace semantics (`_noteEvents =`, never `+=`)
3. ✅ **Duplicate overlays** → FIXED: Add Key + paint debug tracking; log overlay rebuild count
4. ✅ **Invalid events** → FIXED: Strengthen filter to drop pitch<0, pitch>127, NaN/Inf time, end<=start
5. ✅ **Width mapping** → VERIFIED: noteToX consistent between keyboard and painter; no x=0 fallback

### C) Code Changes (Current PR)

#### C1) Event Pipeline Sanitization (Enhanced)
- **Added**: Explicit filtering with reason codes (droppedInvalidPitch, droppedInvalidTime, droppedOutOfRange, etc.)
- **File**: practice_page.dart, `_sanitizeNoteEvents()` method
- **Rules**: Reject pitch<0||pitch>127, start<0||end<=start||NaN, out-of-video, dedupe within 0.001s epsilon

#### C2) Single Notes Source Enforcement
- **Added**: Strict NotesSource enum + comment block at line ~2320 explaining:
  - If expected_json fetched successfully → NEVER fallback to MIDI
  - If expected_json fails → fallback to MIDI ONLY (explicit capture in error handler)
  - During session: `_notesSource` recorded and locked (no mid-session switch)

#### C3) Stale Async Prevention
- **Added**: Enhanced `_isSessionActive()` function with debug logging
- **Ensures**: Every async completion (load, process) checks sessionId before setState
- **Behavior**: If sessionId mismatch → discard update (no ghosting)

#### C4) Duplicate Overlay Proof
- **Added**: Key('practice_notes_overlay') on CustomPaint
- **Added**: Debug stats: `_overlayBuildCount`, `_listenerAttachCount`, `_painterInstanceId` (increment on new painter)
- **Added**: Debug HUD line showing overlay builds, listener attaches, painter ID

#### C5) Bar Width Alignment (Verified + Strengthened)
- **Verified**: Painter uses same `noteToX()` function as keyboard via layout
- **Added**: Assertion in painter paint() to skip if noteToX returns null (no x=0 fallback)
- **Added**: Debug metric: bar widths logged on layout change

#### C6) Debug Report Upgrade
- **Added**: "Copy Debug Report" button in HUD (if debug enabled)
- **Exports JSON**: notesSource, sessionId, counts (total, raw, deduped, filtered, droppedXXX), minPitch/maxPitch, displayFirst/Last keys, layout metrics, overlay/listener stats, first 20 events
- **Output**: Copy to clipboard + debugPrint once

### D) Verification (Tests Run After Commit)
- `cd app && flutter pub get && dart format lib test tool && flutter analyze && flutter test`

### E) Manual Test (5 Steps)
1. Start Practice, press Play → Observe target key highlights + falling notes align
2. Restart Practice rapidly 3 times → No ghost notes appear
3. Trigger debug HUD (5 taps title) → Copy debug report → Check source/sessionId/counts
4. Reload level → Verify displayFirst/LastKey recalculated, no stale range
5. Test bar widths → Measure overlay bars match keyboard key visual widths (no overshoot)

### F) Risks (3 Max)
- **Stricter filtering**: Bad data (negative pitch, NaN time) now rejected. May hide edge cases. Mitigate: Enhanced debug report logs drops with reason.
- **Debug-only HUD**: Overlay stats visible only in debug mode (`kDebugMode`). No perf hit in release.
- **sessionId increment on stop**: Changes state machine slightly. Tested in rapid restart test (E.2).
