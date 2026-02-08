# Guide d'intégration — Rotation + Leaderboard + Vote + IAP Credits

## Fichiers créés (prêts, NON connectés)

### Core Logic
| Fichier | Rôle |
|---------|------|
| `app/lib/core/music/models.dart` | Modèles : FreeTrack, WeeklyRotation, LeaderboardEntry, VoteCandidate |
| `app/lib/core/music/free_tracks_catalog.dart` | Catalogue de 15 musiques libres de droits |
| `app/lib/core/music/rotation_service.dart` | Rotation hebdomadaire déterministe (5 musiques/semaine) |

### State Management (Riverpod)
| Fichier | Rôle |
|---------|------|
| `app/lib/presentation/state/leaderboard_provider.dart` | Provider leaderboard (load, submit, rank) |
| `app/lib/presentation/state/vote_provider.dart` | Provider vote communautaire (load, vote, unvote) |
| `app/lib/presentation/state/iap_credit_provider.dart` | Provider IAP crédits consumable + backward compat |

### Pages UI
| Fichier | Rôle |
|---------|------|
| `app/lib/presentation/pages/leaderboard/leaderboard_page.dart` | Page leaderboard complète (podium, liste, user rank) |
| `app/lib/presentation/pages/free_track/free_track_page.dart` | Page détail musique gratuite (preview, leaderboard, practice) |
| `app/lib/presentation/pages/vote/vote_page.dart` | Page de vote communautaire |

### Widgets
| Fichier | Rôle |
|---------|------|
| `app/lib/presentation/widgets/weekly/weekly_tracks_section.dart` | Section 5 musiques de la semaine (pour HomePage) |

### Backend
| Fichier | Rôle |
|---------|------|
| `backend/leaderboard_routes.py` | Routes FastAPI : leaderboard, vote, rotation |

---

## Étapes d'intégration (à faire)

### 1. Ajouter WeeklyTracksSection dans HomePage

Dans `app/lib/presentation/pages/home/home_page.dart`, ajouter le widget
au-dessus du bouton d'enregistrement :

```dart
import '../../widgets/weekly/weekly_tracks_section.dart';
import '../../pages/free_track/free_track_page.dart';

// Dans le body du Scaffold, ajouter :
WeeklyTracksSection(
  onTrackTap: (track) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FreeTrackPage(track: track),
    ));
  },
),
```

### 2. Connecter le leaderboard au scoring existant

En fin de session Practice sur une musique gratuite, appeler :

```dart
// Dans le controller/page de practice, après la fin de session :
ref.read(leaderboardProvider.notifier).submitScore(
  trackId: currentTrackId,
  uid: firebaseUser.uid,
  displayName: firebaseUser.displayName ?? 'Anonymous',
  score: scoringEngine.totalScore,
  maxCombo: scoringEngine.maxCombo,
  perfectCount: scoringEngine.perfectCount,
  goodCount: scoringEngine.goodCount,
  okCount: scoringEngine.okCount,
  missCount: scoringEngine.missCount,
  accuracy: scoringEngine.accuracy,
);
```

### 3. Remplacer l'IAP dans previews_page.dart

Dans `app/lib/presentation/pages/previews/previews_page.dart` :

```dart
// Ancien : vérifier state.isUnlocked (lifetime)
// Nouveau : vérifier les deux systèmes
final legacyIap = ref.watch(iapProvider);
final creditIap = ref.watch(iapCreditProvider);

final isUnlocked = legacyIap.isUnlocked || creditIap.isJobUnlocked(jobId);
```

### 4. Connecter Firestore dans les providers

Dans `leaderboard_provider.dart` et `vote_provider.dart`, remplacer les
blocs `// TODO: Remplacer par l'appel Firestore réel` par les vrais appels.

Import nécessaire :
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
```

### 5. Brancher les routes backend

Dans `backend/app.py`, ajouter :

```python
from leaderboard_routes import leaderboard_router, vote_router, rotation_router

app.include_router(leaderboard_router)
app.include_router(vote_router)
app.include_router(rotation_router)
```

### 6. Ajouter les URLs Firebase Storage aux musiques

Dans `free_tracks_catalog.dart`, remplacer les FreeTrack sans URLs par
des FreeTrack avec les vrais liens Firebase Storage des vidéos pré-générées.

### 7. Navigation

Ajouter les routes dans le système de navigation :
- HomePage → FreeTrackPage (tap sur musique gratuite)
- FreeTrackPage → LeaderboardPage (bouton leaderboard)
- FreeTrackPage → PracticePage (bouton practice)
- HomePage → VotePage (bouton vote, optionnel)

---

## Structure Firestore

```
leaderboards/
  {trackId}_{week}_{year}/        ex: "fur_elise_6_2026"
    scores/
      {uid}/
        displayName: string
        score: int
        maxCombo: int
        perfectCount: int
        goodCount: int
        okCount: int
        missCount: int
        accuracy: float
        timestamp: string

votes/
  vote_{week}_{year}/             ex: "vote_6_2026"
    fur_elise: 42                 (nombre de votes par track)
    gymnopedie_1: 38
    ...
    user_votes/
      {uid}/
        fur_elise: true           (tracks votés par cet user)
```

## Dépendances à vérifier dans pubspec.yaml

- `cloud_firestore` (pour le leaderboard et les votes)
- `firebase_auth` (pour l'authentification utilisateur)
- `in_app_purchase` (déjà présent)
- `shared_preferences` (déjà présent)
