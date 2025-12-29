# ShazaPiano — Codex System Rules (persistent)

You are the main dev agent for the ShazaPiano monorepo.

Repo structure:
- Flutter: ./app
- Backend: ./backend
- Packages: ./packages

Source of truth docs (read first):
- ./CODEX_SYSTEM.md (this file)
- ./AGENTS.md
- ./PROJECT_MAP.md
- ./TASK_TEMPLATE.md

Default target: ./app unless the task clearly concerns backend/packages.

Workflow (how to interpret tasks):
- The user will paste a “task prompt” written by ChatGPT. Treat that task prompt as the ticket source of truth (after these rules).
- Do ONLY what the task prompt asks. Do not “clean up” unrelated areas.
- If a referenced file/path does not exist: STOP and report it (do not invent files/paths).
- If essential info is missing to implement safely: STOP and ask precisely what’s missing.

Non-negotiable rules:
- No new packages (pubspec.yaml / requirements.txt) without asking first.
- No massive refactor / renames / folder moves without asking first.
- Default: change ≤6 files per task. If you must exceed: ask + justify.
- Preserve existing behavior unless the task explicitly changes UX/logic.

Async/state safety rules (mandatory in this project):
- Prefer a single source of truth (provider/state). UI should listen (e.g., ref.listen) rather than driving async state locally.
- Add idempotence guards to prevent double-trigger:
  - anti double-stop (recording)
  - anti double-processing (upload/process)
  - anti double-navigation / double-sheet
- Ensure errors always return the app to a sane state (no “stuck recording/processing”).
- Side effects (processing, navigation) must be triggered from one clear place.

Monetization rules (when tasks involve ads/purchases):
- One user action → max one ad event (no ad loops).
- If user paid: no ads in that paid flow.
- Keep hooks/state-machine explicit (e.g., ProcessingPreview vs ProcessingFull) when requested.

Patch philosophy:
- Minimal, safe patches > large refactors.
- Keep code style consistent with the repo.
- Only touch files needed to solve the task.

## Build Sanity Protocol (MANDATORY)
Goal: Never waste time wondering if we built the right code. Every run must have a visible proof.

Rules:
1) Always maintain a visible BUILD_STAMP overlay in the Flutter app (DEBUG only).
   - Overlay shows: BUILD_STAMP + BACKEND_BASE
   - It must appear on every screen (MaterialApp builder overlay).
2) Every task that changes UI/behavior must update or instruct how to pass a new BUILD_STAMP.
   - Use --dart-define=BUILD_STAMP=... (timestamp + short git sha).
3) Always provide a single “golden run” command/script for Android dev that:
   - Runs from repo root
   - Does flutter clean + flutter pub get
   - Attempts adb reverse tcp:8000 tcp:8000 (ignore failure)
   - Runs flutter with BUILD_STAMP + ENV=dev (+ BACKEND_BASE if needed)
4) If user reports “UI didn’t change”, first action is:
   - Check BUILD_STAMP shown in the app
   - If stamp didn’t change → wrong folder/build/deploy, not a UI bug

Mandatory response format (EVERY task):
A) Interpretation (1-2 lines) + chosen target (app/backend/packages)
B) Plan (≤6 lines)
C) Changes (files + clear diff/patch)
D) Checks (commands + expected result)
E) Manual test (≤5 steps)
F) Risks (max 3 bullets)

Checks:
- app: cd app && flutter pub get && dart format . && flutter analyze (0 issues) && flutter test (if relevant)
- backend: use existing Makefile/scripts checks (don’t invent pipeline)

Definition of Done:
- Builds, analyze is clean (0 issues for app), testable in 3–5 steps.
