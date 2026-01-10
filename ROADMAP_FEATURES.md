# ROADMAP FEATURES - ShazaPiano

**PHILOSOPHIE :** Système 99% infaillible d'abord, features après.

**OBJECTIFS CORE :**
1. Apprendre à jouer du piano (pédagogie)
2. Se mesurer (compétition, "qui a la plus grosse")
3. Zéro bug, appli fluide

---

## 🎯 PHASE 0 - BASE INFAILLIBLE (EN COURS)

### ✅ DÉJÀ FAIT (11 fixes appliqués, pas encore rebuild)

**FIXES CRITIQUES :**
1. Frequency compensation (sampleRate variable 32-52 kHz)
2. Constant fallLead (pas de jump countdown→running)
3. Layout stability guard (pas de preview flash)
4. Anti-replay 2s guard
5. Rectangle color change (vert quand hit)
6. Coloration sélective intersection (V4 après cascade analysis)
7. Score dialog await (pas de flash écran Play)
8. UX cleanup (texte "Chargement...")

**VALIDATION CASCADE :**
- 4 itérations de debug (V1→V2→V3→V4)
- Géométrie intersection [topY, bottomY] × keyboard zone
- Code 100% générique (toutes notes, toutes octaves)
- MPM pitch detection (PhD-level algo)

**EDGE CASES À TESTER APRÈS REBUILD :**
- [ ] Accords (3+ notes simultanées)
- [ ] Notes rapides (5 notes en 2s)
- [ ] Notes longues (tenues 3+ secondes)
- [ ] Countdown (elapsed négatif, mic actif mais MIDI désactivé)

---

## 📊 PHASE 1 - SCORING & PROGRESSION (APRÈS TESTS)

### **TIMING PRECISION SCORE** (Priorité 1)
```
Formule actuelle :
- Correct/Wrong (binaire)

Formule cible :
- Perfect (±10ms timing, ±10 cents pitch) : 1000 pts
- Great (±50ms, ±25 cents) : 800 pts
- Good (±100ms, ±50 cents) : 500 pts
- OK (±150ms, correct pitch) : 200 pts
- Miss : 0 pts

COMBO SYSTEM :
- 10 notes parfaites = 2x multiplier
- 20 notes = 3x multiplier
- 50 notes = 5x multiplier (LEGENDARY)
- 1 miss = BREAK COMBO

IMPACT :
- Infinite replay value (battre son record)
- Différenciation skill (débutant vs pro)
- Viral potential ("987/1000 sur Fur Elise!")
```

**Implementation :**
- Fichier : `practice_page.dart`
- Variables : `timingErrorMs`, `centsError`, `comboCount`
- UI : Post-game screen avec breakdown
- Stockage : SQLite (scores locaux)

**Estimation : 2 jours dev**

---

### **ANALYTICS DASHBOARD** (Priorité 2)
```
Post-game screen amélioré :

TIMING GRAPH :
- Axe X : Notes (1-100)
- Axe Y : -200ms (early) → +200ms (late)
- Ligne rouge = tes hits
- Zone verte = perfect timing window

PITCH ACCURACY :
- Heatmap : "Tu es 8 cents trop haut sur notes aiguës"
- Pattern : "Tu ralentis de 15% en fin de morceau"

IMPROVEMENT TRACKER :
- Graph progression : "Score moyen +12% cette semaine"
- Weakness detection : "Travaille les transitions Do→Ré"

IMPACT :
- Proof de progression (motivation)
- Personalized learning (AI-driven potentiel)
- Shareable (social media flex)
```

**Implementation :**
- Package : `fl_chart` (Flutter charts)
- Stockage : SQLite (historique 30 jours)
- Export : PNG image (share sur social)

**Estimation : 3 jours dev**

---

## 🏆 PHASE 2 - COMPÉTITION (APRÈS SCORING STABLE)

