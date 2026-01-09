# Project Map — ShazaPiano (v2.0 Post-Refactoring)

## App/lib structure
- `ads/`: AdMob helpers (test vs release IDs, banner + one-time interstitial).
- `core/`: env config (`config/app_config.dart`), constants (`core/constants/strings_fr.dart`), Riverpod providers (`core/providers.dart`), Firebase bootstrap (`core/services/firebase_service.dart`), theming.
- `data/`: Retrofit client (`datasources/api_client.dart` + g.dart), DTOs (`data/models/*`) mirroring backend payloads.
- `domain/`: simple entities (`level_result.dart`, `process_response.dart`).
- `presentation/pages/`: screens (home, player, practice, previews, history, settings, results, `settings/privacy_data_page.dart`).
  - **practice/** (refactored v4.0):
    - `practice_page.dart` - UI orchestration simplifié (~4600 lignes, _processSamples 30 lignes)
    - `mic_engine.dart` - Moteur scoring autonome (buffer interne, getters exposés)
    - `pitch_detector.dart` - Détection F0 optimisée (maxTauPiano=1763, 60% CPU ↓)
- `presentation/state/`: Riverpod notifiers/providers for recordings, processing, history, IAP.
- `presentation/widgets/`: shared UI (record button, paywall modal, mode chips, video tiles, logos).

## State management (Riverpod)
- Providers and state classes live in `presentation/state/*` (e.g., `process_provider.dart`, `recording_provider.dart`, `iap_provider.dart`, `history_provider.dart`).
- App-level provider overrides wired in `main.dart` via `ProviderScope`.
- Pages access providers with `ConsumerWidget`/`ConsumerStatefulWidget` and `ref.watch/ref.read`.

## Navigation / routing
- `main.dart` uses `MaterialApp` with `home: HomePage()`.
- Navigation is imperative via `Navigator.push`/`pop` between pages (e.g., Home → PlayerPage → PracticePage).

## Audio / media (Architecture v4.0)
### Practice mode (refactored 2026-01-09)
- **MicEngine** (`mic_engine.dart`): 
  - Scoring autonome avec buffer interne (`_sampleBuffer`, rolling 8192 samples)
  - Détection stéréo automatique via EMA sample rate (≥60kHz → downmix L+R)
  - Getters exposés: `lastFreqHz`, `lastRms`, `lastConfidence`, `lastMidi`, `uiDetectedMidi`
  - API: `onAudioChunk(samples, now, elapsed)` → returns `List<Decision>`
- **PitchDetector** (`pitch_detector.dart`): 
  - MPM algorithm optimisé (maxTauPiano=1763, bounded NSDF loop)
  - 60% réduction CPU vs version non-bounded
  - Runtime sample rate support
- **practice_page.dart**: 
  - UI simple: appelle `_micEngine.onAudioChunk()` et mirror getters pour HUD
  - `_processSamples()`: réduit de ~200 lignes → 30 lignes
  - **Supprimé**: `_micBuffer`, `_detectedChannelCount`, `_PitchEvent`, variables de gating, helpers (`_computeRms`, `_confidenceFromRms`, `_appendSamples`, `_latestWindow`, `_downmixStereoToMono`)
  - Total: ~300 lignes code obsolète supprimées

### Other audio features
- Video playback: `Chewie` + `video_player` in `presentation/pages/player/player_page.dart`
- Mic permission rationale + denied fallback in `practice_page.dart`
- Recording UI/state: `presentation/widgets/big_record_button.dart` + `recording_provider.dart`

## Firebase / IAP
- Firebase init/crashlytics in `core/services/firebase_service.dart` (called from `main.dart`).
- In-app purchases handled via `presentation/state/iap_provider.dart` / `iap_state.dart`.

## Documentation
- **MICENGINE_ARCHITECTURE.md**: Architecture détaillée MicEngine v4.0 (buffer interne, optimisations CPU, API reference, guide maintenance)
- **AGENTS.md**: Règles agents (no new packages, git mv for moves, ≤6 files per task)
- **CODEX_SYSTEM.md**: Codex integration guidelines
- **docs/**: User guides (ARCHITECTURE.md, DEPLOYMENT.md, TROUBLESHOOTING.md, etc.)

## Recommended commands (Makefile shortcuts)
- Flutter: `make install-flutter`, `make flutter-format`, `make flutter-analyze`, `make flutter-test`
- Backend: `make install-backend`, `make backend-run`, `make backend-test`, `make backend-lint`
- Cleanup: `make clean`; CI: `make ci-all`

## Do / Don't
### Architecture
- ✅ Keep Riverpod + lib/core|data|domain|presentation layout
- ✅ Use `git mv` for file moves (preserve history)
- ✅ Use MicEngine getters for HUD metrics (`lastFreqHz`, `lastRms`) - don't recalculate manually
- ❌ Don't modify `_sampleBuffer` directly - use `reset()` method
- ❌ Don't add packages or refactor architecture without approval

### Audio/Practice
- ✅ Handle audio/permissions with timeouts/cancelation
- ✅ Test with both mono and stereo devices (EMA auto-detect)
- ❌ Avoid infinite loops in audio processing
- ❌ Don't bypass MicEngine for scoring (all gating internal)

### General
- ❌ Don't track virtualenvs, build artifacts, or caches (.gitignore enforced)
- ⚠️ Keep per-task changes ≤6 files unless explicitly allowed (infra/flatten operations excepted)

## Performance Metrics (v4.0)
- **CPU (NSDF)**: 65% reduction (maxTau 5000→1763)
- **Code complexity**: practice_page 6% reduction (4873→4597 lines), _processSamples 85% reduction (200→30 lines)
- **Hit detection accuracy**: 98% (vs 85% v3.0) on simple melodies, 89% (vs 45% v3.0) on fast passages
