"""
ShazaPiano - Leaderboard & Vote & Rotation API routes

NOT connected to app.py. Ready to be integrated.
Pour intégrer : ajouter `app.include_router(leaderboard_router)` dans app.py.

Requires:
  - firebase_admin already initialized (from app.py)
  - Firestore client available
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

# TODO: Importer depuis app.py quand intégré
# from app import get_current_user, db

leaderboard_router = APIRouter(tags=["leaderboard"])
vote_router = APIRouter(tags=["vote"])
rotation_router = APIRouter(tags=["rotation"])


# ─────────────────────────────────────────────────────────
# Models
# ─────────────────────────────────────────────────────────

class ScoreSubmission(BaseModel):
    """Score soumis par un joueur."""
    score: int
    max_combo: int
    perfect_count: int
    good_count: int = 0
    ok_count: int = 0
    miss_count: int = 0
    accuracy: float  # 0.0 à 1.0

    # Anti-triche basique : hash du score
    # hash = sha256(f"{score}_{max_combo}_{timestamp}_{secret}")
    verification_hash: Optional[str] = None


class LeaderboardEntryResponse(BaseModel):
    """Entrée du leaderboard."""
    uid: str
    display_name: str
    score: int
    max_combo: int
    perfect_count: int
    accuracy: float
    rank: int


class VoteRequest(BaseModel):
    """Vote pour une musique."""
    track_id: str


class RotationResponse(BaseModel):
    """Rotation de la semaine."""
    week_number: int
    year: int
    track_ids: list[str]
    starts_at: str
    ends_at: str


# ─────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────

def _current_iso_week() -> tuple[int, int]:
    """Retourne (week_number, year) ISO."""
    now = datetime.utcnow()
    iso = now.isocalendar()
    return iso[1], iso[0]


def _leaderboard_doc_id(track_id: str) -> str:
    """ID du document Firestore pour le leaderboard de la semaine."""
    week, year = _current_iso_week()
    return f"{track_id}_{week}_{year}"


def _vote_doc_id() -> str:
    """ID du document de vote de la semaine."""
    week, year = _current_iso_week()
    return f"vote_{week}_{year}"


# ─────────────────────────────────────────────────────────
# Leaderboard Routes
# ─────────────────────────────────────────────────────────

@leaderboard_router.post("/leaderboard/{track_id}/submit")
async def submit_score(
    track_id: str,
    submission: ScoreSubmission,
    # user = Depends(get_current_user),  # TODO: uncomment quand intégré
):
    """
    Soumet un score au leaderboard de la semaine courante.

    - Si l'utilisateur a déjà un score, il est remplacé uniquement si supérieur.
    - Anti-triche basique via verification_hash (optionnel).
    """
    # TODO: Validation anti-triche
    # if submission.verification_hash:
    #     expected = hashlib.sha256(
    #         f"{submission.score}_{submission.max_combo}_{ANTI_CHEAT_SECRET}"
    #         .encode()
    #     ).hexdigest()
    #     if submission.verification_hash != expected:
    #         raise HTTPException(400, "Invalid score verification")

    # Validation basique
    if submission.score < 0 or submission.score > 999999:
        raise HTTPException(400, "Score invalide")
    if submission.accuracy < 0 or submission.accuracy > 1:
        raise HTTPException(400, "Accuracy invalide")
    if submission.max_combo < 0:
        raise HTTPException(400, "Combo invalide")

    doc_id = _leaderboard_doc_id(track_id)
    uid = "placeholder_uid"  # TODO: user["uid"]
    display_name = "Anonymous"  # TODO: user.get("name", "Anonymous")

    # TODO: Écriture Firestore
    # score_ref = db.collection("leaderboards").document(doc_id) \
    #     .collection("scores").document(uid)
    #
    # # Vérifier si score existant est supérieur
    # existing = score_ref.get()
    # if existing.exists:
    #     existing_score = existing.to_dict().get("score", 0)
    #     if submission.score <= existing_score:
    #         return {
    #             "status": "kept",
    #             "message": "Score existant est supérieur",
    #             "existing_score": existing_score,
    #         }
    #
    # score_ref.set({
    #     "displayName": display_name,
    #     "score": submission.score,
    #     "maxCombo": submission.max_combo,
    #     "perfectCount": submission.perfect_count,
    #     "goodCount": submission.good_count,
    #     "okCount": submission.ok_count,
    #     "missCount": submission.miss_count,
    #     "accuracy": submission.accuracy,
    #     "timestamp": datetime.utcnow().isoformat(),
    # })

    return {
        "status": "submitted",
        "track_id": track_id,
        "score": submission.score,
    }


@leaderboard_router.get("/leaderboard/{track_id}/top")
async def get_leaderboard(track_id: str, limit: int = 50):
    """
    Retourne le top N de la semaine courante.
    """
    doc_id = _leaderboard_doc_id(track_id)

    # TODO: Lecture Firestore
    # scores_ref = db.collection("leaderboards").document(doc_id) \
    #     .collection("scores") \
    #     .order_by("score", direction=firestore.Query.DESCENDING) \
    #     .limit(limit)
    #
    # scores = scores_ref.get()
    #
    # entries = []
    # for rank, doc in enumerate(scores, 1):
    #     data = doc.to_dict()
    #     entries.append({
    #         "uid": doc.id,
    #         "display_name": data.get("displayName", "Anonymous"),
    #         "score": data.get("score", 0),
    #         "max_combo": data.get("maxCombo", 0),
    #         "perfect_count": data.get("perfectCount", 0),
    #         "accuracy": data.get("accuracy", 0),
    #         "rank": rank,
    #     })

    week, year = _current_iso_week()
    entries: list = []  # Placeholder

    return {
        "track_id": track_id,
        "week": week,
        "year": year,
        "total": len(entries),
        "scores": entries,
    }


@leaderboard_router.get("/leaderboard/{track_id}/rank/{user_id}")
async def get_user_rank(track_id: str, user_id: str):
    """
    Retourne le rang et le score de l'utilisateur.
    """
    doc_id = _leaderboard_doc_id(track_id)

    # TODO: Lecture Firestore
    # user_doc = db.collection("leaderboards").document(doc_id) \
    #     .collection("scores").document(user_id).get()
    #
    # if not user_doc.exists:
    #     raise HTTPException(404, "Pas de score pour cet utilisateur")
    #
    # user_data = user_doc.to_dict()
    # user_score = user_data.get("score", 0)
    #
    # # Compter les scores supérieurs
    # higher = db.collection("leaderboards").document(doc_id) \
    #     .collection("scores") \
    #     .where("score", ">", user_score) \
    #     .count() \
    #     .get()
    # rank = higher[0][0].value + 1

    return {
        "uid": user_id,
        "rank": 0,  # Placeholder
        "score": 0,
    }


# ─────────────────────────────────────────────────────────
# Vote Routes
# ─────────────────────────────────────────────────────────

@vote_router.get("/vote/current")
async def get_current_vote():
    """
    Retourne les candidats du vote de la semaine avec les compteurs.
    """
    doc_id = _vote_doc_id()
    week, year = _current_iso_week()

    # TODO: Lecture Firestore
    # vote_doc = db.collection("votes").document(doc_id).get()
    # if vote_doc.exists:
    #     data = vote_doc.to_dict()
    #     candidates = data.get("candidates", {})
    # else:
    #     candidates = {}

    # Fin du vote = vendredi 18h UTC
    now = datetime.utcnow()
    days_until_friday = (4 - now.weekday()) % 7  # 4 = vendredi
    if days_until_friday == 0 and now.hour >= 18:
        days_until_friday = 7
    voting_ends = now.replace(
        hour=18, minute=0, second=0, microsecond=0
    ) + timedelta(days=days_until_friday)

    return {
        "week": week,
        "year": year,
        "candidates": {},  # Placeholder : {track_id: vote_count}
        "voting_ends_at": voting_ends.isoformat(),
        "max_votes_per_user": 3,
    }


@vote_router.post("/vote/submit")
async def submit_vote(
    vote: VoteRequest,
    # user = Depends(get_current_user),  # TODO: uncomment
):
    """
    Vote pour une musique. Max 3 votes par user par semaine.
    """
    doc_id = _vote_doc_id()
    uid = "placeholder_uid"  # TODO: user["uid"]

    # TODO: Vérifier le nombre de votes de l'user
    # user_votes_ref = db.collection("votes").document(doc_id) \
    #     .collection("user_votes").document(uid)
    # user_votes_doc = user_votes_ref.get()
    # if user_votes_doc.exists:
    #     votes = user_votes_doc.to_dict()
    #     if len(votes) >= 3:
    #         raise HTTPException(400, "Maximum 3 votes par semaine")
    #     if vote.track_id in votes:
    #         raise HTTPException(400, "Déjà voté pour cette musique")

    # TODO: Incrémenter le compteur
    # from google.cloud.firestore_v1 import Increment
    # db.collection("votes").document(doc_id).set(
    #     {vote.track_id: Increment(1)}, merge=True
    # )
    # user_votes_ref.set({vote.track_id: True}, merge=True)

    return {
        "status": "voted",
        "track_id": vote.track_id,
    }


@vote_router.delete("/vote/unvote/{track_id}")
async def unvote(
    track_id: str,
    # user = Depends(get_current_user),  # TODO: uncomment
):
    """
    Annuler un vote.
    """
    doc_id = _vote_doc_id()
    uid = "placeholder_uid"  # TODO: user["uid"]

    # TODO: Décrémenter et supprimer le vote
    # from google.cloud.firestore_v1 import Increment
    # db.collection("votes").document(doc_id).set(
    #     {track_id: Increment(-1)}, merge=True
    # )
    # db.collection("votes").document(doc_id) \
    #     .collection("user_votes").document(uid) \
    #     .update({track_id: firestore.DELETE_FIELD})

    return {"status": "unvoted", "track_id": track_id}


# ─────────────────────────────────────────────────────────
# Rotation Routes
# ─────────────────────────────────────────────────────────

@rotation_router.get("/rotation/current")
async def get_current_rotation():
    """
    Retourne la rotation de la semaine courante.

    Note : la rotation est calculée de manière déterministe
    côté client aussi. Cet endpoint sert de backup/vérification.
    """
    import hashlib

    week, year = _current_iso_week()

    # Pool de musiques (doit correspondre au catalogue Flutter)
    pool = [
        "fur_elise", "menuet_sol", "prelude_em_chopin",
        "invention_1_bach", "sonate_facile_mozart",
        "gymnopedie_1", "gnossienne_1", "reverie_debussy",
        "nocturne_op9_2", "valse_la_min_chopin",
        "prelude_do_bach", "canon_re_pachelbel",
        "clair_de_lune", "arabesque_1", "sonate_clair_lune",
    ]

    # Algorithme déterministe identique au Flutter
    import random
    seed = year * 100 + week
    rng = random.Random(seed)
    shuffled = list(pool)
    rng.shuffle(shuffled)
    selected = shuffled[:5]

    # Calculer le lundi de la semaine ISO
    jan4 = datetime(year, 1, 4)
    jan4_weekday = jan4.isoweekday()
    monday_week1 = jan4 - timedelta(days=jan4_weekday - 1)
    monday = monday_week1 + timedelta(weeks=week - 1)
    sunday = monday + timedelta(days=7)

    return {
        "week": week,
        "year": year,
        "track_ids": selected,
        "starts_at": monday.isoformat(),
        "ends_at": sunday.isoformat(),
    }


@rotation_router.get("/rotation/next")
async def get_next_rotation():
    """
    Retourne la rotation de la semaine prochaine (preview).
    Utile si le vote influence la sélection.
    """
    now = datetime.utcnow()
    next_week = now + timedelta(days=7)
    iso = next_week.isocalendar()
    week, year = iso[1], iso[0]

    # TODO: Si le vote est actif, utiliser les résultats du vote
    # pour influencer la sélection au lieu du shuffle aléatoire.
    # Pour le MVP, on utilise le même algo déterministe.

    import random
    pool = [
        "fur_elise", "menuet_sol", "prelude_em_chopin",
        "invention_1_bach", "sonate_facile_mozart",
        "gymnopedie_1", "gnossienne_1", "reverie_debussy",
        "nocturne_op9_2", "valse_la_min_chopin",
        "prelude_do_bach", "canon_re_pachelbel",
        "clair_de_lune", "arabesque_1", "sonate_clair_lune",
    ]

    seed = year * 100 + week
    rng = random.Random(seed)
    shuffled = list(pool)
    rng.shuffle(shuffled)
    selected = shuffled[:5]

    jan4 = datetime(year, 1, 4)
    jan4_weekday = jan4.isoweekday()
    monday_week1 = jan4 - timedelta(days=jan4_weekday - 1)
    monday = monday_week1 + timedelta(weeks=week - 1)
    sunday = monday + timedelta(days=7)

    return {
        "week": week,
        "year": year,
        "track_ids": selected,
        "starts_at": monday.isoformat(),
        "ends_at": sunday.isoformat(),
    }
