from datetime import datetime, timezone

from fastapi.testclient import TestClient

import app.main as main_mod
from app.models import SampleItem
from app.services.channel_catalog import ChannelCatalog
from app.services.youtube_poller import BackfillResult

app = main_mod.app
client = TestClient(app)


def test_download_prepare_returns_url():
    main_mod.store.upsert_samples(
        [
            SampleItem(
                id="sample-1",
                youtube_video_id="yt-1",
                channel_id="channel-1",
                title="Fresh sample",
                description_text="",
                published_at=datetime.now(timezone.utc),
                genre_tags=[],
                tone_tags=[],
                is_saved=False,
                saved_at=None,
                download_state="not_downloaded",
                stream_state="idle",
            )
        ]
    )
    response = client.post("/v1/download/prepare", json={"sample_id": "sample-1"})
    assert response.status_code == 200
    payload = response.json()
    assert payload["sample_id"] == "sample-1"
    assert payload["download_url"].startswith("https://")
    assert payload["source"] in {"fallback", "command"}


def test_playback_resolve_returns_url():
    main_mod.store.upsert_samples(
        [
            SampleItem(
                id="sample-2",
                youtube_video_id="yt-2",
                channel_id="channel-1",
                title="Fresh sample",
                description_text="",
                published_at=datetime.now(timezone.utc),
                genre_tags=[],
                tone_tags=[],
                is_saved=False,
                saved_at=None,
                download_state="not_downloaded",
                stream_state="idle",
            )
        ]
    )
    response = client.post("/v1/playback/resolve", json={"sample_id": "sample-2"})
    assert response.status_code == 200
    payload = response.json()
    assert payload["sample_id"] == "sample-2"
    assert payload["playback_url"].startswith("https://")


def test_register_device_and_update_preferences():
    reg = client.post(
        "/v1/devices/register",
        json={
            "device_id": "device-abc",
            "apns_token": "token",
            "notifications_enabled": True,
            "quiet_start_hour": 22,
            "quiet_end_hour": 8,
        },
    )
    assert reg.status_code == 200
    assert reg.json()["registered"] is True

    upd = client.put(
        "/v1/users/device-abc/preferences",
        json={
            "notifications_enabled": False,
            "quiet_start_hour": 23,
            "quiet_end_hour": 7,
        },
    )
    assert upd.status_code == 200
    assert upd.json()["updated"] is True

    get_pref = client.get("/v1/users/device-abc/preferences")
    assert get_pref.status_code == 200
    payload = get_pref.json()
    assert payload["notifications_enabled"] is False
    assert payload["quiet_start_hour"] == 23


def test_user_channels_default_to_global_defaults():
    response = client.get("/v1/users/device-channels-default/channels")
    assert response.status_code == 200
    payload = response.json()
    assert payload == [
        {
            "id": "UCv5OAW45h67CJEY6kJLyisg",
            "handle": "@andrenavarroII",
            "title": "Andre Navarro II",
            "avatar_url": "https://yt3.googleusercontent.com/COXNzFPEO8BSI7Xrx1rAaYZlrD22Ku0iNv9_wlurCxdE_g8rx5xm2N2kgB_KiyYsQNG9d4WY8z4=s900-c-k-c0x00ffffff-no-rj",
            "is_tracked": True,
        }
    ]


def test_user_channels_can_be_updated_per_device():
    update = client.put(
        "/v1/users/device-channels-custom/channels",
        json={
            "channels": [
                {
                    "id": "channel-1",
                    "handle": "@channelone",
                    "title": "Channel One",
                    "is_tracked": True,
                },
                {
                    "id": "channel-2",
                    "handle": "@channeltwo",
                    "title": "Channel Two",
                    "is_tracked": False,
                },
            ]
        },
    )
    assert update.status_code == 200
    updated_payload = update.json()
    assert updated_payload == [
        {
            "id": "channel-1",
            "handle": "@channelone",
            "title": "Channel One",
            "is_tracked": True,
        },
        {
            "id": "channel-2",
            "handle": "@channeltwo",
            "title": "Channel Two",
            "is_tracked": False,
        },
    ]

    get_updated = client.get("/v1/users/device-channels-custom/channels")
    assert get_updated.status_code == 200
    assert get_updated.json() == updated_payload

    get_other_device = client.get("/v1/users/device-channels-other/channels")
    assert get_other_device.status_code == 200
    assert get_other_device.json()[0]["id"] == "UCv5OAW45h67CJEY6kJLyisg"


def test_samples_endpoint_preserves_stored_channel_metadata():
    main_mod.store.upsert_samples(
        [
            SampleItem(
                id="sample-metadata",
                youtube_video_id="yt-metadata",
                channel_id="channel-1",
                channel_title="Channel One",
                channel_handle="@channelone",
                channel_avatar_url="https://example.com/channel.jpg",
                title="Detailed sample",
                description_text="desc",
                published_at=datetime.now(timezone.utc),
                artwork_url="https://example.com/thumb.jpg",
                duration_seconds=91,
                genre_tags=[],
                tone_tags=[],
                is_saved=False,
                saved_at=None,
                download_state="not_downloaded",
                stream_state="idle",
            )
        ]
    )

    response = client.get("/v1/samples?limit=10&cursor=0")
    assert response.status_code == 200
    item = next(row for row in response.json()["items"] if row["id"] == "sample-metadata")
    assert item["channel_title"] == "Channel One"
    assert item["channel_handle"] == "@channelone"
    assert item["channel_avatar_url"] == "https://example.com/channel.jpg"
    assert item["duration_seconds"] == 91


