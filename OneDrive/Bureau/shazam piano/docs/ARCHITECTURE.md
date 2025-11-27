# ShazaPiano - Architecture

## Vision
Enregistrer ~8s de piano → Extraire mélodie → Générer 4 vidéos de clavier animé (Niveaux 1-4)

## Stack Technique

### Frontend (Flutter)
- **Architecture**: Clean Architecture (data/domain/presentation)
- **State Management**: Riverpod
- **Navigation**: go_router
- **HTTP**: Dio
- **Audio**: record package
- **Video**: video_player
- **IAP**: in_app_purchase
- **Firebase**: auth, firestore, crashlytics

### Backend (FastAPI)
- **Framework**: FastAPI + Uvicorn
- **ML**: BasicPitch (Spotify) pour extraction MIDI
- **Video**: MoviePy + FFmpeg
- **Audio**: Fluidsynth + SoundFont .sf2
- **MIDI**: PrettyMIDI pour arrangements

## Monétisation
- **Achat unique**: 1$ (non-consommable)
- **Previews**: 16s gratuits pour chaque niveau
- **Déblocage**: Accès complet aux 4 niveaux à vie

## 4 Niveaux de Difficulté

| Niveau | Description | Transposition | Quantification | Accompagnement |
|--------|-------------|---------------|----------------|----------------|
| L1 - Hyper Facile | Mélodie simple | → C Maj | 1/4 | Mélodie seule |
| L2 - Facile | + Basse | → C Maj | 1/8 | Fondamentale tenue |
| L3 - Moyen | + Accords | Originale | 1/8-1/16 | Triades plaquées |
| L4 - Pro | Complet | Originale | 1/16 | Arpèges + voicings |

## Flux Utilisateur

1. **Home**: Bouton circulaire → Enregistrement 8s
2. **Processing**: 4 jobs parallèles (L1-L4)
3. **Previews**: Grille 2×2 avec vidéos 16s
4. **Paywall**: Débloquer pour 1$ ou continuer en preview
5. **Player**: Lecture complète + téléchargement
6. **Practice Mode**: Détection fausses notes en temps réel

## Sécurité
- Rate limiting: 20 req/min/IP
- Max upload: 10 MB
- Timeouts: FFmpeg 15s, BasicPitch 10s, Render 20s
- Purge automatique: in/ 1j, out/ 7j

## Déploiement
- **Backend**: Docker → Fly.io / Railway / VPS
- **Frontend**: APK/AAB → Google Play Console
- **CI/CD**: GitHub Actions


