from __future__ import annotations

import json
from subprocess import CompletedProcess, run
from typing import Any


def stream_format_selector() -> str:
    return "bestaudio[ext=m4a]/bestaudio[acodec*=mp4a]/bestaudio[ext=mp4]/best[ext=mp4]/bestaudio/best"


def download_format_selector() -> str:
    return "bestaudio[ext=m4a]/bestaudio[acodec*=mp4a]/bestaudio[ext=mp4]/best[ext=mp4]"


def run_ytdlp_json(args: list[str]) -> dict[str, Any]:
    completed: CompletedProcess[str] = run(
        [
            "yt-dlp",
            "--dump-single-json",
            "--no-warnings",
            *args,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "yt-dlp failed")

    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("yt-dlp returned invalid JSON") from exc


def uploads_playlist_url(channel_id: str) -> str:
    if channel_id.startswith("UC") and len(channel_id) > 2:
        return f"https://www.youtube.com/playlist?list=UU{channel_id[2:]}"
    return f"https://www.youtube.com/channel/{channel_id}/videos"


def pick_media_url(payload: dict[str, Any]) -> str | None:
    selected = pick_media_source(payload)
    return selected["url"] if selected else None


def pick_media_headers(payload: dict[str, Any]) -> dict[str, str]:
    selected = pick_media_source(payload)
    if not selected:
        return {}
    raw_headers = selected.get("http_headers") or payload.get("http_headers") or {}
    return {
        str(key): str(value)
        for key, value in raw_headers.items()
        if value is not None
    }


def pick_media_source(payload: dict[str, Any]) -> dict[str, Any] | None:
    requested_formats = payload.get("requested_formats") or []
    for fmt in requested_formats:
        if _has_audio(fmt):
            return fmt

    direct_url = payload.get("url")
    if direct_url and _has_audio(payload):
        return payload

    formats = payload.get("formats") or []
    audio_only_formats = [fmt for fmt in formats if _has_audio(fmt) and _is_audio_only(fmt)]
    if audio_only_formats:
        return max(audio_only_formats, key=_format_score)

    mixed_formats = [fmt for fmt in formats if _has_audio(fmt)]
    if mixed_formats:
        return max(mixed_formats, key=_format_score)

    return payload if direct_url else None


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
