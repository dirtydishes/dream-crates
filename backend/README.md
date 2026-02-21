# StudioSample Backend Scaffold

## Run locally

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
uvicorn app.main:app --reload
```

## Key endpoints (v1 scaffold)
- `GET /healthz`
- `GET /v1/channels/defaults`
- `GET /v1/samples`
- `POST /v1/poller/run-once`
- `GET /v1/tags/taxonomy`
- `GET /v1/users/{deviceId}/library`
- `PUT /v1/users/{deviceId}/library/{sampleId}?saved=true|false`
- `POST /v1/devices/register`
- `PUT /v1/users/{deviceId}/preferences`

## APNs configuration
Set these environment variables to enable live push delivery:
- `STUDIO_APNS_ENABLED=true`
- `STUDIO_APNS_TOPIC=com.your.bundle.id`
- `STUDIO_APNS_KEY_ID=<10-char-key-id>`
- `STUDIO_APNS_TEAM_ID=<apple-team-id>`
- `STUDIO_APNS_PRIVATE_KEY_PATH=/absolute/path/to/AuthKey_<KEYID>.p8`
- `STUDIO_APNS_USE_SANDBOX=true` (or `false` for production APNs)

When APNs is not configured, notification events are still recorded with `skipped_unconfigured` status for observability.
