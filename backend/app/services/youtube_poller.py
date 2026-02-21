from datetime import datetime, timezone

import httpx

from app.models import Channel, SampleItem
from app.services.store import SampleStore
from app.services.tagging import RulesTagger


class YouTubePoller:
    def __init__(self, *, api_key: str, base_url: str, store: SampleStore, tagger: RulesTagger):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.store = store
        self.tagger = tagger

    async def fetch_recent_uploads(self, channel_id: str, max_results: int = 10) -> list[SampleItem]:
        if not self.api_key:
            return []

        params = {
            "key": self.api_key,
            "channelId": channel_id,
            "part": "snippet",
            "order": "date",
            "type": "video",
            "maxResults": max_results,
        }

        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{self.base_url}/search", params=params)
            response.raise_for_status()
            payload = response.json()

        items: list[SampleItem] = []
        for raw in payload.get("items", []):
            video_id = raw.get("id", {}).get("videoId")
            snippet = raw.get("snippet", {})
            published_raw = snippet.get("publishedAt")
            if not video_id or not published_raw:
                continue

            published_at = datetime.fromisoformat(published_raw.replace("Z", "+00:00")).astimezone(timezone.utc)
            genre_tags, tone_tags = self.tagger.classify(
                snippet.get("title", ""),
                snippet.get("description", ""),
            )
            item = SampleItem(
                id=f"sample-{video_id}",
                youtube_video_id=video_id,
                channel_id=channel_id,
                title=snippet.get("title", "Untitled sample"),
                description_text=snippet.get("description", ""),
                published_at=published_at,
                artwork_url=(snippet.get("thumbnails", {}).get("high", {}) or {}).get("url"),
                duration_seconds=None,
                genre_tags=genre_tags,
                tone_tags=tone_tags,
                is_saved=False,
                saved_at=None,
                download_state="not_downloaded",
                stream_state="idle",
            )
            items.append(item)

        return items

    async def poll_channel(self, channel: Channel) -> list[SampleItem]:
        fetched = await self.fetch_recent_uploads(channel.id)
        known = self.store.existing_video_ids(channel.id)
        new_items = [item for item in fetched if item.youtube_video_id not in known]
        self.store.upsert_samples(new_items)
        return new_items

    async def poll_all(self, channels: list[Channel]) -> list[SampleItem]:
        inserted: list[SampleItem] = []
        for channel in channels:
            if channel.is_tracked:
                inserted.extend(await self.poll_channel(channel))
        return inserted
