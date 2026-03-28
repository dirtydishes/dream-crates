from datetime import datetime, timezone

from fastapi.testclient import TestClient

import app.main as main_mod
from app.models import SampleItem

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
            "id": "UCs_1dV9bN0wQhQ_a9W8wO4Q",
            "handle": "@andrenavarroII",
            "title": "andrenavarroII",
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
    assert get_other_device.json()[0]["id"] == "UCs_1dV9bN0wQhQ_a9W8wO4Q"


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
