import asyncio
from datetime import datetime, timezone
from pathlib import Path

import httpx

from app.models import Channel, SampleItem
from app.services.store import SampleStore
from app.services.tagging import RulesTagger
from app.services.youtube_poller import UploadPage, YouTubePoller


class FakePoller(YouTubePoller):
    def __init__(self, store: SampleStore, items: list[SampleItem]):
        super().__init__(
            api_key="ignored",
            base_url="https://example.com",
            store=store,
            tagger=RulesTagger(),
        )
        self._items = items

    async def _fetch_upload_page(
        self,
        channel_id: str,
        *,
        max_results: int,
        page_token: str | None = None,
    ) -> UploadPage:
        _ = max_results
        _ = page_token
        items = [item for item in self._items if item.channel_id == channel_id]
        return UploadPage(items=items, next_page_token=None)


class PaginatedFakePoller(YouTubePoller):
    def __init__(self, store: SampleStore, pages_by_channel: dict[str, list[UploadPage]]):
        super().__init__(
            api_key="ignored",
            base_url="https://example.com",
            store=store,
            tagger=RulesTagger(),
        )
        self._pages_by_channel = pages_by_channel
        self._page_index: dict[str, int] = {}

    async def _fetch_upload_page(
        self,
        channel_id: str,
        *,
        max_results: int,
        page_token: str | None = None,
    ) -> UploadPage:
        _ = max_results
        _ = page_token
        index = self._page_index.get(channel_id, 0)
        self._page_index[channel_id] = index + 1
        pages = self._pages_by_channel.get(channel_id, [])
        if index >= len(pages):
            return UploadPage(items=[], next_page_token=None)
        return pages[index]


