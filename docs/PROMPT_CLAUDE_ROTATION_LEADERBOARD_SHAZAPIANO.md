# MISSION : Rotation hebdomadaire de 3 musiques gratuites + Leaderboard global + Achat par musique

## Contexte

Tu travailles sur **ShazaPiano** (github.com/sky1241/shazam-piano), une app Flutter qui détecte ce que l'utilisateur joue au piano, génère 4 niveaux de difficulté en vidéo, et propose un mode Practice temps réel.

**Monétisation actuelle :**
- AdMob : banner + interstitial (déjà implémenté dans `app/lib/ads/admob_ads.dart`)
- IAP : achat unique 1$ non-consumable `piano_all_levels_1usd` qui débloque TOUT (dans `app/lib/presentation/state/iap_provider.dart`)
- Paywall modal qui propose l'achat (dans `app/lib/presentation/widgets/paywall_modal.dart`)

**Scoring actuel :**
- Engine complet dans `app/lib/core/practice/scoring/practice_scoring_engine.dart`
- Grades : perfect (≤40ms), good (≤100ms), ok (≤450ms), miss
- Combo multiplier : +0.1x par 10 consécutifs, cap 2.0x
- Sustain factor : pénalise durée incorrecte (clamp 0.7-1.0)
- Points = base * sustain * combo

**Backend actuel :**
- FastAPI dans `backend/app.py`
- Endpoints : `/jobs` (create), `/jobs/{id}/start`, `/jobs/{id}/progress`, `/practice/session` (save to Firestore), `/practice/notes/{id}/{level}`
- Firebase auth + Firestore
- In-memory job store

## Nouveau modèle business

```
GRATUIT (avec pub) :
  → 3 musiques en rotation chaque semaine (tirées d'un pool de 10-20)
  → Preview 12 secondes des 4 niveaux
  → Mode Practice sur ces 3 musiques
  → Leaderboard global sur ces 3 musiques
  → Pubs (banner + interstitial)

PAYANT (1€ par musique) :
  → L'utilisateur enregistre son propre piano → 1€ pour débloquer les 4 vidéos complètes
  → Pas de pub sur le contenu payant
  → Practice mode illimité sur ses musiques achetées
```

## Ce que tu dois implémenter

### 1. POOL DE MUSIQUES ET ROTATION HEBDOMADAIRE

#### 1A. Structure des données musiques

**Fichier à créer :** `app/lib/core/music/weekly_rotation.dart`

```dart
class FreeTrack {
  final String id;                    // ex: "fur_elise_easy"
  final String title;                 // ex: "Für Elise"
  final String composer;              // ex: "Beethoven"
  final String difficulty;            // "easy", "medium", "hard"
  final String midiAssetPath;         // chemin vers le MIDI dans assets
  final String coverImagePath;        // pochette/image
  final int durationSec;              // durée approximative
  final Map<int, String> videoUrls;   // URLs des 4 niveaux (pré-générés)
  final Map<int, String> previewUrls; // URLs des previews 12s
}

class WeeklyRotation {
  final int weekNumber;               // numéro de semaine ISO
  final int year;
  final List<FreeTrack> tracks;       // exactement 3
  final DateTime startsAt;
  final DateTime endsAt;
}
```

#### 1B. Logique de rotation

**Fichier à créer :** `app/lib/core/music/rotation_service.dart`

La rotation doit être :
- **Déterministe** : basée sur le numéro de semaine ISO, pas sur un appel serveur
- **Reproductible** : le même algorithme sur tous les devices donne les mêmes 3 musiques
- **Sans doublon** : les 3 musiques de la semaine sont toujours différentes

