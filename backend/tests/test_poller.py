import asyncio
from datetime import datetime, timezone
from pathlib import Path

from app.models import Channel, SampleItem
from app.services.store import SampleStore
from app.services.tagging import RulesTagger
from app.services.youtube_poller import YouTubePoller


class FakePoller(YouTubePoller):
    def __init__(self, store: SampleStore, items: list[SampleItem]):
        super().__init__(
            api_key="ignored",
            base_url="https://example.com",
            store=store,
            tagger=RulesTagger(),
        )
        self._items = items

    async def fetch_recent_uploads(self, channel_id: str, max_results: int = 10):
        _ = max_results
        return [item for item in self._items if item.channel_id == channel_id]


def sample(video_id: str) -> SampleItem:
    return SampleItem(
        id=f"sample-{video_id}",
        youtube_video_id=video_id,
        channel_id="channel-1",
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
