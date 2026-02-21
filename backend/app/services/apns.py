from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import httpx
import jwt


@dataclass
class APNSResult:
    delivered: bool
    status: str


class APNSClient:
    def __init__(
        self,
        *,
        enabled: bool,
        topic: str,
        key_id: str,
        team_id: str,
        private_key_path: str,
        use_sandbox: bool,
        http_client: httpx.Client | None = None,
    ):
        self.enabled = enabled
        self.topic = topic
        self.key_id = key_id
        self.team_id = team_id
        self.private_key_path = private_key_path
        self.use_sandbox = use_sandbox

        self._cached_token: str | None = None
        self._token_expires_at: datetime | None = None
        self._http_client = http_client or httpx.Client(http2=True, timeout=10)

    def send_new_sample(self, *, device_token: str, sample_id: str, title: str) -> APNSResult:
        if not self._is_configured():
            return APNSResult(delivered=False, status="skipped_unconfigured")

        token = self._auth_token()
        if not token:
            return APNSResult(delivered=False, status="auth_error")

        headers = {
            "authorization": f"bearer {token}",
            "apns-topic": self.topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        payload: dict[str, Any] = {
            "aps": {
                "alert": {
                    "title": "New sample available",
                    "body": title,
                },
                "sound": "default",
            },
            "sampleId": sample_id,
        }

        host = "https://api.sandbox.push.apple.com" if self.use_sandbox else "https://api.push.apple.com"
        url = f"{host}/3/device/{device_token}"

        try:
            response = self._http_client.post(url, headers=headers, json=payload)
        except httpx.HTTPError:
            return APNSResult(delivered=False, status="transport_error")

        if response.status_code == 200:
            return APNSResult(delivered=True, status="sent")

        return APNSResult(delivered=False, status=f"apns_{response.status_code}")

    def _is_configured(self) -> bool:
        if not self.enabled:
            return False

        if not self.topic or not self.key_id or not self.team_id or not self.private_key_path:
            return False

        return Path(self.private_key_path).exists()

    def _auth_token(self) -> str | None:
        now = datetime.now(timezone.utc)
        if self._cached_token and self._token_expires_at and now < self._token_expires_at:
            return self._cached_token

        key_path = Path(self.private_key_path)
        if not key_path.exists():
            return None

        private_key = key_path.read_text(encoding="utf-8")
        issued_at = int(now.timestamp())
        payload = {"iss": self.team_id, "iat": issued_at}
        headers = {"alg": "ES256", "kid": self.key_id}

        try:
            token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
        except Exception:
            return None

        self._cached_token = token
        self._token_expires_at = now + timedelta(minutes=50)
        return token
