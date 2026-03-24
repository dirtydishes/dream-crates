from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    youtube_api_key: str = ""
    youtube_base_url: str = "https://www.googleapis.com/youtube/v3"
    storage_path: str = "data/studiosample.db"
    apns_enabled: bool = False
    apns_topic: str = "com.dreamcrates.studiosample"
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_private_key_path: str = ""
    apns_use_sandbox: bool = True
    resolver_command: str = ""
    resolver_fallback_url: str = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
    resolver_ttl_seconds: int = 3600

    model_config = SettingsConfigDict(env_prefix="STUDIO_", env_file=".env", extra="ignore")


settings = Settings()
