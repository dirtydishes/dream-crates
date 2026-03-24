import json
from datetime import datetime, timezone

from app.models import SampleItem
from app.services.resolver import PlaybackResolver


def sample() -> SampleItem:
    return SampleItem(
        id="sample-1",
        youtube_video_id="yt-1",
        channel_id="channel-1",
        title="Sample",
        description_text="desc",
        published_at=datetime.now(timezone.utc),
        artwork_url=None,
        duration_seconds=60,
        genre_tags=[],
        tone_tags=[],
        is_saved=False,
        saved_at=None,
        download_state="not_downloaded",
        stream_state="idle",
    )


def test_resolver_uses_fallback_without_command():
    resolver = PlaybackResolver(
        command_template="",
        fallback_url="https://fallback.example/audio.mp3",
        ttl_seconds=600,
    )

    result = resolver.resolve_stream(sample())

    assert result.url == "https://fallback.example/audio.mp3"
    assert result.source == "fallback"


def test_resolver_uses_command_when_available(tmp_path):
    script = tmp_path / "resolver.sh"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s' '{\"url\":\"https://resolved.example/audio.mp3\",\"expiresAt\":\"2026-01-01T00:00:00Z\",\"source\":\"command\"}'\n",
        encoding="utf-8",
    )
    script.chmod(0o755)

    resolver = PlaybackResolver(
        command_template=str(script),
        fallback_url="https://fallback.example/audio.mp3",
    )

    result = resolver.resolve_download(sample())

    assert result.url == "https://resolved.example/audio.mp3"
    assert result.source == "command"
    assert result.expires_at.year == 2026
