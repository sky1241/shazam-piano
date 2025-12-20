"""Firebase Admin helpers: init, token verification, Firestore writes."""
from __future__ import annotations

from typing import Any, Dict, Optional

from loguru import logger

try:
    import firebase_admin
    from firebase_admin import auth as firebase_auth
    from firebase_admin import credentials, firestore
except ImportError:  # pragma: no cover - handled at runtime
    firebase_admin = None
    firebase_auth = None
    credentials = None
    firestore = None

firebase_app = None
firestore_client = None


def init_firebase(cred_path: Optional[str]) -> None:
    """Initialize Firebase Admin SDK with the given credentials path."""
    global firebase_app, firestore_client

    if firebase_admin is None:
        logger.warning("Firebase Admin SDK not installed; skipping Firebase init.")
        return

    if not cred_path:
        logger.warning("FIREBASE_CREDENTIALS not set; skipping Firebase init.")
        return

    try:
        logger.info(f"Initializing Firebase Admin with creds: {cred_path}")
        cred = credentials.Certificate(cred_path)
        firebase_app = firebase_admin.initialize_app(cred)
        firestore_client = firestore.client(app=firebase_app)
        logger.success("Firebase Admin initialized.")
    except Exception as e:  # pragma: no cover
        logger.error(f"Firebase initialization failed: {e}")
        firebase_app = None
        firestore_client = None


def verify_firebase_token(id_token: str) -> Dict[str, Any]:
    """Verify Firebase ID token and return decoded claims."""
    if firebase_auth is None or firebase_app is None:
        raise RuntimeError("Firebase not initialized")

    return firebase_auth.verify_id_token(id_token, app=firebase_app)


def save_job_for_user(user_id: str, job_id: str, payload: Dict[str, Any]) -> None:
    """Persist job metadata to Firestore under users/{uid}/jobs/{jobId}."""
    if firestore_client is None:
        logger.warning("Firestore client not initialized; skipping job persistence.")
        return

    doc_ref = (
        firestore_client.collection("users")
        .document(user_id)
        .collection("jobs")
        .document(job_id)
    )
    payload = dict(payload)
    payload["userId"] = user_id
    doc_ref.set(payload, merge=True)
    logger.success(f"Job {job_id} saved to Firestore for user {user_id}.")
