from datetime import datetime
from pydantic import BaseModel, Field


class Channel(BaseModel):
    id: str
    handle: str
    title: str
    is_tracked: bool = True


class TagScore(BaseModel):
    key: str
    confidence: float = Field(ge=0.0, le=1.0)


class SampleItem(BaseModel):
    id: str
    youtube_video_id: str
    channel_id: str
    title: str
    description_text: str
    published_at: datetime
    artwork_url: str | None = None
    duration_seconds: int | None = None
    genre_tags: list[TagScore] = Field(default_factory=list)
    tone_tags: list[TagScore] = Field(default_factory=list)
    is_saved: bool = False
    saved_at: datetime | None = None
    download_state: str = "not_downloaded"
    stream_state: str = "idle"


class PlaybackResolveRequest(BaseModel):
    sample_id: str


class DownloadPrepareRequest(BaseModel):
    sample_id: str


class PlaybackResolveResponse(BaseModel):
    sample_id: str
    playback_url: str
    expires_at: datetime
    source: str


class DownloadPrepareResponse(BaseModel):
    sample_id: str
    download_url: str
    expires_at: datetime
    source: str


class BackfillRequest(BaseModel):
    limit: int = Field(default=333, ge=1)
    send_notifications: bool = False


class BackfillResponse(BaseModel):
    inserted: int
    notifications_sent: int
    requested_limit: int
    exhausted: bool
    channels_processed: int


class DeviceRegistrationRequest(BaseModel):
    device_id: str
    apns_token: str = ""
    notifications_enabled: bool = True
    quiet_start_hour: int | None = Field(default=22, ge=0, le=23)
    quiet_end_hour: int | None = Field(default=8, ge=0, le=23)


class ChannelsUpdateRequest(BaseModel):
    channels: list[Channel] = Field(default_factory=list)


class PreferencesUpdateRequest(BaseModel):
    notifications_enabled: bool = True
    quiet_start_hour: int | None = Field(default=22, ge=0, le=23)
    quiet_end_hour: int | None = Field(default=8, ge=0, le=23)


class DevicePreferencesResponse(BaseModel):
    device_id: str
    notifications_enabled: bool
    quiet_start_hour: int | None
    quiet_end_hour: int | None
