from datetime import datetime, timezone

from app.models import SampleItem
from app.services.apns import APNSClient
from app.services.store import SampleStore


class PushDispatcher:
    def __init__(self, store: SampleStore, apns_client: APNSClient):
        self.store = store
        self.apns_client = apns_client

    def notify_new_samples(self, samples: list[SampleItem]) -> int:
        sent = 0
        devices = self.store.list_devices()
        now_hour = datetime.now(timezone.utc).hour

        for sample in samples:
            for device in devices:
                if not device["notifications_enabled"]:
                    continue

                if self._is_quiet_hours(
                    now_hour,
                    device["quiet_start_hour"],
                    device["quiet_end_hour"],
                ):
                    self.store.record_notification_event(
                        device_id=device["device_id"],
                        sample_id=sample.id,
                        title=sample.title,
                        status="suppressed_quiet_hours",
                    )
                    continue

                if not device["apns_token"]:
                    self.store.record_notification_event(
                        device_id=device["device_id"],
                        sample_id=sample.id,
                        title=sample.title,
                        status="skipped_missing_token",
                    )
                    continue

                apns_result = self.apns_client.send_new_sample(
                    device_token=device["apns_token"],
                    sample_id=sample.id,
                    title=sample.title,
                )
                self.store.record_notification_event(
                    device_id=device["device_id"],
                    sample_id=sample.id,
                    title=sample.title,
                    status=apns_result.status,
                )
                if apns_result.delivered:
                    sent += 1

        return sent

    @staticmethod
    def _is_quiet_hours(current_hour: int, start_hour: int | None, end_hour: int | None) -> bool:
        if start_hour is None or end_hour is None:
            return False

        if start_hour == end_hour:
            return False

        if start_hour < end_hour:
            return start_hour <= current_hour < end_hour

        return current_hour >= start_hour or current_hour < end_hour