def sample(video_id: str, *, channel_id: str = "channel-1") -> SampleItem:
    return SampleItem(
        id=f"sample-{video_id}",
        youtube_video_id=video_id,
        channel_id=channel_id,
        title=f"Sample {video_id}",
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


def test_poller_dedupes_inserted_rows(tmp_path: Path):
    db_path = str(tmp_path / "test.db")
    store = SampleStore(db_path)
    channel = Channel(id="channel-1", handle="@c1", title="c1", is_tracked=True)

    poller = FakePoller(store, [sample("v1"), sample("v2")])
    first = asyncio.run(poller.poll_all([channel]))
    second = asyncio.run(poller.poll_all([channel]))

    assert len(first) == 2
    assert len(second) == 0
    assert len(store.list_recent()) == 2


def test_backfill_walks_multiple_pages_to_find_older_unseen_uploads(tmp_path: Path):
    db_path = str(tmp_path / "test.db")
    store = SampleStore(db_path)
    channel = Channel(id="channel-1", handle="@c1", title="c1", is_tracked=True)
    store.upsert_samples([sample("v1"), sample("v2")])

    poller = PaginatedFakePoller(
        store,
        {
            "channel-1": [
                UploadPage(items=[sample("v1"), sample("v2")], next_page_token="page-2"),
                UploadPage(items=[sample("v3"), sample("v4")], next_page_token=None),
            ]
        },
    )

    result = asyncio.run(poller.backfill_all([channel], limit=2))

    assert [item.youtube_video_id for item in result.inserted_items] == ["v3", "v4"]
    assert result.exhausted is True
    assert result.channels_processed == 1
    assert len(store.list_recent()) == 4


def test_backfill_stops_when_requested_limit_is_reached(tmp_path: Path):
    db_path = str(tmp_path / "test.db")
    store = SampleStore(db_path)
    channel = Channel(id="channel-1", handle="@c1", title="c1", is_tracked=True)

    poller = PaginatedFakePoller(
        store,
        {
            "channel-1": [
                UploadPage(items=[sample("v1"), sample("v2")], next_page_token="page-2"),
                UploadPage(items=[sample("v3"), sample("v4")], next_page_token="page-3"),
            ]
        },
    )

    result = asyncio.run(poller.backfill_all([channel], limit=3))

    assert [item.youtube_video_id for item in result.inserted_items] == ["v1", "v2", "v3"]
    assert result.exhausted is False
    assert result.channels_processed == 1
    assert len(store.list_recent()) == 3


def test_backfill_returns_when_channel_history_is_exhausted(tmp_path: Path):
    db_path = str(tmp_path / "test.db")
    store = SampleStore(db_path)
    channel = Channel(id="channel-1", handle="@c1", title="c1", is_tracked=True)

    poller = PaginatedFakePoller(
        store,
        {
            "channel-1": [
                UploadPage(items=[sample("v1")], next_page_token=None),
            ]
        },
    )

    result = asyncio.run(poller.backfill_all([channel], limit=3))

    assert [item.youtube_video_id for item in result.inserted_items] == ["v1"]
    assert result.exhausted is True
    assert result.channels_processed == 1
    assert len(store.list_recent()) == 1


def test_fetch_upload_page_falls_back_to_ytdlp_when_api_is_forbidden(tmp_path: Path, monkeypatch):
    db_path = str(tmp_path / "test.db")
    store = SampleStore(db_path)
    poller = YouTubePoller(
        api_key="restricted-key",
        base_url="https://example.com",
        store=store,
        tagger=RulesTagger(),
    )

    async def fake_api(channel_id: str, *, max_results: int, page_token: str | None = None) -> UploadPage:
        _ = channel_id
        _ = max_results
        _ = page_token
        request = httpx.Request("GET", "https://example.com/search")
        response = httpx.Response(403, request=request)
        raise httpx.HTTPStatusError("forbidden", request=request, response=response)

    def fake_ytdlp(channel_id: str, *, max_results: int, page_token: str | None = None) -> UploadPage:
        _ = channel_id
        _ = max_results
        _ = page_token
        return UploadPage(items=[sample("fallback")], next_page_token=None)

    monkeypatch.setattr(poller, "_fetch_upload_page_via_api", fake_api)
    monkeypatch.setattr(poller, "_fetch_upload_page_via_ytdlp", fake_ytdlp)

    page = asyncio.run(poller._fetch_upload_page("channel-1", max_results=10))

    assert [item.youtube_video_id for item in page.items] == ["fallback"]
    assert page.next_page_token is None


def test_ytdlp_playlist_pages_are_converted_into_samples(tmp_path: Path, monkeypatch):
    db_path = str(tmp_path / "test.db")
    store = SampleStore(db_path)
    poller = YouTubePoller(
        api_key="",
        base_url="https://example.com",
        store=store,
        tagger=RulesTagger(),
    )

    monkeypatch.setattr(
        "app.services.youtube_poller.run_ytdlp_json",
        lambda args: {
            "entries": [
                {
                    "id": "abc123",
                    "title": "Warm Rhodes loop",
                    "description": "soulful jazz sample",
                    "duration": 93,
                    "timestamp": 1774552509,
                    "channel": "Andre Navarro II",
                    "uploader_id": "@andrenavarroII",
                    "thumbnail": "https://example.com/thumb.jpg",
                },
                {
                    "id": "def456",
                    "title": "Cold synth pad",
                    "description": "",
                    "duration": 42,
                    "upload_date": "20260324",
                    "channel": "Andre Navarro II",
                    "uploader_id": "@andrenavarroII",
                    "thumbnail": "https://example.com/thumb-2.jpg",
                },
            ]
        },
    )

    page = poller._fetch_upload_page_via_ytdlp("UCv5OAW45h67CJEY6kJLyisg", max_results=2, page_token="0")

    assert [item.youtube_video_id for item in page.items] == ["abc123", "def456"]
    assert page.next_page_token == "2"
    assert page.items[0].channel_handle == "@andrenavarroII"
    assert page.items[0].duration_seconds == 93
    assert page.items[0].published_at == datetime(2026, 3, 26, 19, 15, 9, tzinfo=timezone.utc)
    assert page.items[1].published_at == datetime(2026, 3, 24, 0, 0, 0, tzinfo=timezone.utc)
