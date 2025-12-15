"""
Configuration for ShazaPiano Backend
Levels presets, paths, limits
"""
from pathlib import Path
from typing import Dict, Any
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings"""
    
    # Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    DEBUG: bool = True
    BASE_URL: str = "http://127.0.0.1:8000"  # used to build absolute media URLs for clients
    
    # ACRCloud (optional)
    ACR_HOST: str | None = None
    ACR_ACCESS_KEY: str | None = None
    ACR_ACCESS_SECRET: str | None = None
    
    # Separation (optional)
    USE_SPLEETER: bool = True  # keeps HPSS separation via librosa if True
    USE_DEMUCS: bool = False   # set True si demucs installé (Python 3.10 recommandé)
    SEPARATION_TARGET: str = "vocals"  # HPSS target stem label
    DEMUCS_MODEL: str = "mdx_extra"    # demucs model name
    DEMUCS_TARGET: str = "vocals"      # demucs stem to extract (vocals/melody/other)
    DEMUCS_DEVICE: str = "cpu"         # cpu ou cuda
    DEMUCS_TIMEOUT: int = 180          # secondes max pour demucs
    
    # Paths
    BASE_DIR: Path = Path(__file__).parent
    MEDIA_DIR: Path = BASE_DIR / "media"
    INPUT_DIR: Path = MEDIA_DIR / "in"
    OUTPUT_DIR: Path = MEDIA_DIR / "out"
    
    # Upload limits
    MAX_UPLOAD_SIZE_MB: int = 10
    MAX_AUDIO_DURATION_SEC: int = 15
    
    # Processing timeouts
    FFMPEG_TIMEOUT: int = 15
    BASICPITCH_TIMEOUT: int = 60  # Augmenté car BasicPitch est lent
    RENDER_TIMEOUT: int = 30
    
    # Video settings
    VIDEO_WIDTH: int = 960
    VIDEO_HEIGHT: int = 540  # 16:9 plein ecran - réduit pour tests rapides
    VIDEO_FPS: int = 24  # réduit pour tests rapides
    VIDEO_TIME_OFFSET_MS: int = -60  # global timing offset (ms), negative to advance (helps sync bars with audio)
    PREVIEW_DURATION_SEC: int = 10
    FULL_VIDEO_MAX_DURATION_SEC: int | None = 10  # limite toutes les videos a 16s
    VIDEO_LOOKAHEAD_SEC: float = 2.2  # 2.2s lookahead pour meilleure visibilité
    VIDEO_FALLING_SPEED_PX_PER_SEC: int = 300
    VIDEO_FALLING_AREA_HEIGHT: int = 500
    VIDEO_BAR_START_Y_OFFSET: int = 0  # Barres commencent en haut
    
    # Concurrency
    MAX_CONCURRENT_JOBS: int = 4
    
    # Retention
    INPUT_RETENTION_HOURS: int = 24
    OUTPUT_RETENTION_DAYS: int = 7
    
    class Config:
        env_file = ".env"


settings = Settings()


# ============================================
# LEVELS PRESETS - 4 Difficulty Levels
# ============================================

LEVELS: Dict[int, Dict[str, Any]] = {
    1: {
        "name": "Hyper Facile",
        "description": "Mélodie simple, main droite seule",
        "transpose_to_c": True,
        "quantize": "1/4",
        "tempo_factor": 0.8,
        "melody": True,
        "left_hand": None,
        "right_hand_chords": False,
        "polyphony": False,
        "note_range": (60, 79),  # C4-G5
        "filter_short_notes_ms": 100,
    },
    2: {
        "name": "Facile",
        "description": "Mélodie + basse simple",
        "transpose_to_c": True,
        "quantize": "1/8",
        "tempo_factor": 0.9,
        "melody": True,
        "left_hand": "root",  # Fondamentale tenue
        "right_hand_chords": False,
        "polyphony": False,
        "note_range": (48, 72),  # C3-C5
        "filter_short_notes_ms": 80,
    },
    3: {
        "name": "Moyen",
        "description": "Mélodie + accompagnement triades",
        "transpose_to_c": False,
        "quantize": "1/8",  # avec quelques 1/16
        "tempo_factor": 1.0,
        "melody": True,
        "left_hand": "root_fifth",  # Fondamentale + Quinte
        "right_hand_chords": "block",  # Triades plaquées
        "polyphony": True,
        "note_range": (24, 96),  # C2-C6
        "filter_short_notes_ms": 50,
    },
    4: {
        "name": "Pro",
        "description": "Arrangement complet avec arpèges",
        "transpose_to_c": False,
        "quantize": "1/16",
        "tempo_factor": 1.0,
        "melody": True,
        "left_hand": "arpeggio",  # Arpèges 1-5-8
        "right_hand_chords": "broken",  # Triades brisées
        "polyphony": True,
        "note_range": (24, 96),  # C2-C6
        "filter_short_notes_ms": 30,
        "speed_option": True,  # Peut augmenter tempo si facile
    },
}


# ============================================
# CHORD PROGRESSIONS & SCALES
# ============================================

MAJOR_SCALE = [0, 2, 4, 5, 7, 9, 11]
MINOR_SCALE = [0, 2, 3, 5, 7, 8, 10]

COMMON_PROGRESSIONS = {
    "pop": ["I", "V", "vi", "IV"],
    "ballad": ["I", "vi", "IV", "V"],
    "blues": ["I", "I", "I", "I", "IV", "IV", "I", "I", "V", "IV", "I", "V"],
}


# ============================================
# ERROR MESSAGES
# ============================================

ERROR_MESSAGES = {
    "no_audio": "Aucun audio détecté. Veuillez réessayer.",
    "no_melody": "Aucune mélodie détectable. Essayez un environnement plus silencieux.",
    "too_long": f"L'audio ne doit pas dépasser {settings.MAX_AUDIO_DURATION_SEC}s.",
    "too_large": f"Le fichier ne doit pas dépasser {settings.MAX_UPLOAD_SIZE_MB} MB.",
    "processing_failed": "Erreur lors de la génération. Veuillez réessayer.",
    "invalid_level": "Niveau invalide. Utilisez 1, 2, 3 ou 4.",
}


def get_level_config(level: int) -> Dict[str, Any]:
    """Get configuration for a specific level"""
    if level not in LEVELS:
        raise ValueError(ERROR_MESSAGES["invalid_level"])
    return LEVELS[level]


def init_directories():
    """Create necessary directories"""
    settings.INPUT_DIR.mkdir(parents=True, exist_ok=True)
    settings.OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