### **LEADERBOARD LOCAL** (Priorité 1)
```
Database SQLite :
- Table : scores (songId, score, timing, accuracy, date)
- Index : songId + score DESC
- Query : Top 10 par chanson

UI :
- Liste simple (rank, score, date)
- Indicateur personnel (ta position)
- Badge "Personal Best"

IMPACT :
- Zéro backend (pas de serveur)
- Motivation long-term (battre ses records)
- Foundation pour leaderboard global
```

**Implementation :**
- Package : `sqflite`
- Fichier : `lib/data/local/score_database.dart`
- UI : `lib/presentation/pages/leaderboard_local.dart`

**Estimation : 1 jour dev**

---

### **LEADERBOARD GLOBAL** (Priorité 2)
```
Backend Firebase :
- Firestore : collection "leaderboards"
- Document : {songId, userId, score, timestamp}
- Security rules : read all, write authenticated

UI :
- Top 100 mondial par chanson
- Filtre : Daily / Weekly / All-Time
- Badge "World Record Holder" (si #1)

IMPACT :
- Compétition globale (qui a la plus grosse)
- Network effect (tes amis jouent → tu rejoins)
- Retention 10x supérieure

ANTI-CHEAT :
- Server-side validation (impossible score = banned)
- Replay required (ghost upload pour vérification)
- Report system (signaler cheaters)
```

**Implementation :**
- Backend : Firebase Firestore + Cloud Functions
- Auth : Firebase Auth (déjà présent)
- Sync : Real-time listeners

**Estimation : 3 jours dev + 1 jour anti-cheat**

---

### **GHOST REPLAY SYSTEM** (Priorité 3)
```
Fonctionnalité :
- Enregistrer ta performance (notes + timing)
- Rejouer avec TON ghost à battre
- Télécharger ghost des TOP 10 mondiaux
- Mode "Race vs Ghost" (2 curseurs côte à côte)

UI :
- Ta note : Vert
- Ghost note : Bleu transparent
- Affichage écart temps réel : "+0.15s" / "-0.08s"

IMPACT :
- Apprendre des meilleurs (copycat leur timing)
- Motivation ("J'étais 0.2s derrière le #1!")
- Zero multiplayer infra (replays async)

STOCKAGE :
- Format : JSON [{timestamp, pitch, duration}]
- Compression : gzip (100 notes ≈ 1KB)
- Firebase Storage : ghost files
```

**Implementation :**
- Record : Buffer notes pendant practice
- Playback : Overlay painter (ghost notes)
- Download : Firebase Storage SDK

**Estimation : 4 jours dev**

---

## 🎨 PHASE 3 - COSMÉTIQUES (APRÈS COMPÉTITION STABLE)

### **NOTE EFFECTS** (Simple mais impactant)
```
Effet "Combustion" :
- Note en feu pendant qu'elle traverse keyboard
- Particles fire trail (10-20 particles)
- Son "whoosh" subtil (si audio activé)
- Unlock : 10 perfect notes d'affilée

Effet "Lightning Strike" :
- Éclair frappe la note à l'impact
- Flash blanc 100ms
- Son "crack" électrique
- Unlock : 50 combo

Effet "Explosion" :
- Particules colorées explosent sur perfect
- Effet confetti 500ms
- Son "pop" satisfaisant
- Unlock : 100% perfect song

IMPACT :
- Visual satisfaction (dopamine hit)
- Reward feeling (tu progresses → unlock)
- Différenciation visuelle (flex)
```

**Implementation :**
- Package : `flutter_particle_system` ou custom
- Trigger : Condition `isTarget && perfectStreak >= X`
- Performance : Max 50 particles 60 FPS

**Estimation : 2 jours dev par effet**

---

