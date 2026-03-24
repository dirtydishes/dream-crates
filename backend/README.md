# Dream Crates Backend

## Run locally

```bash
cd /Users/kell/dev/dream-crates/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
uvicorn app.main:app --reload
```

## Environment setup
Copy `.env.example` to `.env` and fill secrets:

```bash
cd /Users/kell/dev/dream-crates/backend
cp .env.example .env
```

## Tests

```bash
cd /Users/kell/dev/dream-crates/backend
./scripts/run-tests.sh
```

## Key endpoints (v1 scaffold)
- `GET /healthz`
- `GET /v1/channels/defaults`
- `GET /v1/samples`
- `POST /v1/poller/run-once`
- `GET /v1/tags/taxonomy`
- `GET /v1/users/{deviceId}/library`
- `PUT /v1/users/{deviceId}/library/{sampleId}?saved=true|false`
- `GET /v1/users/{deviceId}/preferences`
- `POST /v1/devices/register`
- `PUT /v1/users/{deviceId}/preferences`
- `POST /v1/playback/resolve`
- `POST /v1/download/prepare`

## APNs configuration
Set these environment variables to enable live push delivery:
- `STUDIO_APNS_ENABLED=true`
- `STUDIO_APNS_TOPIC=com.your.bundle.id`
- `STUDIO_APNS_KEY_ID=<10-char-key-id>`
- `STUDIO_APNS_TEAM_ID=<apple-team-id>`
- `STUDIO_APNS_PRIVATE_KEY_PATH=/absolute/path/to/AuthKey_<KEYID>.p8`
- `STUDIO_APNS_USE_SANDBOX=true` (or `false` for production APNs)

When APNs is not configured, notification events are still recorded with `skipped_unconfigured` status for observability.

## Playback Resolver
Resolution can use either:

- `STUDIO_RESOLVER_COMMAND`: command that prints JSON containing `url`, optional `expiresAt`, and optional `source`
- `STUDIO_RESOLVER_FALLBACK_URL`: static fallback URL if command resolution is disabled or fails
- `STUDIO_RESOLVER_TTL_SECONDS`: default expiry when the resolver does not provide one

The command template supports `{video_id}`, `{sample_id}`, and `{mode}` placeholders.

## Testing Policy
Use `/Users/kell/dev/dream-crates/testing.md` for device-first testing guidance.
