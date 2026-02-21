from datetime import datetime, timezone

from fastapi.testclient import TestClient

import app.main as main_mod
from app.models import SampleItem

app = main_mod.app
client = TestClient(app)


def test_download_prepare_returns_url():
    response = client.post("/v1/download/prepare", json={"sample_id": "sample-1"})
    assert response.status_code == 200
    payload = response.json()
    assert payload["sampleId"] == "sample-1"
    assert payload["downloadURL"].startswith("https://")


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
