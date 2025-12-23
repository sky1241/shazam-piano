"""
ACRCloud identification helper.
Reads creds from settings and posts audio to ACRCloud identify API.
"""
import base64
import hashlib
import hmac
import time
from pathlib import Path
from typing import Optional

import httpx
from loguru import logger

from config import settings


def identify_audio(audio_path: Path) -> Optional[dict]:
    """
    Identify audio using ACRCloud.
    Returns dict with title/artist/album if success, else None.
    """
    if not (settings.ACR_HOST and settings.ACR_ACCESS_KEY and settings.ACR_ACCESS_SECRET):
        return None

    try:
        data_type = "audio"
        signature_version = "1"
        timestamp = int(time.time())

        string_to_sign = "\n".join(
            ["POST", "/v1/identify", settings.ACR_ACCESS_KEY, data_type, signature_version, str(timestamp)]
        )

        sign = base64.b64encode(
            hmac.new(
                settings.ACR_ACCESS_SECRET.encode("utf-8"),
                string_to_sign.encode("utf-8"),
                digestmod=hashlib.sha1,
            ).digest()
        ).decode("utf-8")

        files = {
            "sample": (audio_path.name, audio_path.read_bytes(), "audio/mpeg"),
            "access_key": (None, settings.ACR_ACCESS_KEY),
            "data_type": (None, data_type),
            "signature_version": (None, signature_version),
            "signature": (None, sign),
            "timestamp": (None, str(timestamp)),
        }

        url = f"https://{settings.ACR_HOST}/v1/identify"
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(url, files=files)
            resp.raise_for_status()
            result = resp.json()

        status_code = result.get("status", {}).get("code")
        if status_code != 0:
            logger.warning(f"ACR identify failed code={status_code} msg={result.get('status', {}).get('msg')}")
            return None

        metadata = result.get("metadata", {})
        music_list = metadata.get("music", [])
        if not music_list:
            return None

        first = music_list[0]
        return {
            "title": first.get("title"),
            "artist": ", ".join([a.get("name") for a in first.get("artists", []) if a.get("name")]),
            "album": (first.get("album") or {}).get("name"),
            "acrid": first.get("acrid"),
            "score": first.get("score"),
        }
    except Exception as e:
        logger.error(f"ACR identify error: {e}")
        return None