### **KEYBOARD SKINS** (Monétisation potentielle)
```
Skins simples :
- Neon glow (outline coloré)
- Rainbow wave (gradient animé)
- Minimalist (noir/blanc)
- Galaxy (étoiles background)

Unlock :
- Gratuit : 3 skins de base
- Premium : 1 skin exclusif par saison
- Achievement : "Play 100 songs" = unlock skin rare

MONÉTISATION (Phase 4) :
- Bundles $2-5
- Rotation daily (scarcity)
- Collabs (si app populaire)
```

**Implementation :**
- Asset : PNG overlays (keyboard background)
- Storage : SharedPreferences (unlocked skins)
- UI : Gallery selection screen

**Estimation : 1 jour dev + assets**

---

## 🎮 PHASE 4 - CHALLENGE MODES (APRÈS BASE SOLIDE)

### **SPEEDRUN MODE**
```
Règle :
- Joue 10 chansons le + vite possible
- Timer global + score total
- Leaderboard temps + précision

Scoring :
- Time : 0-500 pts (plus rapide = plus de points)
- Accuracy : 0-500 pts (moyenne des 10 chansons)
- Total : 0-1000 pts

IMPACT :
- Variété gameplay (pas juste "play song repeat")
- High skill ceiling (optimisation routes)
- Esport potential (tournois)
```

---

### **ENDURANCE MODE**
```
Règle :
- Combien de chansons sans erreur ?
- 1 miss = game over
- Record mondial affiché

Progression :
- 5 chansons = Bronze badge
- 10 chansons = Silver badge
- 20 chansons = Gold badge
- 50 chansons = Legendary badge

IMPACT :
- Mental challenge (concentration)
- Bragging rights ("J'ai fait 47 chansons")
- Content creators (YouTube "World Record Attempt")
```

---

### **PERFECT RUN MODE**
```
Règle :
- Mode hardcore : 100% perfect notes required
- 1 "great" ou "good" = fail
- Badge ultra-rare : "Perfectionnist"

Unlock :
- Exclusive skin "Platinum Piano"
- Title "Perfectionnist" (profile badge)
- Ghost replay featured sur homepage

IMPACT :
- Ultimate challenge (0.1% players succeed)
- Community prestige
- Viral moments ("I did it!")
```

---

## 💰 PHASE 5 - MONÉTISATION (QUAND 10k+ USERS)

### **BATTLE PASS** (Modèle F2P moderne)
```
Système :
- Free track : 30 tiers (rewards basiques)
- Premium track : $10/saison (rewards exclusifs)
- Progression : 1 tier = 3 songs played

Rewards :
- Coins virtuels
- Skins exclusifs
- XP boost (progression plus rapide)
- Ghost replay des pros (apprendre)

Time-limited :
- 3 mois par saison
- FOMO effect ("Season 1 skins never come back")

REVENUE POTENTIAL :
- 100k users × 20% conversion × $10 = $200k/saison
- 4 saisons/an = $800k revenue
```

---

### **PREMIUM SUBSCRIPTION** ($10/mois)
```
Benefits :
- Unlock all songs (pas de grind)
- Ad-free experience
- Priority leaderboard position (badge)
- Early access à nouvelles features
- Analytics avancées (heatmaps détaillés)

Justification prix :
- Simply Piano = $20/mois (référence marché)
- Valeur = cours piano ($40-80/mois économisés)
- Cancel anytime (pas de lock-in)

REVENUE POTENTIAL :
- 100k users × 10% conversion × $10 = $100k/mois
- Année 1 : $1.2M revenue récurrent
```

---

## 🔧 PHASE 6 - OUTILS AVANCÉS (LONG-TERM)

### **PRACTICE TOOLS**
```
Metronome intégré :
- BPM ajustable (40-240)
- Visual + audio click
- Auto-sync avec chanson

Loop mode :
- Sélectionner section (mesures 10-20)
- Répéter jusqu'à 100% perfect
- Speed training (50%, 75%, 100%, 125%)

Slow-motion :
- Jouer chanson à 50% vitesse
- Notes tombent plus lentement
- Apprendre passages difficiles

IMPACT :
- Pédagogie (vraiment apprendre, pas juste jouer)
- Rétention (utilisateurs progressent = restent)
```

