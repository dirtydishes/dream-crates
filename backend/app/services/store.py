import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from app.models import Channel, SampleItem


class SampleStore:
    def __init__(self, db_path: str):
        self.db_path = db_path
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS samples (
                    id TEXT PRIMARY KEY,
                    youtube_video_id TEXT UNIQUE NOT NULL,
                    channel_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    description_text TEXT NOT NULL,
                    published_at TEXT NOT NULL,
                    artwork_url TEXT,
                    is_saved INTEGER NOT NULL DEFAULT 0,
                    saved_at TEXT,
                    download_state TEXT NOT NULL DEFAULT 'not_downloaded',
                    stream_state TEXT NOT NULL DEFAULT 'idle'
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS devices (
                    device_id TEXT PRIMARY KEY,
                    apns_token TEXT NOT NULL,
                    notifications_enabled INTEGER NOT NULL DEFAULT 1,
                    quiet_start_hour INTEGER,
                    quiet_end_hour INTEGER,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS notification_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id TEXT NOT NULL,
                    sample_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS device_channels (
                    device_id TEXT NOT NULL,
                    channel_id TEXT NOT NULL,
                    handle TEXT NOT NULL,
                    title TEXT NOT NULL,
                    is_tracked INTEGER NOT NULL DEFAULT 1,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (device_id, channel_id)
                )
                """
            )

    def existing_video_ids(self, channel_id: str) -> set[str]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT youtube_video_id FROM samples WHERE channel_id = ?",
                (channel_id,),
            ).fetchall()
            return {row[0] for row in rows}

    def upsert_samples(self, samples: list[SampleItem]) -> int:
        inserted = 0
        with self._connect() as conn:
            for sample in samples:
                result = conn.execute(
                    """
                    INSERT OR IGNORE INTO samples (
                        id, youtube_video_id, channel_id, title, description_text,
                        published_at, artwork_url, is_saved, saved_at, download_state, stream_state
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        sample.id,
                        sample.youtube_video_id,
                        sample.channel_id,
                        sample.title,
                        sample.description_text,
                        sample.published_at.isoformat(),
                        sample.artwork_url,
                        int(sample.is_saved),
                        sample.saved_at.isoformat() if sample.saved_at else None,
                        sample.download_state,
                        sample.stream_state,
                    ),
                )
                if result.rowcount:
                    inserted += 1
        return inserted

    def list_recent(
        self,
        *,
        limit: int = 50,
        offset: int = 0,
        since: datetime | None = None,
    ) -> list[SampleItem]:
        where_clause = ""
        values: list[object] = []
        if since is not None:
            where_clause = "WHERE published_at > ?"
            values.append(since.isoformat())
        values.extend([limit, offset])

        with self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT id, youtube_video_id, channel_id, title, description_text,
                       published_at, artwork_url, is_saved, saved_at,
                       download_state, stream_state
                FROM samples
                {where_clause}
                ORDER BY published_at DESC
                LIMIT ?
                OFFSET ?
                """,
                values,
            ).fetchall()

        result: list[SampleItem] = []
        for row in rows:
            result.append(
                SampleItem(
                    id=row["id"],
                    youtube_video_id=row["youtube_video_id"],
                    channel_id=row["channel_id"],
                    title=row["title"],
                    description_text=row["description_text"],
                    published_at=datetime.fromisoformat(row["published_at"]),
                    artwork_url=row["artwork_url"],
                    is_saved=bool(row["is_saved"]),
                    saved_at=datetime.fromisoformat(row["saved_at"]) if row["saved_at"] else None,
                    download_state=row["download_state"],
                    stream_state=row["stream_state"],
                )
            )
        return result

    def set_saved(self, sample_id: str, saved: bool) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE samples
                SET is_saved = ?, saved_at = ?
                WHERE id = ?
                """,
                (int(saved), datetime.now(timezone.utc).isoformat() if saved else None, sample_id),
            )

    def get_sample(self, sample_id: str) -> SampleItem | None:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT id, youtube_video_id, channel_id, title, description_text,
                       published_at, artwork_url, is_saved, saved_at,
                       download_state, stream_state
                FROM samples
                WHERE id = ?
                """,
                (sample_id,),
            ).fetchone()

        if row is None:
            return None

        return SampleItem(
            id=row["id"],
            youtube_video_id=row["youtube_video_id"],
            channel_id=row["channel_id"],
            title=row["title"],
            description_text=row["description_text"],
            published_at=datetime.fromisoformat(row["published_at"]),
            artwork_url=row["artwork_url"],
            is_saved=bool(row["is_saved"]),
            saved_at=datetime.fromisoformat(row["saved_at"]) if row["saved_at"] else None,
            download_state=row["download_state"],
            stream_state=row["stream_state"],
        )

    def register_device(
        self,
        *,
        device_id: str,
        apns_token: str,
        notifications_enabled: bool,
        quiet_start_hour: int | None,
        quiet_end_hour: int | None,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO devices (
                    device_id, apns_token, notifications_enabled,
                    quiet_start_hour, quiet_end_hour, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(device_id) DO UPDATE SET
                    apns_token=excluded.apns_token,
                    notifications_enabled=excluded.notifications_enabled,
                    quiet_start_hour=excluded.quiet_start_hour,
                    quiet_end_hour=excluded.quiet_end_hour,
                    updated_at=excluded.updated_at
                """,
                (
                    device_id,
                    apns_token,
                    int(notifications_enabled),
                    quiet_start_hour,
                    quiet_end_hour,
                    datetime.now(timezone.utc).isoformat(),
                ),
            )

    def update_preferences(
        self,
        *,
        device_id: str,
        notifications_enabled: bool,
        quiet_start_hour: int | None,
        quiet_end_hour: int | None,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE devices
                SET notifications_enabled = ?,
                    quiet_start_hour = ?,
                    quiet_end_hour = ?,
                    updated_at = ?
                WHERE device_id = ?
                """,
                (
                    int(notifications_enabled),
                    quiet_start_hour,
                    quiet_end_hour,
                    datetime.now(timezone.utc).isoformat(),
                    device_id,
                ),
            )

    def list_devices(self) -> list[sqlite3.Row]:
        with self._connect() as conn:
            return conn.execute(
                """
                SELECT device_id, apns_token, notifications_enabled,
                       quiet_start_hour, quiet_end_hour
                FROM devices
                """
            ).fetchall()

    def get_device(self, device_id: str) -> sqlite3.Row | None:
        with self._connect() as conn:
            return conn.execute(
                """
                SELECT device_id, apns_token, notifications_enabled,
                       quiet_start_hour, quiet_end_hour
                FROM devices
                WHERE device_id = ?
                """,
                (device_id,),
            ).fetchone()

    def list_device_channels(self, *, device_id: str, default_channels: list[Channel]) -> list[Channel]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT channel_id, handle, title, is_tracked
                FROM device_channels
                WHERE device_id = ?
                ORDER BY rowid ASC
                """,
                (device_id,),
            ).fetchall()

        if not rows:
            return [
                Channel(
                    id=channel.id,
                    handle=channel.handle,
                    title=channel.title,
                    is_tracked=channel.is_tracked,
                )
                for channel in default_channels
            ]

        return [
            Channel(
                id=row["channel_id"],
                handle=row["handle"],
                title=row["title"],
                is_tracked=bool(row["is_tracked"]),
            )
            for row in rows
        ]

    def replace_device_channels(self, *, device_id: str, channels: list[Channel]) -> None:
        updated_at = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute(
                "DELETE FROM device_channels WHERE device_id = ?",
                (device_id,),
            )
            for channel in channels:
                conn.execute(
                    """
                    INSERT INTO device_channels (
                        device_id, channel_id, handle, title, is_tracked, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (
                        device_id,
                        channel.id,
                        channel.handle,
                        channel.title,
                        int(channel.is_tracked),
                        updated_at,
                    ),
                )

    def record_notification_event(self, *, device_id: str, sample_id: str, title: str, status: str) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO notification_events (device_id, sample_id, title, status, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (device_id, sample_id, title, status, datetime.now(timezone.utc).isoformat()),
            )

    def list_notification_events(self) -> list[sqlite3.Row]:
        with self._connect() as conn:
            return conn.execute(
                """
                SELECT id, device_id, sample_id, title, status, created_at
                FROM notification_events
                ORDER BY id ASC
                """
            ).fetchall()
