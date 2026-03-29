from __future__ import annotations

from typing import Any


def pick_media_url(payload: dict[str, Any]) -> str | None:
    requested_formats = payload.get("requested_formats") or []
    for fmt in requested_formats:
        if _has_audio(fmt):
            return fmt["url"]

    direct_url = payload.get("url")
    if direct_url and _has_audio(payload):
        return direct_url

    formats = payload.get("formats") or []
    audio_only_formats = [fmt for fmt in formats if _has_audio(fmt) and _is_audio_only(fmt)]
    if audio_only_formats:
        return max(audio_only_formats, key=_format_score)["url"]

    mixed_formats = [fmt for fmt in formats if _has_audio(fmt)]
    if mixed_formats:
        return max(mixed_formats, key=_format_score)["url"]

    return direct_url


def _has_audio(fmt: dict[str, Any]) -> bool:
    return bool(fmt.get("url")) and fmt.get("acodec") != "none"


def _is_audio_only(fmt: dict[str, Any]) -> bool:
    return fmt.get("vcodec") == "none"


def _format_score(fmt: dict[str, Any]) -> tuple[float, float, float, float, float]:
    return (
        float(fmt.get("abr") or 0),
        float(fmt.get("asr") or 0),
        float(fmt.get("tbr") or 0),
        float(fmt.get("filesize") or 0),
        float(fmt.get("quality") or 0),
    )