```dart
class RotationService {
  static const List<FreeTrack> _pool = [...]; // 10-20 musiques hardcodées

  /// Retourne les 3 musiques de la semaine courante
  static WeeklyRotation getCurrentRotation() {
    final now = DateTime.now();
    final weekNumber = _isoWeekNumber(now);
    final year = now.year;

    // Algorithme déterministe :
    // seed = year * 100 + weekNumber
    // shuffle le pool avec ce seed
    // prendre les 3 premiers
    final seed = year * 100 + weekNumber;
    final rng = Random(seed);
    final shuffled = List<FreeTrack>.from(_pool)..shuffle(rng);
    final selected = shuffled.take(3).toList();

    return WeeklyRotation(
      weekNumber: weekNumber,
      year: year,
      tracks: selected,
      startsAt: _mondayOfWeek(weekNumber, year),
      endsAt: _mondayOfWeek(weekNumber, year).add(Duration(days: 7)),
    );
  }

  /// Temps restant avant la prochaine rotation
  static Duration timeUntilNextRotation() { ... }
}
```

#### 1C. Sourcing des musiques

Les musiques doivent être **libres de droits** (domaine public ou Creative Commons).

Sources recommandées pour les MIDI :
- Classiques : Für Elise, Clair de Lune, Gymnopédie n°1, Prélude en Do de Bach, Comptine d'un autre été, River Flows in You, etc.
- Les MIDI doivent être pré-traités par le backend (arrangement 4 niveaux + rendu vidéo) et les vidéos hébergées (Firebase Storage ou CDN)

**Fichier à créer :** `app/lib/core/music/free_tracks_catalog.dart`
```dart
/// Catalogue hardcodé des musiques du pool
/// Les vidéos sont pré-générées et hébergées sur Firebase Storage
class FreeTracksCatalog {
  static const List<FreeTrack> allTracks = [
    FreeTrack(
      id: 'fur_elise',
      title: 'Für Elise',
      composer: 'Beethoven',
      difficulty: 'medium',
      // ... URLs Firebase Storage pour les vidéos pré-générées
    ),
    // ... 9-19 autres musiques
  ];
}
```

**IMPORTANT :** Les vidéos des musiques gratuites sont **pré-générées** et hébergées. Pas de traitement backend à chaque fois. Le backend ne traite que les musiques enregistrées par l'utilisateur (payantes à 1€).

### 2. LEADERBOARD GLOBAL

#### 2A. Structure Firestore

```
Collection: leaderboards
  Document: {trackId}_{weekNumber}_{year}  (ex: "fur_elise_6_2026")
    Collection: scores
      Document: {userId}
        - displayName: "Ludo"
        - score: 45200
        - maxCombo: 47
        - perfectCount: 89
        - accuracy: 0.94
        - timestamp: Timestamp
        - deviceModel: "Pixel 7"
```

#### 2B. Backend endpoints à ajouter

**Fichier à modifier :** `backend/app.py`

```python
# Ajouter ces endpoints :

@app.post("/leaderboard/{track_id}/submit")
async def submit_score(
    track_id: str,
    score: int,
    max_combo: int,
    perfect_count: int,
    accuracy: float,
    user = Depends(get_current_user)
):
    """Soumet un score au leaderboard de la semaine courante."""
    week = datetime.now().isocalendar()[1]
    year = datetime.now().year
    doc_id = f"{track_id}_{week}_{year}"

    # Écrire dans Firestore
    db.collection("leaderboards").document(doc_id) \
      .collection("scores").document(user["uid"]).set({
        "displayName": user.get("name", "Anonymous"),
        "score": score,
        "maxCombo": max_combo,
        "perfectCount": perfect_count,
        "accuracy": accuracy,
        "timestamp": firestore.SERVER_TIMESTAMP,
    })
    return {"status": "ok"}

@app.get("/leaderboard/{track_id}/top")
async def get_leaderboard(track_id: str, limit: int = 50):
    """Retourne le top N de la semaine courante."""
    week = datetime.now().isocalendar()[1]
    year = datetime.now().year
    doc_id = f"{track_id}_{week}_{year}"

    scores = db.collection("leaderboards").document(doc_id) \
      .collection("scores") \
      .order_by("score", direction=firestore.Query.DESCENDING) \
      .limit(limit) \
      .get()

    return {"scores": [s.to_dict() | {"uid": s.id} for s in scores]}

@app.get("/leaderboard/{track_id}/rank/{user_id}")
async def get_user_rank(track_id: str, user_id: str):
    """Retourne le rang de l'utilisateur."""
    # ... compter les scores supérieurs
```

