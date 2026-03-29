from dataclasses import dataclass
from datetime import datetime, timezone

import httpx

from app.models import Channel, SampleItem
from app.services.store import SampleStore
from app.services.tagging import RulesTagger


@dataclass
class UploadPage:
    items: list[SampleItem]
    next_page_token: str | None


@dataclass
class BackfillResult:
    inserted_items: list[SampleItem]
    exhausted: bool
    channels_processed: int


class YouTubePoller:
    def __init__(self, *, api_key: str, base_url: str, store: SampleStore, tagger: RulesTagger):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.store = store
        self.tagger = tagger

    async def fetch_recent_uploads(self, channel_id: str, max_results: int = 10) -> list[SampleItem]:
        page = await self._fetch_upload_page(channel_id, max_results=max_results)
        return page.items

    async def _fetch_upload_page(
        self,
        channel_id: str,
        *,
        max_results: int,
        page_token: str | None = None,
    ) -> UploadPage:
        if not self.api_key:
            return UploadPage(items=[], next_page_token=None)

        params = {
            "key": self.api_key,
            "channelId": channel_id,
            "part": "snippet",
            "order": "date",
            "type": "video",
            "maxResults": max_results,
        }
        if page_token:
            params["pageToken"] = page_token

        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{self.base_url}/search", params=params)
            response.raise_for_status()
            payload = response.json()

        items: list[SampleItem] = []
        for raw in payload.get("items", []):
            item = self._build_sample_item(channel_id, raw)
            if item is not None:
                items.append(item)

        return UploadPage(items=items, next_page_token=payload.get("nextPageToken"))

    def _build_sample_item(self, channel_id: str, raw: dict) -> SampleItem | None:
        video_id = raw.get("id", {}).get("videoId")
        snippet = raw.get("snippet", {})
        published_raw = snippet.get("publishedAt")
        if not video_id or not published_raw:
            return None

        published_at = datetime.fromisoformat(published_raw.replace("Z", "+00:00")).astimezone(timezone.utc)
        genre_tags, tone_tags = self.tagger.classify(
            snippet.get("title", ""),
            snippet.get("description", ""),
        )
        return SampleItem(
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

    async def backfill_channel(self, channel: Channel, *, limit: int) -> BackfillResult:
        inserted: list[SampleItem] = []
        known = self.store.existing_video_ids(channel.id)
        next_page_token: str | None = None
        exhausted = True

        while len(inserted) < limit:
            page = await self._fetch_upload_page(
                channel.id,
                max_results=50,
                page_token=next_page_token,
            )
            if not page.items:
                exhausted = page.next_page_token is None
                break

            remaining = limit - len(inserted)
            unseen_items = [item for item in page.items if item.youtube_video_id not in known]
            page_insertions = unseen_items[:remaining]
            if page_insertions:
                self.store.upsert_samples(page_insertions)
                inserted.extend(page_insertions)
                known.update(item.youtube_video_id for item in page_insertions)

            if len(unseen_items) > remaining:
                exhausted = False
                break

            if page.next_page_token is None:
                exhausted = True
                break

            next_page_token = page.next_page_token
            exhausted = False

        return BackfillResult(
            inserted_items=inserted,
            exhausted=exhausted,
            channels_processed=1,
        )

    async def backfill_all(self, channels: list[Channel], *, limit: int = 333) -> BackfillResult:
        inserted: list[SampleItem] = []
        channels_processed = 0
        exhausted = True

        for channel in channels:
            if not channel.is_tracked:
                continue

            remaining = limit - len(inserted)
            if remaining <= 0:
                exhausted = False
                break

            channels_processed += 1
            result = await self.backfill_channel(channel, limit=remaining)
            inserted.extend(result.inserted_items)
            if not result.exhausted:
                exhausted = False
                break

        return BackfillResult(
            inserted_items=inserted,
            exhausted=exhausted,
            channels_processed=channels_processed,
        )

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
