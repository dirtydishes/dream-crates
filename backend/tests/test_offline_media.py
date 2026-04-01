from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.services.offline_media import OfflineMediaCache, OfflineMediaError
from app.services.resolver import ResolveResult
import app.services.offline_media as offline_media_mod


def test_offline_media_cache_transcodes_once_and_reuses_result(monkeypatch, tmp_path):
    calls: list[list[str]] = []

    def fake_run(command, check, capture_output, text):
        _ = (check, capture_output, text)
        calls.append(command)
        Path(command[-1]).write_bytes(b"a" * 4096)

        class Completed:
            returncode = 0
            stderr = ""

        return Completed()

    monkeypatch.setattr(offline_media_mod, "run", fake_run)

    cache = OfflineMediaCache(tmp_path)
    source = ResolveResult(
        url="https://media.example/audio",
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        source="yt-dlp",
        headers={"User-Agent": "yt-dlp-test"},
    )

    first = cache.resolve("sample-1", source)
    second = cache.resolve("sample-1", source)

    assert first == second
    assert first.name == "sample-1.m4a"
    assert len(calls) == 1
    assert "-headers" in calls[0]
    assert "User-Agent: yt-dlp-test\r\n" in calls[0]


def test_offline_media_cache_surfaces_ffmpeg_failures(monkeypatch, tmp_path):
    def fake_run(command, check, capture_output, text):
        _ = (command, check, capture_output, text)

        class Completed:
            returncode = 1
            stderr = "ffmpeg exploded"

        return Completed()

    monkeypatch.setattr(offline_media_mod, "run", fake_run)

    cache = OfflineMediaCache(tmp_path)
    source = ResolveResult(
        url="https://media.example/audio",
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        source="yt-dlp",
        headers={},
    )

    try:
        cache.resolve("sample-2", source)
        raise AssertionError("expected transcode to fail")
    except OfflineMediaError as exc:
        assert "ffmpeg exploded" in str(exc)