#### 2C. Flutter - Provider + UI

**Fichier à créer :** `app/lib/presentation/state/leaderboard_provider.dart`

```dart
class LeaderboardEntry {
  final String displayName;
  final int score;
  final int maxCombo;
  final int perfectCount;
  final double accuracy;
  final int rank;
}

class LeaderboardNotifier extends StateNotifier<LeaderboardState> {
  /// Soumettre le score en fin de Practice
  Future<void> submitScore(String trackId, PracticeScoringEngine scoring);

  /// Charger le top 50
  Future<void> loadLeaderboard(String trackId);

  /// Charger le rang de l'utilisateur
  Future<void> loadUserRank(String trackId);
}
```

**Fichier à créer :** `app/lib/presentation/pages/leaderboard/leaderboard_page.dart`

UI du leaderboard :
- Header : nom de la musique + timer "Rotation dans X jours Xh"
- Liste scrollable : rang, avatar/initiale, pseudo, score, combo, accuracy
- Highlight de la ligne du joueur
- Bouton "Rejouer" pour améliorer son score
- Pull-to-refresh

### 3. MODIFICATION DU SYSTÈME D'ACHAT

#### 3A. Nouveau modèle IAP

Le modèle actuel (`piano_all_levels_1usd` non-consumable qui débloque tout) doit être modifié.

**Nouveau modèle :** Chaque musique enregistrée par l'utilisateur coûte 1€ pour débloquer les 4 vidéos complètes.

**Option technique :** Utiliser un **consumable** IAP qui représente 1 crédit de musique.

```dart
// Dans app_constants.dart, remplacer :
static const String iapProductId = 'piano_all_levels_1usd';
// Par :
static const String iapCreditProductId = 'shazapiano_credit_1eur';
static const String iapCreditPrice = '1,00 €';
```

**ATTENTION :** Les musiques gratuites (rotation) n'ont PAS besoin d'achat. L'achat ne concerne que les musiques ENREGISTRÉES par l'utilisateur.

#### 3B. Modifier le flow

```
MUSIQUE GRATUITE (rotation) :
  HomePage → Sélectionner une musique gratuite → Practice + Leaderboard (gratuit, avec pub)

MUSIQUE PERSO (enregistrée) :
  HomePage → Enregistrer → Preview 12s gratuit (avec pub)
           → Payer 1€ → Vidéos complètes + Practice (sans pub)
```

#### 3C. Modifier iap_provider.dart

```dart
class IAPNotifier extends StateNotifier<IAPState> {
  // Garder l'ancien système pour les users qui ont déjà acheté le lifetime
  // (backward compatibility : si isUnlocked == true, tout est gratuit)

  // Ajouter :
  Future<void> purchaseCredit() async {
    // buyConsumable au lieu de buyNonConsumable
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  // Tracker les crédits disponibles
  int get availableCredits => _credits;

  // Consommer un crédit pour une musique
  Future<bool> useCredit(String jobId) async {
    if (state.isUnlocked) return true; // lifetime users
    if (_credits <= 0) return false;
    _credits--;
    _saveCreditCount();
    _saveUnlockedJob(jobId);
    return true;
  }

  // Vérifier si un job est débloqué
  bool isJobUnlocked(String jobId) {
    return state.isUnlocked || _unlockedJobs.contains(jobId);
  }
}
```

#### 3D. Modifier paywall_modal.dart

Adapter le texte :
```
Ancien : "Tout débloquer pour 1$"
Nouveau : "Débloquer cette musique - 1,00 €"
  ✓ 4 niveaux de difficulté
  ✓ Vidéos complètes HD
  ✓ Mode Practice interactif
  ✓ Sans publicité
```

### 4. INTÉGRATION DANS LA HOMEPAGE

#### 4A. Modifier home_page.dart

Ajouter une section au-dessus ou en dessous du bouton d'enregistrement :

