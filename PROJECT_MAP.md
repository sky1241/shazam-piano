# Project Map — ShazaPiano

## App/lib structure
- `core/`: env config (`config/app_config.dart`), constants, Riverpod providers (`core/providers.dart`), Firebase bootstrap (`core/services/firebase_service.dart`), theming.
- `data/`: Retrofit client (`datasources/api_client.dart` + g.dart), DTOs (`data/models/*`) mirroring backend payloads.
- `domain/`: simple entities (`level_result.dart`, `process_response.dart`).
- `presentation/pages/`: screens (home, player, practice, previews, history, settings, results).
- `presentation/state/`: Riverpod notifiers/providers for recordings, processing, history, IAP.
- `presentation/widgets/`: shared UI (record button, paywall modal, mode chips, video tiles, logos).

## State management (Riverpod)
- Providers and state classes live in `presentation/state/*` (e.g., `process_provider.dart`, `recording_provider.dart`, `iap_provider.dart`, `history_provider.dart`).
- App-level provider overrides wired in `main.dart` via `ProviderScope`.
- Pages access providers with `ConsumerWidget`/`ConsumerStatefulWidget` and `ref.watch/ref.read`.

## Navigation / routing
- `main.dart` uses `MaterialApp` with `home: HomePage()`.
- Navigation is imperative via `Navigator.push`/`pop` between pages (e.g., Home → PlayerPage → PracticePage).

## Audio / media
- Video playback: `Chewie` + `video_player` in `presentation/pages/player/player_page.dart` and practice preview pieces.
- Practice listening/scoring: `presentation/pages/practice/practice_page.dart` uses `sound_stream` `RecorderStream`, `PitchDetector`, and scoring logic; `audioplayers` for metronome/feedback.
- Recording UI/state: `presentation/widgets/big_record_button.dart` with `RecordButtonState`, tied into `recording_provider.dart`.

## Firebase / IAP
- Firebase init/crashlytics in `core/services/firebase_service.dart` (called from `main.dart`).
- In-app purchases handled via `presentation/state/iap_provider.dart` / `iap_state.dart`.

## Recommended commands (Makefile shortcuts)
- `make install-flutter` / `make flutter-format` / `make flutter-analyze` / `make flutter-test`.
- Backend: `make install-backend`, `make backend-run`, `make backend-test`, `make backend-lint`.
- Cleanup: `make clean`; CI bundles: `make ci-all`.

## Do / Don’t
- Do keep Riverpod + lib/core|data|domain|presentation layout; use `git mv` for moves.
- Do handle audio/permissions with timeouts/cancelation; avoid infinite loops.
- Don’t add packages or refactor architecture without approval.
- Don’t track virtualenvs, build artifacts, or caches.
- Keep per-task changes ≤6 files unless explicitly allowed.
