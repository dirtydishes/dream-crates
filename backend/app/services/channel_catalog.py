from __future__ import annotations

from datetime import datetime, timedelta, timezone

import httpx

from app.models import Channel, SampleItem


class ChannelCatalog:
    def __init__(
        self,
        *,
        api_key: str,
        base_url: str,
        defaults: list[Channel],
        cache_ttl_seconds: int = 6 * 60 * 60,
    ):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.defaults = defaults
        self.cache_ttl_seconds = cache_ttl_seconds
        self._cached_channels = {channel.id: channel for channel in defaults}
        self._cache_expires_at = datetime.min.replace(tzinfo=timezone.utc)

    async def default_channels(self) -> list[Channel]:
        await self._refresh_if_needed()
        return list(self._cached_channels.values())

    async def decorate_samples(self, samples: list[SampleItem]) -> list[SampleItem]:
        await self._refresh_if_needed()
        return [self._decorate_sample(sample) for sample in samples]

    async def _refresh_if_needed(self) -> None:
        now = datetime.now(timezone.utc)
        if now < self._cache_expires_at:
            return

        merged = {channel.id: channel for channel in self.defaults}

        if self.api_key and self.defaults:
            try:
                hydrated = await self._fetch_channels_from_youtube()
                for channel in hydrated:
                    merged[channel.id] = channel
            except Exception:
                # Keep serving cached/default channel metadata if YouTube is unavailable.
                pass

        self._cached_channels = merged
        self._cache_expires_at = now + timedelta(seconds=self.cache_ttl_seconds)

    async def _fetch_channels_from_youtube(self) -> list[Channel]:
        params = {
            "key": self.api_key,
            "part": "snippet",
            "id": ",".join(channel.id for channel in self.defaults),
        }

        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{self.base_url}/channels", params=params)
            response.raise_for_status()
            payload = response.json()

        defaults_by_id = {channel.id: channel for channel in self.defaults}
        hydrated: list[Channel] = []

        for raw in payload.get("items", []):
            channel_id = raw.get("id")
            snippet = raw.get("snippet", {})
            fallback = defaults_by_id.get(channel_id)
            if not channel_id or fallback is None:
                continue

            thumbnails = snippet.get("thumbnails", {})
            avatar_url = (
                (thumbnails.get("high") or {}).get("url")
                or (thumbnails.get("medium") or {}).get("url")
                or (thumbnails.get("default") or {}).get("url")
                or fallback.avatar_url
            )

            hydrated.append(
                Channel(
                    id=channel_id,
                    handle=fallback.handle,
                    title=snippet.get("title", fallback.title),
                    avatar_url=avatar_url,
                    is_tracked=fallback.is_tracked,
                )
            )

        return hydrated

    def _decorate_sample(self, sample: SampleItem) -> SampleItem:
        channel = self._cached_channels.get(sample.channel_id)
        if channel is None:
            return sample

        return sample.model_copy(
            update={
                "channel_title": sample.channel_title or channel.title,
                "channel_handle": sample.channel_handle or channel.handle,
                "channel_avatar_url": sample.channel_avatar_url or channel.avatar_url,
            }
        )