---

### **SOCIAL FEATURES**
```
Friends system :
- Add friends via code/email
- See leurs scores en temps réel
- Challenge direct (async PvP)

Activity feed :
- "John a battu ton record sur Fur Elise!"
- "Sarah a unlock le skin Legendary"
- "Tom joue maintenant (spectate)"

Clan system :
- Teams de 5-20 joueurs
- Clan leaderboard (score total)
- Clan wars (events hebdo)

IMPACT :
- Network effect viral (invite amis)
- Retention sociale (jouer ensemble)
- Community building
```

---

## 📊 MÉTRIQUES SUCCÈS (KPIs)

### **PHASE 0-1 (MVP Stable)**
- ✅ 0 crash sur 100 sessions
- ✅ 95%+ notes détectées correctement
- ✅ 60 FPS constant (visual smoothness)
- ✅ Latency < 150ms (micro → visual)

### **PHASE 2-3 (Growth)**
- 🎯 10k users actifs/mois
- 🎯 10% retention day 7
- 🎯 30% retention day 30
- 🎯 Average 20 chansons jouées/user/semaine

### **PHASE 4-5 (Revenue)**
- 🎯 $10k MRR (Monthly Recurring Revenue)
- 🎯 20% conversion free → premium
- 🎯 Average $20/user/an (LTV)
- 🎯 100k users = $2M revenue/an

### **PHASE 6 (Scale)**
- 🎯 100k+ users
- 🎯 $100k+ MRR
- 🎯 50k+ active learners/mois
- 🎯 Top 10 app éducation (App Store)

---

## 🚫 CE QU'ON NE FAIT PAS (Scope limité)

**HORS SCOPE (Pour l'instant) :**
- ❌ Synthèse audio (MIDI → son piano) : Trop lourd, pas le core
- ❌ Video tutorials : Pas l'app principale, YouTube suffit
- ❌ Live multiplayer (PvP temps réel) : Backend complexe, async suffit
- ❌ AR/VR piano : Gimmick, pas utile pour apprendre
- ❌ AI composition : Hors scope, focus sur apprendre

**POURQUOI :**
- Focus = infaillible + fun + compétition
- Scope creep = mort des startups
- Ship fast, iterate, écouter users

---

## 🎯 PROCHAINE ÉTAPE IMMÉDIATE

**MAINTENANT :**
1. ✅ Rebuild avec 11 fixes
2. ✅ Test exhaustif (accords, rapide, tenu)
3. ✅ Validation 0 bug critique
4. → **PHASE 0 TERMINÉE**

**APRÈS (Ordre prioritaire) :**
1. Scoring 0-1000 + Combo (2 jours)
2. Leaderboard local (1 jour)
3. Analytics dashboard (3 jours)
4. Tests utilisateurs (1 semaine)
5. → **PHASE 1 TERMINÉE**

**PUIS :**
- Décision : Leaderboard global ou cosmétiques ?
- Dépend feedback users (qu'est-ce qu'ils veulent ?)

---

## 💎 PHILOSOPHIE FINALE

> "Système 99% infaillible qui sera OK pour tous les types de niveau. Le but de l'app reste : 1) Apprendre à jouer du piano, 2) Se mesurer qui a la plus grosse."

**Principes :**
- ✅ Qualité > Quantité
- ✅ Core solide > Features flashy
- ✅ User experience > Monétisation
- ✅ Ship fast > Perfect code

**Success = Quand :**
- User joue 1h sans crash
- User progresse (mesurable)
- User invite ses amis
- User paie (valeur reconnue)

---

**Document créé le : 2026-01-10**  
**Dernière mise à jour : Après session debugging 11 fixes**  
**Status : PHASE 0 en cours (rebuild pending)**
