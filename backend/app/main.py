from datetime import datetime

from fastapi import FastAPI, HTTPException

from app.config import settings
from app.models import (
    Channel,
    DeviceRegistrationRequest,
    DownloadPrepareRequest,
    PlaybackResolveRequest,
    PreferencesUpdateRequest,
)
from app.services.apns import APNSClient
from app.services.push import PushDispatcher
from app.services.store import SampleStore
from app.services.tagging import RulesTagger
from app.services.youtube_poller import YouTubePoller

app = FastAPI(title="StudioSample Backend", version="0.1.0")
store = SampleStore(settings.storage_path)
tagger = RulesTagger()
poller = YouTubePoller(
    api_key=settings.youtube_api_key,
    base_url=settings.youtube_base_url,
    store=store,
    tagger=tagger,
)
apns_client = APNSClient(
    enabled=settings.apns_enabled,
    topic=settings.apns_topic,
    key_id=settings.apns_key_id,
    team_id=settings.apns_team_id,
    private_key_path=settings.apns_private_key_path,
    use_sandbox=settings.apns_use_sandbox,
)
push_dispatcher = PushDispatcher(store=store, apns_client=apns_client)

DEFAULT_CHANNELS: list[Channel] = [
    Channel(id="UCs_1dV9bN0wQhQ_a9W8wO4Q", handle="@andrenavarroII", title="andrenavarroII", is_tracked=True),
]


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/channels/defaults")
async def channels_defaults() -> list[Channel]:
    return DEFAULT_CHANNELS


@app.get("/v1/samples")
async def samples(limit: int = 50, cursor: int = 0, since: str | None = None):
    safe_limit = max(1, min(limit, 100))
    safe_cursor = max(0, cursor)
    since_value = datetime.fromisoformat(since) if since else None
    items = store.list_recent(limit=safe_limit, offset=safe_cursor, since=since_value)
    next_cursor = safe_cursor + len(items) if len(items) == safe_limit else None
    return {"items": items, "nextCursor": next_cursor}


@app.post("/v1/poller/run-once")
async def poll_once() -> dict[str, int]:
    inserted_items = await poller.poll_all(DEFAULT_CHANNELS)
    notifications_sent = push_dispatcher.notify_new_samples(inserted_items)
    return {
        "inserted": len(inserted_items),
        "notificationsSent": notifications_sent,
    }


@app.get("/v1/tags/taxonomy")
async def tags_taxonomy() -> dict[str, list[str]]:
    return tagger.taxonomy()


@app.get("/v1/users/{device_id}/library")
async def get_library(device_id: str, limit: int = 50):
    _ = device_id
    return [sample for sample in store.list_recent(limit=limit, offset=0) if sample.is_saved]


@app.put("/v1/users/{device_id}/library/{sample_id}")
async def put_library(device_id: str, sample_id: str, saved: bool = True):
    _ = device_id
    store.set_saved(sample_id, saved)
    return {"sampleId": sample_id, "saved": saved}


@app.post("/v1/playback/resolve")
async def resolve_playback(body: PlaybackResolveRequest):
    raise HTTPException(
        status_code=501,
        detail=f"Resolver not implemented yet for {body.sample_id}; tracked under task T6/T7",
    )


@app.post("/v1/download/prepare")
async def prepare_download(body: DownloadPrepareRequest):
    return {
        "sampleId": body.sample_id,
        "downloadURL": "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
    }


@app.post("/v1/devices/register")
async def register_device(body: DeviceRegistrationRequest):
    store.register_device(
        device_id=body.device_id,
        apns_token=body.apns_token,
        notifications_enabled=body.notifications_enabled,
        quiet_start_hour=body.quiet_start_hour,
        quiet_end_hour=body.quiet_end_hour,
    )
    return {"registered": True, "deviceId": body.device_id}


@app.put("/v1/users/{device_id}/preferences")
async def update_preferences(device_id: str, body: PreferencesUpdateRequest):
    store.update_preferences(
        device_id=device_id,
        notifications_enabled=body.notifications_enabled,
        quiet_start_hour=body.quiet_start_hour,
        quiet_end_hour=body.quiet_end_hour,
    )
    return {"updated": True, "deviceId": device_id}
