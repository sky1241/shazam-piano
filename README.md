# 🎹 ShazaPiano

**Transforme 8 secondes de piano en vidéos pédagogiques animées.**  
Tu enregistres un court extrait → l’app génère automatiquement **4 niveaux de difficulté** avec **clavier animé**, **previews gratuites**, et un **mode pratique** pour t’entraîner en temps réel.

---

## ✨ Ce que fait le projet

- 🎤 **Enregistrement ultra simple** : ~8 secondes suffisent  
- 🎹 **4 niveaux automatiques** : Hyper Facile → Facile → Moyen → Pro  
- 📺 **Previews gratuites** : 12 secondes par niveau  
- 💰 **Déblocage à vie (~1$)** : accès complet aux 4 niveaux  
- 🎵 **Practice Mode** : détection d’erreurs + feedback temps réel  
- 🌙 **UI Shazam-like** : design dark moderne, rapide et clair  

---

## 🧠 Concept (en 1 phrase)

**“Shazam pour piano”** : tu joues → l’app comprend → elle te génère des vidéos d’apprentissage adaptées à ton niveau.

---

# 🧭 Plan d’architecture (clair + complet)

## 1) Vue d’ensemble (pipeline)

1. **App mobile (Flutter)**
   - L’utilisateur enregistre ~8s de piano
   - L’app envoie l’audio au backend
2. **Backend (FastAPI)**
   - Extraction MIDI / notes
   - Génération de **4 arrangements** (L1→L4)
   - Rendu des **vidéos** (clavier animé + overlay)
3. **Retour app**
   - Affichage des **4 previews**
   - Paywall (achat unique)
   - Accès aux vidéos complètes + mode pratique

---

## 2) Monorepo (structure projet)

shazapiano/
├── app/ # Flutter mobile app (UI + logique)
│ ├── lib/
│ │ ├── core/ # Config, constants, thème, services, utils
│ │ ├── data/ # API (Dio/Retrofit), DTO, repos, storage
│ │ ├── domain/ # Entities + interfaces + usecases
│ │ └── presentation/ # Pages UI, widgets, state (Riverpod)
│ └── pubspec.yaml
│
├── backend/ # FastAPI (traitement audio + rendu vidéo)
│ ├── app.py # Endpoints (process, health, cleanup, etc.)
│ ├── config.py # Settings, presets, validation
│ ├── inference.py # Audio → MIDI / extraction notes
│ ├── arranger.py # Génération 4 niveaux (L1-L4)
│ ├── render.py # Génération vidéo (MoviePy/FFmpeg)
│ └── requirements.txt
│
├── packages/ # Packages internes / stubs (si nécessaire)
├── scripts/ # Dev helpers (Windows/Linux)
├── infra/ # Docker / déploiement
└── docs/ # Specs, roadmap, guides


---

## 3) Architecture Frontend (Flutter)

**Organisation en couches (Clean-ish) :**

- **presentation/**
  - UI : pages, widgets, composants
  - state management : Riverpod (state + controllers)
- **domain/**
  - Entities (modèles métier)
  - Interfaces de repositories
  - Use cases (logique métier)
- **data/**
  - API clients (Dio/Retrofit)
  - DTOs + mapping vers Entities
  - Implémentations des repositories
- **core/**
  - Thème / design system
  - Services communs (audio, prefs, logging)
  - Constantes, helpers

**Flux typique :**  
UI → Controller (Riverpod) → UseCase → Repository → API/Local → retour UI

---

## 4) Architecture Backend (FastAPI)

**Modules principaux :**

- `app.py` : routes + orchestration
- `inference.py` : audio → notes/MIDI (BasicPitch + logique d’extraction)
- `arranger.py` : création des 4 niveaux (simplification, transposition, accompagnements)
- `render.py` : rendu vidéo (timeline notes + clavier + export mp4)
- `config.py` : presets, paramètres, validation, chemins fichiers

**Flux typique :**  
Upload audio → extraction MIDI → arrangements (L1..L4) → rendu vidéos → URLs (preview/full) + MIDI

---

## 5) Composants produit (écrans)

- **Home**
  - bouton central d’enregistrement
  - progression L1-L4
- **Previews (2×2)**
  - lecture auto des previews
  - CTA déblocage
- **Player**
  - lecteur vidéo complet + actions
- **Paywall**
  - achat unique + restore
- **Practice Mode**
  - clavier virtuel + feedback temps réel (notes correctes / fausses / timing)

---

## 🎯 Stack technique

### Frontend
- Flutter, Riverpod, go_router  
- Dio/Retrofit (API)  
- record + permission_handler (micro)  
- video_player + chewie  
- in_app_purchase  
- Firebase (Auth/Firestore/Analytics/Crashlytics)  
- AdMob (monétisation)  

### Backend
- FastAPI + Uvicorn  
- BasicPitch (extraction MIDI)  
- PrettyMIDI / mido (MIDI)  
- MoviePy + FFmpeg (vidéos)  
- (Optionnel) Firebase Admin  

---

## 🎹 Les 4 niveaux

| Niveau | Objectif | Public |
|---|---|---|
| L1 - Hyper Facile | Mélodie simplifiée | Débutants complets |
| L2 - Facile | Mélodie + basse | 3–6 mois |
| L3 - Moyen | Ajout accords | 6–12 mois |
| L4 - Pro | Arrangement complet | 1+ an |

---

## 💰 Business model

- ✅ **Previews gratuites** : 16s par niveau  
- ✅ **Achat unique (~1$)** : déblocage complet à vie  
- ✅ **Mises à jour incluses**  

---

## 🔥 Objectif produit

Rendre l’apprentissage du piano **instantané**, **visuel**, et **motivant** :  
tu joues → tu obtiens immédiatement une vidéo guidée adaptée → tu progresses plus vite.

---
