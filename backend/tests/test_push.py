from datetime import datetime, timezone

from app.models import SampleItem
from app.services.apns import APNSResult
from app.services.push import PushDispatcher
from app.services.store import SampleStore


class FakeAPNSClient:
    def __init__(self, delivered: bool = True, status: str = "sent"):
        self.delivered = delivered
        self.status = status

    def send_new_sample(self, *, device_token: str, sample_id: str, title: str) -> APNSResult:
        _ = (device_token, sample_id, title)
        return APNSResult(delivered=self.delivered, status=self.status)


def sample(sample_id: str) -> SampleItem:
    return SampleItem(
        id=sample_id,
        youtube_video_id=sample_id,
        channel_id="c1",
        title="Sample",
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


def test_push_dispatch_records_events(tmp_path):
    store = SampleStore(str(tmp_path / "test.db"))
    store.register_device(
        device_id="dev1",
        apns_token="token",
        notifications_enabled=True,
        quiet_start_hour=None,
        quiet_end_hour=None,
    )

    dispatcher = PushDispatcher(store, apns_client=FakeAPNSClient())
    sent = dispatcher.notify_new_samples([sample("sample-1")])

    assert sent == 1
    events = store.list_notification_events()
    assert len(events) == 1
    assert events[0]["status"] == "sent"


def test_push_dispatch_suppresses_during_quiet_hours(tmp_path):
    now_hour = datetime.now(timezone.utc).hour
    end_hour = (now_hour + 1) % 24

    store = SampleStore(str(tmp_path / "test.db"))
    store.register_device(
        device_id="dev1",
        apns_token="token",
        notifications_enabled=True,
        quiet_start_hour=now_hour,
        quiet_end_hour=end_hour,
    )

    dispatcher = PushDispatcher(store, apns_client=FakeAPNSClient())
    sent = dispatcher.notify_new_samples([sample("sample-2")])

    assert sent == 0
    events = store.list_notification_events()
    assert len(events) == 1
    assert events[0]["status"] == "suppressed_quiet_hours"
