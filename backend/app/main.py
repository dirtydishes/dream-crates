from datetime import datetime, timedelta, timezone
import logging

import httpx
from fastapi import Body, FastAPI, HTTPException, Request, Response
from starlette.background import BackgroundTask
from starlette.responses import StreamingResponse

from app.config import settings
from app.models import (
    BackfillRequest,
    BackfillResponse,
    Channel,
    ChannelsUpdateRequest,
    DevicePreferencesResponse,
    DeviceRegistrationRequest,
    DownloadPrepareResponse,
    DownloadPrepareRequest,
    PlaybackResolveResponse,
    PlaybackResolveRequest,
    PreferencesUpdateRequest,
)
from app.services.device_notifications import DeviceNotificationService
from app.services.apns import APNSClient
from app.services.channel_catalog import ChannelCatalog
from app.services.push import PushDispatcher
from app.services.resolver import PlaybackResolver
from app.services.store import SampleStore
from app.services.tagging import RulesTagger
from app.services.youtube_poller import YouTubePoller

logger = logging.getLogger(__name__)

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
notification_service = DeviceNotificationService(store=store)
resolver = PlaybackResolver(
    command_template=settings.resolver_command,
    fallback_url=settings.resolver_fallback_url,
    ttl_seconds=settings.resolver_ttl_seconds,
)

DEFAULT_CHANNELS: list[Channel] = [
    Channel(
        id="UCv5OAW45h67CJEY6kJLyisg",
        handle="@andrenavarroII",
        title="Andre Navarro II",
        avatar_url="https://yt3.googleusercontent.com/COXNzFPEO8BSI7Xrx1rAaYZlrD22Ku0iNv9_wlurCxdE_g8rx5xm2N2kgB_KiyYsQNG9d4WY8z4=s900-c-k-c0x00ffffff-no-rj",
        is_tracked=True,
    ),
]
channel_catalog = ChannelCatalog(
    api_key=settings.youtube_api_key,
    base_url=settings.youtube_base_url,
    defaults=DEFAULT_CHANNELS,
)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/channels/defaults", response_model=list[Channel], response_model_exclude_none=True)
async def channels_defaults() -> list[Channel]:
    return await channel_catalog.default_channels()


@app.get("/v1/users/{device_id}/channels", response_model=list[Channel], response_model_exclude_none=True)
async def get_user_channels(device_id: str):
    return store.list_device_channels(device_id=device_id, default_channels=DEFAULT_CHANNELS)


@app.put("/v1/users/{device_id}/channels", response_model=list[Channel], response_model_exclude_none=True)
async def put_user_channels(device_id: str, body: ChannelsUpdateRequest):
    store.replace_device_channels(device_id=device_id, channels=body.channels)
    return store.list_device_channels(device_id=device_id, default_channels=DEFAULT_CHANNELS)


@app.get("/v1/samples")
async def samples(limit: int = 50, cursor: int = 0, since: str | None = None):
    safe_limit = max(1, min(limit, 100))
    safe_cursor = max(0, cursor)
    since_value = datetime.fromisoformat(since) if since else None
    items = store.list_recent(limit=safe_limit, offset=safe_cursor, since=since_value)
    if safe_cursor == 0 and len(items) <= 1:
        try:
            result = await poller.backfill_all(DEFAULT_CHANNELS, limit=max(333, safe_limit))
            if result.inserted_items:
                items = store.list_recent(limit=safe_limit, offset=safe_cursor, since=since_value)
        except Exception:
            logger.exception("Auto-backfill failed while serving /v1/samples")
    items = await channel_catalog.decorate_samples(items)
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


@app.post("/v1/admin/poller/backfill", response_model=BackfillResponse)
async def backfill_poll(body: BackfillRequest = Body(default_factory=BackfillRequest)):
    result = await poller.backfill_all(DEFAULT_CHANNELS, limit=body.limit)
    notifications_sent = push_dispatcher.notify_new_samples(result.inserted_items) if body.send_notifications else 0
    return BackfillResponse(
        inserted=len(result.inserted_items),
        notifications_sent=notifications_sent,
        requested_limit=body.limit,
        exhausted=result.exhausted,
        channels_processed=result.channels_processed,
    )


@app.get("/v1/tags/taxonomy")
async def tags_taxonomy() -> dict[str, list[str]]:
    return tagger.taxonomy()


@app.get("/v1/users/{device_id}/library")
async def get_library(device_id: str, limit: int = 50):
    _ = device_id
    saved = [sample for sample in store.list_recent(limit=limit, offset=0) if sample.is_saved]
    return await channel_catalog.decorate_samples(saved)


@app.put("/v1/users/{device_id}/library/{sample_id}")
async def put_library(device_id: str, sample_id: str, saved: bool = True):
    _ = device_id
    store.set_saved(sample_id, saved)
    return {"sampleId": sample_id, "saved": saved}


