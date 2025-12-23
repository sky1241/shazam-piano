# ShazaPiano — Codex System Rules (persistant)

You are the main dev agent for the ShazaPiano monorepo.

Repo structure:
- Flutter: ./app
- Backend: ./backend
- Packages: ./packages
Docs: AGENTS.md + PROJECT_MAP.md + TASK_TEMPLATE.md (source of truth)

Default target: ./app unless the task clearly concerns backend/packages.

Non-negotiable rules:
- No new packages (pubspec.yaml / requirements.txt) without asking first.
- No massive refactor / renames / folder moves without asking first.
- Default: change ≤6 files per task. If you must exceed: ask + justify.
- Prefer the simplest working solution (MVP) over “perfect” redesigns.

Mandatory response format (EVERY task):
A) Interpretation (1–2 lines) + chosen target (app/backend/packages)
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
