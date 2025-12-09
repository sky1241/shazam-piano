"""
Audio separation helper.
Tries Demucs (si activé et installé) pour isoler une piste (vocals/melody),
sinon fallback sur HPSS (librosa) pour extraire la composante harmonique.
"""
from pathlib import Path
from typing import Optional
import subprocess

import librosa
import soundfile as sf
from loguru import logger

from config import settings


def _separate_with_demucs(audio_path: Path) -> Optional[Path]:
    """Use demucs CLI if available and enabled."""
    if not settings.USE_DEMUCS:
        return None
    try:
        output_dir = audio_path.parent / "separated"
        output_dir.mkdir(exist_ok=True)
        # demucs --two-stems=<target> -n <model> -d <device> --out <dir> <file>
        cmd = [
            "demucs",
            f"--two-stems={settings.DEMUCS_TARGET}",
            "-n",
            settings.DEMUCS_MODEL,
            "-d",
            settings.DEMUCS_DEVICE,
            "--out",
            str(output_dir),
            str(audio_path),
        ]
        logger.info(f"Running Demucs: {' '.join(cmd)}")
        subprocess.run(cmd, check=True, timeout=settings.DEMUCS_TIMEOUT)

        # Expected path: <out>/<model>/<basename>/<target>.wav
        candidate = output_dir / settings.DEMUCS_MODEL / audio_path.stem / f"{settings.DEMUCS_TARGET}.wav"
        if candidate.exists():
            logger.info(f"Demucs separated {settings.DEMUCS_TARGET}: {candidate}")
            return candidate
        logger.warning(f"Demucs output not found: {candidate}")
        return None
    except FileNotFoundError:
        logger.warning("Demucs not installed or not in PATH; skipping demucs separation")
        return None
    except Exception as e:
        logger.error(f"Demucs separation failed: {e}")
        return None


def _separate_with_hpss(audio_path: Path) -> Optional[Path]:
    """Fallback harmonic/percussive separation with librosa."""
    try:
        y, sr = librosa.load(str(audio_path), sr=None, mono=True)
        harmonic, _ = librosa.effects.hpss(y)
        output_dir = audio_path.parent / "separated"
        output_dir.mkdir(exist_ok=True)
        out_path = output_dir / f"{audio_path.stem}_melody.wav"
        sf.write(str(out_path), harmonic, sr)
        logger.info(f"Separated harmonic stem with librosa: {out_path}")
        return out_path
    except Exception as e:
        logger.error(f"Librosa HPSS separation failed: {e}")
        return None


def separate_melody(audio_path: Path) -> Optional[Path]:
    """
    Separate audio to isolate the melodic stem.
    Returns path to separated WAV if successful, else None.
    """
    # Try Demucs first if enabled
    demucs_path = _separate_with_demucs(audio_path)
    if demucs_path:
        return demucs_path

    # Fallback HPSS if enabled
    if settings.USE_SPLEETER:
        return _separate_with_hpss(audio_path)

    return None
