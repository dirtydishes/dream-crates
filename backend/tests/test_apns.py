import httpx

from app.services.apns import APNSClient


def test_apns_client_returns_skipped_when_unconfigured():
    client = APNSClient(
        enabled=False,
        topic="com.example.app",
        key_id="",
        team_id="",
        private_key_path="",
        use_sandbox=True,
    )

    result = client.send_new_sample(device_token="token", sample_id="sample-1", title="hello")
    assert result.delivered is False
    assert result.status == "skipped_unconfigured"


def test_apns_client_handles_transport_error():
    transport = httpx.MockTransport(lambda request: (_ for _ in ()).throw(httpx.ConnectError("fail", request=request)))
    http_client = httpx.Client(transport=transport, http2=True)

    class TestableAPNSClient(APNSClient):
        def _is_configured(self) -> bool:  # noqa: PLR6301
            return True

        def _auth_token(self) -> str | None:  # noqa: PLR6301
            return "test-token"

    client = TestableAPNSClient(
        enabled=True,
        topic="com.example.app",
        key_id="kid",
        team_id="tid",
        private_key_path="/tmp/does-not-exist.p8",
        use_sandbox=True,
        http_client=http_client,
    )

    result = client.send_new_sample(device_token="token", sample_id="sample-1", title="hello")
    assert result.delivered is False
    assert result.status == "transport_error"