```
┌─────────────────────────────────┐
│  🎵 Musiques de la semaine      │
│  Rotation dans 3j 14h           │
│                                 │
│  ┌─────┐ ┌─────┐ ┌─────┐      │
│  │ Für │ │Clair│ │Gymno│      │
│  │Elise│ │de   │ │pédie│      │
│  │     │ │Lune │ │ n°1 │      │
│  │ ▶️  │ │ ▶️  │ │ ▶️  │      │
│  │🏆 #4│ │🏆 — │ │🏆 #1│      │
│  └─────┘ └─────┘ └─────┘      │
│                                 │
│      [ 🎙️ ENREGISTRER ]        │
│   (votre propre musique - 1€)   │
└─────────────────────────────────┘
```

Chaque carte de musique gratuite affiche :
- Titre + compositeur
- Bouton Play (preview)
- Rang du joueur au leaderboard (ou "—" si pas encore joué)
- Tap → ouvre la page détail avec Practice + Leaderboard

### 5. PAGE DÉTAIL MUSIQUE GRATUITE

**Fichier à créer :** `app/lib/presentation/pages/free_track/free_track_page.dart`

```
┌─────────────────────────────────┐
│ ← Für Elise - Beethoven         │
│                                 │
│ ┌─────────────────────────────┐ │
│ │    [Vidéo Preview 12s]      │ │
│ │    Niveau: [1] [2] [3] [4]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │  🏆 Leaderboard             │ │
│ │  #1  Pierre    52400  x48   │ │
│ │  #2  Marie     48100  x42   │ │
│ │  #3  Vous      45200  x38   │ │
│ │  ...                        │ │
│ │  [Voir tout]                │ │
│ └─────────────────────────────┘ │
│                                 │
│    [ 🎹 PRACTICE MODE ]        │
│                                 │
│  ⏱️ Rotation dans 3j 14h       │
│  (Banner pub en bas)            │
└─────────────────────────────────┘
```

### 6. FLOW PRACTICE → SCORE → LEADERBOARD

En fin de session Practice sur une musique gratuite :

```
Practice terminé
    ↓
Écran résultat :
  Score: 45,200
  Perfect: 89 | Good: 23 | OK: 5 | Miss: 3
  Max Combo: 38x
  Accuracy: 94%
  [Nouveau record personnel !]
    ↓
Si connecté (Firebase Auth) :
  → Auto-submit au leaderboard
  → Afficher "Vous êtes #3 cette semaine !"
Si pas connecté :
  → "Connectez-vous pour sauvegarder votre score"
  → Bouton Google Sign-In
    ↓
[Rejouer] [Leaderboard] [Accueil]
```

### 7. CONNEXION AVEC LE CODE EXISTANT

#### Fichiers à MODIFIER (pas remplacer) :

1. **`app/lib/presentation/pages/home/home_page.dart`**
   - Ajouter la section "Musiques de la semaine" avec les 3 cartes
   - Garder le bouton d'enregistrement en dessous
   - Modifier le texte sous le bouton : "Enregistrez votre piano - 1€"

2. **`app/lib/core/constants/app_constants.dart`**
   - Ajouter `iapCreditProductId` et `iapCreditPrice`
   - Garder `iapProductId` pour backward compatibility

3. **`app/lib/presentation/state/iap_provider.dart`**
   - Ajouter `purchaseCredit()`, `useCredit()`, `isJobUnlocked()`
   - Garder `purchase()` pour les users legacy
   - Ajouter tracking des crédits (SharedPreferences)

4. **`app/lib/presentation/widgets/paywall_modal.dart`**
   - Adapter le texte et le prix
   - Détecter si c'est pour une musique perso (1€) ou si l'user a le lifetime

5. **`app/lib/presentation/pages/previews/previews_page.dart`**
   - Utiliser `isJobUnlocked(jobId)` au lieu de `state.isUnlocked`

6. **`backend/app.py`**
   - Ajouter les 3 endpoints leaderboard
   - Ajouter un endpoint `/rotation/current` (optionnel, pour backup si le calcul client diverge)

#### Fichiers à CRÉER :