@app.post("/v1/playback/resolve", response_model=PlaybackResolveResponse)
async def resolve_playback(request: Request, body: PlaybackResolveRequest):
    sample = store.get_sample(body.sample_id)
    if sample is None:
        raise HTTPException(status_code=404, detail=f"Unknown sample: {body.sample_id}")

    return PlaybackResolveResponse(
        sample_id=body.sample_id,
        playback_url=_public_url_for(request, "media_proxy", sample_id=body.sample_id, mode="stream"),
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=settings.resolver_ttl_seconds),
        source="backend-proxy",
    )


@app.post("/v1/download/prepare", response_model=DownloadPrepareResponse)
async def prepare_download(request: Request, body: DownloadPrepareRequest):
    sample = store.get_sample(body.sample_id)
    if sample is None:
        raise HTTPException(status_code=404, detail=f"Unknown sample: {body.sample_id}")

    return DownloadPrepareResponse(
        sample_id=body.sample_id,
        download_url=_public_url_for(request, "media_proxy", sample_id=body.sample_id, mode="download"),
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=settings.resolver_ttl_seconds),
        source="backend-proxy",
    )


@app.api_route("/v1/media/{sample_id}/{mode}", methods=["GET", "HEAD"], name="media_proxy")
async def media_proxy(sample_id: str, mode: str, request: Request):
    sample = store.get_sample(sample_id)
    if sample is None:
        raise HTTPException(status_code=404, detail=f"Unknown sample: {sample_id}")

    if mode == "stream":
        resolved = resolver.resolve_stream(sample)
    elif mode == "download":
        resolved = resolver.resolve_download(sample)
    else:
        raise HTTPException(status_code=404, detail=f"Unsupported media mode: {mode}")

    request_headers = dict(resolved.headers)
    for header_name in ("range", "if-range"):
        header_value = request.headers.get(header_name)
        if header_value:
            request_headers[header_name] = header_value

    client = httpx.AsyncClient(
        follow_redirects=True,
        timeout=httpx.Timeout(connect=10.0, read=None, write=30.0, pool=30.0),
    )
    upstream_request = client.build_request(request.method, resolved.url, headers=request_headers)
    try:
        upstream_response = await client.send(upstream_request, stream=True)
    except httpx.HTTPError as exc:
        await client.aclose()
        logger.exception("Media proxy failed for %s (%s)", sample_id, mode)
        raise HTTPException(status_code=502, detail="Unable to fetch upstream media") from exc

    proxy_headers = _filter_proxy_headers(upstream_response.headers)
    if mode == "download" and "content-disposition" not in {name.lower() for name in proxy_headers}:
        proxy_headers["Content-Disposition"] = f'attachment; filename="{sample_id}.m4a"'

    cleanup = BackgroundTask(_close_upstream_response, upstream_response, client)
    if request.method == "HEAD":
        return Response(status_code=upstream_response.status_code, headers=proxy_headers, background=cleanup)

    return StreamingResponse(
        upstream_response.aiter_bytes(),
        status_code=upstream_response.status_code,
        headers=proxy_headers,
        background=cleanup,
    )


@app.post("/v1/devices/register")
async def register_device(body: DeviceRegistrationRequest):
    notification_service.register_device(
        device_id=body.device_id,
        apns_token=body.apns_token,
        notifications_enabled=body.notifications_enabled,
        quiet_start_hour=body.quiet_start_hour,
        quiet_end_hour=body.quiet_end_hour,
    )
    return {"registered": True, "deviceId": body.device_id}


@app.get("/v1/users/{device_id}/preferences", response_model=DevicePreferencesResponse)
async def get_preferences(device_id: str):
    preferences = notification_service.get_preferences(device_id=device_id)
    return DevicePreferencesResponse(
        device_id=device_id,
        notifications_enabled=preferences.notifications_enabled,
        quiet_start_hour=preferences.quiet_start_hour,
        quiet_end_hour=preferences.quiet_end_hour,
    )


@app.put("/v1/users/{device_id}/preferences")
async def update_preferences(device_id: str, body: PreferencesUpdateRequest):
    notification_service.update_preferences(
        device_id=device_id,
        notifications_enabled=body.notifications_enabled,
        quiet_start_hour=body.quiet_start_hour,
        quiet_end_hour=body.quiet_end_hour,
    )
    return {"updated": True, "deviceId": device_id}


async def _close_upstream_response(upstream_response: httpx.Response, client: httpx.AsyncClient) -> None:
    await upstream_response.aclose()
    await client.aclose()


def _filter_proxy_headers(headers: httpx.Headers) -> dict[str, str]:
    hop_by_hop = {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    }
    return {
        key: value
        for key, value in headers.items()
        if key.lower() not in hop_by_hop
    }


def _public_url_for(request: Request, route_name: str, **path_params: str) -> str:
    url = request.url_for(route_name, **path_params)
    scheme = request.headers.get("x-forwarded-proto") or request.url.scheme
    host = request.headers.get("x-forwarded-host") or request.headers.get("host")
    if host:
        url = url.replace(scheme=scheme, netloc=host)
    elif scheme != url.scheme:
        url = url.replace(scheme=scheme)
    return str(url)
