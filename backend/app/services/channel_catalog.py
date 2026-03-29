from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
import re

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
        await self._refresh_if_needed(extra_channel_ids={sample.channel_id for sample in samples})
        return [self._decorate_sample(sample) for sample in samples]

    async def _refresh_if_needed(self, *, extra_channel_ids: set[str] | None = None) -> None:
        now = datetime.now(timezone.utc)
        requested_ids = extra_channel_ids or set()
        if now < self._cache_expires_at and requested_ids.issubset(self._cached_channels.keys()):
            return

        merged = {channel.id: channel for channel in self.defaults}
        for channel_id in requested_ids:
            merged.setdefault(
                channel_id,
                Channel(id=channel_id, handle="", title=channel_id, avatar_url=None, is_tracked=True)
            )

        if self.api_key and merged:
            try:
                hydrated = await self._fetch_channels_from_youtube(list(merged.values()))
                for channel in hydrated:
                    merged[channel.id] = channel
            except Exception:
                # Keep serving cached/default channel metadata if YouTube is unavailable.
                pass
        elif merged:
            try:
                hydrated = await self._fetch_channels_from_html(list(merged.values()))
                for channel in hydrated:
                    merged[channel.id] = channel
            except Exception:
                # Keep serving cached/default channel metadata if scraping fails.
                pass

        self._cached_channels = merged
        self._cache_expires_at = now + timedelta(seconds=self.cache_ttl_seconds)

    async def _fetch_channels_from_youtube(self, channels: list[Channel]) -> list[Channel]:
        params = {
            "key": self.api_key,
            "part": "snippet",
            "id": ",".join(channel.id for channel in channels),
        }

        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{self.base_url}/channels", params=params)
            response.raise_for_status()
            payload = response.json()

        defaults_by_id = {channel.id: channel for channel in channels}
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

    async def _fetch_channels_from_html(self, channels: list[Channel]) -> list[Channel]:
        async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
            responses = await asyncio.gather(
                *[self._fetch_channel_page(client, channel) for channel in channels],
                return_exceptions=True,
            )

        hydrated: list[Channel] = []
        for response in responses:
            if isinstance(response, Channel):
                hydrated.append(response)
        return hydrated

    async def _fetch_channel_page(self, client: httpx.AsyncClient, channel: Channel) -> Channel | None:
        handle_or_id = channel.handle.strip() if channel.handle else ""
        path = handle_or_id if handle_or_id.startswith("@") else f"/channel/{channel.id}"
        if path.startswith("@"):
            path = f"/{path}"

        response = await client.get(f"https://www.youtube.com{path}")
        response.raise_for_status()
        title, avatar_url = self._parse_channel_html(
            response.text,
            fallback_title=channel.title,
            fallback_avatar_url=channel.avatar_url,
        )

        return Channel(
            id=channel.id,
            handle=channel.handle,
            title=title,
            avatar_url=avatar_url,
            is_tracked=channel.is_tracked,
        )

    @staticmethod
    def _parse_channel_html(
        html: str,
        *,
        fallback_title: str,
        fallback_avatar_url: str | None,
    ) -> tuple[str, str | None]:
        title_match = re.search(r'channelMetadataRenderer":\{"title":"([^"]+)"', html)
        avatar_match = re.search(r"(https://yt3\.googleusercontent\.com[^\"\\]+)", html)

        title = title_match.group(1) if title_match else fallback_title
        avatar_url = avatar_match.group(1) if avatar_match else fallback_avatar_url
        return title, avatar_url

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
