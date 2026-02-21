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


class DeviceRegistrationRequest(BaseModel):
    device_id: str
    apns_token: str
    notifications_enabled: bool = True
    quiet_start_hour: int | None = Field(default=22, ge=0, le=23)
    quiet_end_hour: int | None = Field(default=8, ge=0, le=23)


class PreferencesUpdateRequest(BaseModel):
    notifications_enabled: bool = True
    quiet_start_hour: int | None = Field(default=22, ge=0, le=23)
    quiet_end_hour: int | None = Field(default=8, ge=0, le=23)
