# ShazaPiano - Roadmap

## 🎯 Milestones

### M1 - MVP (Niveau 1 muet) ✅
**Objectif**: Proof of concept avec un seul niveau

**Backend**:
- [x] Endpoint `/process?level=1`
- [x] m4a → wav conversion (FFmpeg)
- [x] BasicPitch → MIDI extraction
- [x] Keyboard render → MP4 (muet)

**Flutter**:
- [x] Enregistrement audio (record package)
- [x] Upload vers backend (Dio)
- [x] Lecteur vidéo (video_player)
- [x] Gros bouton central type Shazam

**Firebase**:
- [x] Projet créé
- [x] Auth anonyme
- [x] Firestore (profil user basique)

**Telemetry**:
- [x] Crashlytics ou Sentry (minimal)

**Critère de succès**: MP4 jouable en <60s, gestion erreurs micro/réseau

---

### M2 - 4 Niveaux + UI Modes 🎯
**Objectif**: Générer les 4 niveaux en parallèle

**Backend**:
- [ ] Refactor `arrange(level)` pour L1-L4
- [ ] Accompagnements:
  - L1: Mélodie seule
  - L2: + Basse (fondamentale)
  - L3: + Triades plaquées
  - L4: + Arpèges complets
- [ ] Endpoint retourne tableau de 4 objets

**Flutter**:
- [ ] Écran Previews (grille 2×2)
- [ ] 4 VideoTiles avec states
- [ ] Navigation vers Player individuel
- [ ] Historique local (dernière session)

**Backend optimisations**:
- [ ] Jobs parallèles avec asyncio
- [ ] Warm-up modèle BasicPitch au boot
- [ ] Semaphore pour limiter concurrence

---

### M3 - Paywall 1$ (IAP) 💰
**Objectif**: Monétisation avec previews 16s

**Flutter IAP**:
- [ ] Setup in_app_purchase package
- [ ] Produit non-consommable: `piano_all_levels_1usd`
- [ ] Flow: query → purchase → acknowledge
- [ ] Restore purchases au démarrage
- [ ] Persistance: SharedPreferences + Firestore

**Backend Previews**:
- [ ] Générer `preview_16s.mp4` + `full.mp4`
- [ ] API retourne `preview_url` et `video_url`
- [ ] Protection: ne pas exposer URLs complètes avant achat

**UI**:
- [ ] PaywallModal avec CTA "1$"
- [ ] Badge "16s preview" sur tiles
- [ ] Déblocage: preview_url → video_url

**Google Play Console**:
- [ ] Créer produit IAP
- [ ] Configurer comptes test sandbox
- [ ] Tester flow complet

---

### M4 - Audio + Robustesse 🎵
**Objectif**: Ajouter audio piano optionnel

**Backend Audio**:
- [ ] Intégrer Fluidsynth + SoundFont .sf2
- [ ] Synthèse MIDI → WAV
- [ ] Mux audio dans MP4 (FFmpeg)
- [ ] Flag `?with_audio=true/false`

**Filesystem**:
- [ ] Purge cron: /in >1j, /out >7j
- [ ] Quotas utilisateur (max 10 générations/jour)
- [ ] Timeouts stricts (FFmpeg 15s, BasicPitch 10s, Render 20s)

**Firebase Rules**:
- [ ] Sécuriser Firestore (users own data)
- [ ] Rate limiting côté Firebase
- [ ] Validation entitlements côté serveur

**Error Handling**:
- [ ] Retry logic avec exponential backoff
- [ ] Messages d'erreur user-friendly
- [ ] Logging structuré (JSON)

---

### M5 - CI/CD & Release Alpha 🚀
**Objectif**: Automatisation et première release

**GitHub Actions**:
- [ ] Workflow Flutter:
  - `flutter analyze`
  - `flutter test`
  - Build APK/AAB
  - Sign release
- [ ] Workflow Backend:
  - Lint (black, flake8)
  - Tests pytest
  - Build Docker image
  - Push to registry

**Déploiement Backend**:
- [ ] Dockerfile optimisé (multi-stage)
- [ ] Deploy sur Fly.io / Railway / VPS
- [ ] Nginx reverse proxy
- [ ] SSL/TLS (Let's Encrypt)
- [ ] Monitoring: /health endpoint

**Play Console**:
- [ ] Créer app (com.ludo.shazapiano)
- [ ] Upload AAB signé
- [ ] Closed testing track
- [ ] Descriptions + screenshots
- [ ] Privacy policy

**Release**:
- [ ] Internal testing (5-10 users)
- [ ] Closed testing (50-100 users)
- [ ] Open beta
- [ ] Production 🎉

---

## 📅 Timeline Estimé

| Milestone | Durée | Status |
|-----------|-------|--------|
| M1 - MVP | 1-2 semaines | ✅ À démarrer |
| M2 - 4 Niveaux | 1 semaine | ⏳ Pending |
| M3 - Paywall | 1 semaine | ⏳ Pending |
| M4 - Audio | 1 semaine | ⏳ Pending |
| M5 - CI/CD | 1 semaine | ⏳ Pending |

**Total estimé**: 5-7 semaines jusqu'à alpha release

---

## 🎯 Prochaines Actions Immédiates

1. ✅ Initialiser monorepo (app/, backend/, infra/, docs/)
2. 🔄 Setup Flutter avec Clean Architecture
3. 🔄 Setup Backend FastAPI + BasicPitch
4. 🔄 Firebase projet + Auth + Firestore
5. ⏳ M1: Endpoint /process + Flutter record/upload/play

---

## 🚧 Risques & Parades

| Risque | Impact | Mitigation |
|--------|--------|------------|
| Mélodie bruitée | Qualité MIDI | Filtrer notes <80ms, quantification douce |
| Rendu lent | UX | 1280×360@30fps, pas d'effets lourds |
| IAP complexe | Monétisation | Sandbox testing, restore purchases |
| Coût serveur | Budget | Rate limiting, purges, optimiser modèle |
| Latence réseau | UX | Feedback progressif, retry logic |

---

## 🔮 Futures Améliorations (Post-MVP)

- [ ] Practice Mode avec détection fausses notes
- [ ] Bibliothèque de morceaux sauvegardés
- [ ] Partage social
- [ ] Export PDF partition
- [ ] Support iOS
- [ ] Mode multi-instruments
- [ ] Accompagnements jazz/classique personnalisés


