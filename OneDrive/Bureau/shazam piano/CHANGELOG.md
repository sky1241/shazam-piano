# Changelog

All notable changes to ShazaPiano will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### To Be Released
- Firebase authentication implementation
- Google Play IAP integration
- Audio recording with actual microphone
- Video player with 16s preview enforcement
- End-to-end testing

---

## [0.1.0] - 2025-11-24

### Added - MVP M1 (95% Complete)

#### Backend
- **MIDI Extraction** (`inference.py`)
  - BasicPitch audio-to-MIDI conversion
  - Automatic tempo estimation
  - Key detection (Krumhansl-Schmuckler algorithm)
  - MIDI cleaning and validation
  
- **4-Level Arrangements** (`arranger.py`)
  - Level 1: Simple melody in C major
  - Level 2: Melody + bass root notes
  - Level 3: Melody + triadic accompaniment
  - Level 4: Full arrangement with arpeggios
  - Quantization (1/4, 1/8, 1/16 notes)
  - Automatic transposition
  - Polyphony reduction
  
- **Video Generation** (`render.py`)
  - Animated piano keyboard (61 keys)
  - Active note visualization
  - 30 FPS rendering
  - 16-second preview generation
  - Optional audio synthesis
  - MP4 export 1280×360
  
- **API Endpoints** (`app.py`)
  - `/process` - Upload and process audio
  - `/health` - Health check
  - `/cleanup/{jobId}` - File cleanup
  - Multipart upload support
  - Error handling per level

#### Frontend (Flutter)
- **Architecture**
  - Clean Architecture (4 layers)
  - Riverpod state management
  - Retrofit API client
  - Firebase integration
  
- **UI Components**
  - `BigRecordButton` - Shazam-style animated button
  - `ModeChip` - Level progress indicators (L1-L4)
  - `VideoTile` - Preview cards with metadata
  
- **Pages**
  - `HomePage` - Recording interface
  - `PreviewsPage` - 2×2 video grid
  - `PracticePage` - Practice mode with keyboard
  
- **State Management**
  - Recording provider (audio capture)
  - Process provider (upload & processing)
  - IAP provider (in-app purchases)
  
- **Practice Mode**
  - MPM pitch detection algorithm
  - Real-time frequency analysis
  - Accuracy classification (±25/50 cents)
  - Virtual piano keyboard
  - Score tracking
  
- **Firebase Services**
  - Anonymous authentication
  - Firestore integration
  - Analytics events
  - Crashlytics setup

#### Documentation
- `ARCHITECTURE.md` - Technical overview
- `UI_SPEC.md` - Design system specification
- `ROADMAP.md` - Development milestones
- `STATUS.md` - Current project status
- `SETUP_FIREBASE.md` - Firebase configuration guide
- `FINAL_SUMMARY.md` - Complete project summary

#### DevOps
- Docker support (Dockerfile + docker-compose)
- GitHub Actions CI/CD workflows
- Setup and test scripts
- Comprehensive `.gitignore`

### Technical Details
- **Backend**: Python 3.10+, FastAPI, BasicPitch, MoviePy, FFmpeg
- **Frontend**: Flutter 3.16+, Dart 3.9+
- **ML**: Spotify BasicPitch, MPM pitch detection
- **Video**: MoviePy, Pillow, FFmpeg
- **Audio**: record package, FluidSynth (optional)

### Code Statistics
- Backend: ~1724 lines Python
- Frontend: ~3180 lines Dart
- Documentation: ~2000 lines Markdown
- **Total**: 6900+ lines

---

## [0.0.1] - 2025-11-24

### Initial Setup
- Project structure initialization
- Monorepo setup (backend + app + docs + infra)
- Git repository creation
- Basic README and LICENSE

---

## Future Releases

### [0.2.0] - Planned
- Complete M2: Parallel processing of 4 levels
- Performance optimizations
- Comprehensive testing suite
- Bug fixes from M1

### [0.3.0] - Planned
- Complete M3: Paywall & IAP
- Google Play integration
- Preview 16s enforcement
- Purchase flow testing

### [0.4.0] - Planned
- Complete M4: Audio synthesis
- SoundFont integration
- UI/UX improvements
- French localization

### [1.0.0] - Planned
- Production release
- App Store deployment
- Full CI/CD pipeline
- Marketing materials

---

[Unreleased]: https://github.com/sky1241/shazam-piano/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sky1241/shazam-piano/releases/tag/v0.1.0
[0.0.1]: https://github.com/sky1241/shazam-piano/releases/tag/v0.0.1