def test_samples_endpoint_backfills_when_feed_is_sparse(monkeypatch):
    sample = SampleItem(
        id="sample-backfilled",
        youtube_video_id="yt-backfilled",
        channel_id="channel-1",
        title="Backfilled sample",
        description_text="desc",
        published_at=datetime.now(timezone.utc),
        genre_tags=[],
        tone_tags=[],
        is_saved=False,
        saved_at=None,
        download_state="not_downloaded",
        stream_state="idle",
    )

    class FakeStore:
        def __init__(self):
            self.items: list[SampleItem] = []

        def list_recent(self, limit=50, offset=0, since=None):
            _ = since
            return self.items[offset : offset + limit]

        def upsert_samples(self, samples):
            self.items.extend(samples)

    class FakePoller:
        async def backfill_all(self, channels, *, limit=333):
            _ = channels
            _ = limit
            fake_store.upsert_samples([sample])
            return BackfillResult(inserted_items=[sample], exhausted=False, channels_processed=1)

    fake_store = FakeStore()
    monkeypatch.setattr(main_mod, "store", fake_store)
    monkeypatch.setattr(main_mod, "poller", FakePoller())

    response = client.get("/v1/samples?limit=10&cursor=0")
    assert response.status_code == 200
    assert any(item["id"] == "sample-backfilled" for item in response.json()["items"])


def test_channel_catalog_parses_profile_metadata_from_html():
    html = """
    <script>
    {"channelMetadataRenderer":{"title":"Andre Navarro II"}}
    </script>
    <img src="https://yt3.googleusercontent.com/example-avatar=s900-c-k-c0x00ffffff-no-rj" />
    """

    title, avatar_url = ChannelCatalog._parse_channel_html(
        html,
        fallback_title="Fallback Channel",
        fallback_avatar_url=None,
    )

    assert title == "Andre Navarro II"
    assert avatar_url == "https://yt3.googleusercontent.com/example-avatar=s900-c-k-c0x00ffffff-no-rj"


def test_poll_once_reports_inserted_and_notifications(monkeypatch):
    class FakePoller:
        async def poll_all(self, channels):
            _ = channels
            return [
                SampleItem(
                    id="sample-abc",
                    youtube_video_id="abc",
                    channel_id="channel-1",
                    title="Fresh sample",
                    description_text="",
                    published_at=datetime.now(timezone.utc),
                    genre_tags=[],
                    tone_tags=[],
                    is_saved=False,
                    saved_at=None,
                    download_state="not_downloaded",
                    stream_state="idle",
                )
            ]

    class FakeDispatcher:
        def notify_new_samples(self, samples):
            return len(samples)

    monkeypatch.setattr(main_mod, "poller", FakePoller())
    monkeypatch.setattr(main_mod, "push_dispatcher", FakeDispatcher())

    response = client.post("/v1/poller/run-once")
    assert response.status_code == 200
    payload = response.json()
    assert payload["inserted"] == 1
    assert payload["notificationsSent"] == 1


def test_backfill_endpoint_uses_defaults_without_notifications(monkeypatch):
    class FakePoller:
        def __init__(self):
            self.limit = None

        async def backfill_all(self, channels, *, limit=333):
            self.limit = limit
            return BackfillResult(
                inserted_items=[
                    SampleItem(
                        id="sample-abc",
                        youtube_video_id="abc",
                        channel_id="channel-1",
                        title="Fresh sample",
                        description_text="",
                        published_at=datetime.now(timezone.utc),
                        genre_tags=[],
                        tone_tags=[],
                        is_saved=False,
                        saved_at=None,
                        download_state="not_downloaded",
                        stream_state="idle",
                    )
                ],
                exhausted=False,
                channels_processed=len(channels),
            )

    class FakeDispatcher:
        def notify_new_samples(self, samples):
            raise AssertionError("notifications should be suppressed by default")

    fake_poller = FakePoller()
    monkeypatch.setattr(main_mod, "poller", fake_poller)
    monkeypatch.setattr(main_mod, "push_dispatcher", FakeDispatcher())

    response = client.post("/v1/admin/poller/backfill")
    assert response.status_code == 200
    payload = response.json()
    assert fake_poller.limit == 333
    assert payload["inserted"] == 1
    assert payload["notifications_sent"] == 0
    assert payload["requested_limit"] == 333
    assert payload["exhausted"] is False
    assert payload["channels_processed"] == 1


def test_backfill_endpoint_can_send_notifications(monkeypatch):
    class FakePoller:
        async def backfill_all(self, channels, *, limit=333):
            _ = channels
            _ = limit
            return BackfillResult(
                inserted_items=[
                    SampleItem(
                        id="sample-abc",
                        youtube_video_id="abc",
                        channel_id="channel-1",
                        title="Fresh sample",
                        description_text="",
                        published_at=datetime.now(timezone.utc),
                        genre_tags=[],
                        tone_tags=[],
                        is_saved=False,
                        saved_at=None,
                        download_state="not_downloaded",
                        stream_state="idle",
                    )
                ],
                exhausted=True,
                channels_processed=1,
            )

    class FakeDispatcher:
        def notify_new_samples(self, samples):
            return len(samples)

    monkeypatch.setattr(main_mod, "poller", FakePoller())
    monkeypatch.setattr(main_mod, "push_dispatcher", FakeDispatcher())

    response = client.post(
        "/v1/admin/poller/backfill",
        json={"limit": 2, "send_notifications": True},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["inserted"] == 1
    assert payload["notifications_sent"] == 1
    assert payload["requested_limit"] == 2
    assert payload["exhausted"] is True
    assert payload["channels_processed"] == 1
