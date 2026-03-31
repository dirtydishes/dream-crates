from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import json
from subprocess import CompletedProcess, run

from app.models import SampleItem


@dataclass
class ResolveResult:
    url: str
    expires_at: datetime
    source: str
    headers: dict[str, str]


class PlaybackResolver:
    def __init__(
        self,
        *,
        command_template: str = "",
        fallback_url: str,
        ttl_seconds: int = 3600,
    ):
        self.command_template = command_template.strip()
        self.fallback_url = fallback_url
        self.ttl_seconds = ttl_seconds
        self._cache: dict[tuple[str, str], ResolveResult] = {}

    def resolve_stream(self, sample: SampleItem) -> ResolveResult:
        return self._resolve(sample, mode="stream")

    def resolve_download(self, sample: SampleItem) -> ResolveResult:
        return self._resolve(sample, mode="download")

    def _resolve(self, sample: SampleItem, *, mode: str) -> ResolveResult:
        cache_key = (sample.id, mode)
        cached = self._cache.get(cache_key)
        now = datetime.now(timezone.utc)
        if cached is not None and cached.expires_at > now + timedelta(seconds=30):
            return cached

        if self.command_template:
            resolved = self._resolve_via_command(sample, mode=mode)
            if resolved is not None:
                self._cache[cache_key] = resolved
                return resolved

        fallback = ResolveResult(
            url=self.fallback_url,
            expires_at=now + timedelta(seconds=self.ttl_seconds),
            source="fallback",
            headers={},
        )
        self._cache[cache_key] = fallback
        return fallback

    def _resolve_via_command(self, sample: SampleItem, *, mode: str) -> ResolveResult | None:
        command = self.command_template.format(
            video_id=sample.youtube_video_id,
            sample_id=sample.id,
            mode=mode,
        )

        completed: CompletedProcess[str] = run(
            command,
            shell=True,
            check=False,
            capture_output=True,
            text=True,
        )

        if completed.returncode != 0:
            return None

        payload = json.loads(completed.stdout)
        url = payload.get("url")
        if not url:
            return None

        expires_at_raw = payload.get("expiresAt")
        expires_at = (
            datetime.fromisoformat(expires_at_raw.replace("Z", "+00:00"))
            if expires_at_raw
            else datetime.now(timezone.utc) + timedelta(seconds=self.ttl_seconds)
        )
        source = payload.get("source", "command")
        headers = payload.get("headers") or {}
        return ResolveResult(
            url=url,
            expires_at=expires_at,
            source=source,
            headers={str(key): str(value) for key, value in headers.items() if value is not None},
        )
