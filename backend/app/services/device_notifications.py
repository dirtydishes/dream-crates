from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from app.services.store import SampleStore


@dataclass
class NotificationPreferences:
    notifications_enabled: bool
    quiet_start_hour: int | None
    quiet_end_hour: int | None


class DeviceNotificationService:
    def __init__(self, store: SampleStore):
        self.store = store

    def register_device(
        self,
        *,
        device_id: str,
        apns_token: str,
        notifications_enabled: bool,
        quiet_start_hour: int | None,
        quiet_end_hour: int | None,
    ) -> None:
        self.store.register_device(
            device_id=device_id,
            apns_token=apns_token,
            notifications_enabled=notifications_enabled,
            quiet_start_hour=quiet_start_hour,
            quiet_end_hour=quiet_end_hour,
        )

    def update_preferences(
        self,
        *,
        device_id: str,
        notifications_enabled: bool,
        quiet_start_hour: int | None,
        quiet_end_hour: int | None,
    ) -> None:
        self.store.update_preferences(
            device_id=device_id,
            notifications_enabled=notifications_enabled,
            quiet_start_hour=quiet_start_hour,
            quiet_end_hour=quiet_end_hour,
        )

    def get_preferences(self, *, device_id: str) -> NotificationPreferences:
        device = self.store.get_device(device_id)
        if device is None:
            return NotificationPreferences(
                notifications_enabled=True,
                quiet_start_hour=22,
                quiet_end_hour=8,
            )

        return NotificationPreferences(
            notifications_enabled=bool(device["notifications_enabled"]),
            quiet_start_hour=device["quiet_start_hour"],
            quiet_end_hour=device["quiet_end_hour"],
        )

    def update_apns_token(self, *, device_id: str, token_hex: str) -> None:
        device = self.store.get_device(device_id)
        if device is None:
            self.store.register_device(
                device_id=device_id,
                apns_token=token_hex,
                notifications_enabled=True,
                quiet_start_hour=22,
                quiet_end_hour=8,
            )
            return

        self.store.register_device(
            device_id=device_id,
            apns_token=token_hex,
            notifications_enabled=bool(device["notifications_enabled"]),
            quiet_start_hour=device["quiet_start_hour"],
            quiet_end_hour=device["quiet_end_hour"],
        )