```
app/lib/core/music/
├── free_tracks_catalog.dart          ← Catalogue des 10-20 musiques
├── weekly_rotation.dart              ← Modèles WeeklyRotation + FreeTrack
└── rotation_service.dart             ← Logique de rotation déterministe

app/lib/presentation/pages/
├── free_track/
│   └── free_track_page.dart          ← Page détail musique gratuite
└── leaderboard/
    └── leaderboard_page.dart         ← Page leaderboard complète

app/lib/presentation/state/
└── leaderboard_provider.dart         ← State management leaderboard

app/lib/presentation/widgets/
└── weekly_tracks_section.dart        ← Widget section 3 musiques homepage
```

## Règles importantes

1. **Backward compatibility IAP** — Les users qui ont déjà acheté `piano_all_levels_1usd` (lifetime) gardent tout débloqué. Ne JAMAIS casser leur achat.

2. **Les musiques gratuites sont TOUJOURS gratuites** — Pas de paywall sur la rotation. La pub suffit. L'achat ne concerne que les musiques enregistrées par l'utilisateur.

3. **Le leaderboard reset chaque semaine** — Quand la rotation change, nouveau leaderboard. Les anciens scores restent dans Firestore mais ne sont plus affichés.

4. **Firebase Auth obligatoire pour le leaderboard** — Mais PAS pour jouer. L'utilisateur peut jouer en mode Practice sans compte, mais pour soumettre son score il doit se connecter.

5. **Les vidéos des musiques gratuites sont pré-générées** — Stockées sur Firebase Storage. Le backend ne les génère PAS à la volée. Seules les musiques perso passent par le pipeline de génération.

6. **Anti-triche basique** — Le score est calculé côté client (engine existant) mais on peut ajouter un hash de vérification (score + combo + timestamp + secret) pour rendre la triche un peu plus difficile. Pas besoin d'un système anti-triche parfait pour le MVP.

7. **Pub uniquement sur le contenu gratuit** — Les musiques payantes (enregistrées) = pas de pub. Ça incentive l'achat.

## Fichiers à lire en priorité avant de coder

1. `app/lib/presentation/pages/home/home_page.dart` — comprendre la HomePage actuelle (670 lignes)
2. `app/lib/presentation/state/iap_provider.dart` — comprendre le système IAP (191 lignes)
3. `app/lib/presentation/widgets/paywall_modal.dart` — comprendre le paywall (227 lignes)
4. `app/lib/core/practice/scoring/practice_scoring_engine.dart` — comprendre le scoring (196 lignes)
5. `app/lib/presentation/state/library_provider.dart` — comprendre la library (434 lignes)
6. `app/lib/presentation/pages/previews/previews_page.dart` — comprendre les previews (498 lignes)
7. `app/lib/core/constants/app_constants.dart` — constantes et config
8. `backend/app.py` — backend complet (945 lignes)
9. `app/lib/ads/admob_ads.dart` — intégration pub actuelle
10. `app/lib/core/config/app_config.dart` — config backend URLs

## Sources MIDI libres de droits recommandées

Pour constituer le pool de 10-20 musiques, utiliser des morceaux **domaine public** :
- Für Elise (Beethoven)
- Clair de Lune (Debussy)
- Gymnopédie n°1 (Satie)
- Prélude en Do majeur BWV 846 (Bach)
- Sonate au Clair de Lune, 1er mouvement (Beethoven)
- Arabesque n°1 (Debussy)
- Nocturne Op.9 No.2 (Chopin)
- Rêverie (Debussy)
- Valse en La mineur (Chopin)
- Gnossienne n°1 (Satie)
- Prélude en Mi mineur Op.28 No.4 (Chopin)
- Invention n°1 en Do majeur (Bach)
- Sonate Facile K.545, 1er mouvement (Mozart)
- Menuet en Sol majeur (Bach/Petzold)
- Bagatelle en La mineur WoO 59 (Beethoven) — c'est Für Elise, doublon
- La Lettre à Élise simplifiée
- Canon en Ré (Pachelbel) — version piano

Tous ces morceaux sont dans le domaine public (compositeurs morts depuis >70 ans). Les FICHIERS MIDI eux-mêmes doivent être soit créés, soit sourcés depuis des sites CC0 (ex: musescore.com/openscore, kunstderfuge.com, mutopiaproject.org).
