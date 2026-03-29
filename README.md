# Dream Crates

```text
           .-~~~~-.         .-~~~~-.         .-~~~~-.
        .-(   dream )-. .-(   crates )-. .-(   drift )-.
       (   ~  ~   ~   )(   ~   ~~   ~  )(   ~   ~   ~   )
        '-._________.-' '-.__________.-' '-.__________.-'
             \   \            /   /             /   /
          .-~~~~~~~~~~~~~~~~~~~~~~~~ dream crates ~~~~~~~~~~~~~~~~-.
        .(     soft stacks of samples floating through the cloud    ).
          '-~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~-'
```

Dream Crates is an internal iPhone app and FastAPI backend for discovering freshly uploaded YouTube samples from curated channels, tagging them, surfacing them in a feed, and playing or saving them in a studio-style listening flow.

The repo currently contains a working vertical slice:

- A SwiftUI iOS app with `Feed`, `Player`, `Library`, and `Settings` tabs
- A FastAPI backend with sample ingestion, tagging, library state, playback/download resolution, and notification preference endpoints
- Debian deployment assets for a single-node server using `systemd` and `nginx`
- Docker deployment assets for a containerized backend with `yt-dlp` and `ffmpeg`
- Device-first testing scripts and lightweight local smoke checks

## Status at a glance

### Implemented now

- YouTube polling for tracked channels via the YouTube Data API
- SQLite-backed storage for samples, device registrations, and notification events
- Rule-based genre and tone tagging during ingestion
- Feed API with pagination and optional `since` filtering
- Save/unsave flow backed by the backend library API
- Local iOS persistence for saved-state changes when offline
- Local offline file storage and relaunch restoration for downloaded files
- Player UI with spinning-record animation, pause deceleration, background audio, remote commands, and playback speed control
- Notification preference syncing plus APNs registration and push dispatch scaffolding
- Fallback and command-based playback/download URL resolution
- Debian deployment templates for API + recurring poller

### Partially implemented / still missing

- Tracked-channel management beyond the hard-coded default channel list
- A production resolver that consistently returns real stream/download URLs
- End-to-end validation of APNs delivery from device to server to push receipt
- iOS handling for incoming push notifications inside the app experience
- Durable backend-managed download preparation beyond the shared fallback URL path
- More complete integration coverage across iOS + backend together

## Repo layout

- `ios/StudioSample`: SwiftUI iPhone app
- `backend`: FastAPI service, SQLite store, ingestion, tagging, push, resolver logic, tests
- `deploy/debian`: Debian deployment templates, env example, `systemd` units, `nginx` config
- `deploy/docker`: Docker deployment templates and environment examples
- `docker-compose.yml`: local or server container orchestration for API + poller
- `scripts`: top-level environment and API smoke scripts
- `testing.md`: device-first testing policy
- `PLAN.md`: product plan, milestones, acceptance criteria, and risks

## Architecture

```text
+------------------ iOS App (SwiftUI) ------------------+
| Feed tab       -> fetch recent samples                |
| Player tab     -> play local/offline or resolved URL  |
| Library tab    -> saved samples + offline downloads   |
| Settings tab   -> notifications + quiet hours         |
|                                                        |
| Local persistence:                                    |
| - saved-state sync queue                              |
| - playback speed                                      |
| - APNs token + notification prefs                     |
| - offline downloaded MP3 files                        |
+-----------------------+--------------------------------+
                        |
                        | REST
                        v
+------------------ Backend (FastAPI) -------------------+
| /v1/samples                                          |
| /v1/users/{deviceId}/library                         |
| /v1/playback/resolve                                 |
| /v1/download/prepare                                 |
| /v1/devices/register                                 |
| /v1/users/{deviceId}/preferences                     |
| /v1/poller/run-once                                  |
|                                                      |
| Services: YouTube poller, rules tagger, resolver,    |
| device registration, APNs dispatcher, SQLite store   |
+-----------------------+--------------------------------+
                        |
                        v
+---------------- External Services ---------------------+
| YouTube Data API                                      |
| Optional APNs                                          |
| Optional external command-based resolver              |
+--------------------------------------------------------+
```

## Current implementation details

### iOS app

The app is generated with XcodeGen from `ios/StudioSample/project.yml` and targets iOS 17.

Current iOS behavior includes:

- `Feed`: loads recent samples from the backend, falls back to local mock data if the API is unavailable, supports pull-to-refresh, and lets the user save/unsave items
- `Player`: plays the currently selected sample, animates a rotating record while playing, decelerates on pause, supports playback speed from `0.5x` to `2.0x`, and configures lock-screen / remote control playback commands
- `Library`: shows saved samples ordered by most-recently-saved and allows downloading files for offline playback
- `Settings`: stores notification preferences locally, syncs them to the backend, and can request APNs permission + device registration

Local persistence on iOS currently covers:

- Saved state with pending/synced tracking so offline save changes can survive relaunches
- Playback speed preference via `UserDefaults`
- Notification preference toggles and APNs token via `UserDefaults`
- Downloaded MP3 files in Application Support under `DreamCratesDownloads`

Important current limitation:

- The app is still hard-coded to use `http://127.0.0.1:8000` as its backend base URL, so real device usage against a remote server still requires changing that value in the app code or introducing configuration

### Backend

The backend is a FastAPI app in `backend/app/main.py` with a SQLite store under `STUDIO_STORAGE_PATH`.

Current backend behavior includes:

- Polling the YouTube Data API for recent uploads from tracked channels
- Deduplicating by `youtube_video_id`
- Creating sample records with title, description, publication time, artwork URL, and inferred genre/tone tags
- Persisting saved-library state per sample
- Registering devices with APNs tokens and quiet-hour preferences
- Resolving playback and download URLs through either:
  - `STUDIO_RESOLVER_COMMAND`
  - or `STUDIO_RESOLVER_FALLBACK_URL`
- Recording notification delivery attempts and skip reasons

Current storage tables:

- `samples`
- `devices`
- `notification_events`

Current default tracked channel list:

- `@andrenavarroII` (`UCs_1dV9bN0wQhQ_a9W8wO4Q`)

### Tagging

The tagger is currently rule-based, not ML-based. It scans sample titles and descriptions for keyword matches and assigns normalized confidence scores.

Genre taxonomy currently includes:

- `ambient`
- `boom_bap`
- `cinematic`
- `drill`
- `house`
- `lo_fi`
- `phonk`
- `rnb`
- `techno`
- `trap`

Tone taxonomy currently includes:

- `aggressive`
- `dark`
- `dreamy`
- `eerie`
- `glossy`
- `gritty`
- `melancholic`
- `nostalgic`
- `uplifting`
- `warm`

## API surface

Current top-level endpoints:

- `GET /healthz`
- `GET /v1/channels/defaults`
- `GET /v1/samples`
- `POST /v1/admin/poller/backfill`
- `POST /v1/poller/run-once`
- `GET /v1/tags/taxonomy`
- `GET /v1/users/{device_id}/library`
- `PUT /v1/users/{device_id}/library/{sample_id}?saved=true|false`
- `POST /v1/playback/resolve`
- `POST /v1/download/prepare`
- `POST /v1/devices/register`
- `GET /v1/users/{device_id}/preferences`
- `PUT /v1/users/{device_id}/preferences`

Notable endpoint behavior:

- `GET /v1/samples` supports `limit`, `cursor`, and optional ISO-8601 `since`
- `POST /v1/admin/poller/backfill` backfills up to `limit` historical uploads across tracked channels and suppresses notifications unless `send_notifications=true`
- `POST /v1/poller/run-once` both ingests new uploads and attempts notifications
- Playback/download prepare endpoints return URLs plus `expires_at` and `source`
- Library operations are device-scoped at the API layer, but the current backend storage model tracks saved state directly on the sample row

## Local development

### Prerequisites

- `python3`
- `bd`
- `xcodebuild`
- `xcodegen`
- `xcrun`

Quick environment check:

```bash
./scripts/doctor.sh
```

### Backend quickstart

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
cp .env.example .env
uvicorn app.main:app --reload
```

### Backend (Docker + yt-dlp)

```bash
cd /Users/kell/Cloud/dev/dream-crates
cp deploy/docker/dream-crates.env.example deploy/docker/dream-crates.env
docker compose up --build -d
```

Default local backend URL:

```text
http://127.0.0.1:8000
```

Run backend tests:
```bash
cd backend
./scripts/run-tests.sh
```

Run API smoke checks against a running backend:

```bash
./scripts/api-smoke.sh
```

Container notes:

- The Docker image includes `yt-dlp` and `ffmpeg`
- `deploy/docker/dream-crates.env.example` prewires the resolver command to use `backend/scripts/resolve_media_url.py`
- Detailed container deployment notes live in `deploy/docker/README.md`

### iOS quickstart

```bash
cd ios/StudioSample
xcodegen generate
xcodebuild -project 'dream crates.xcodeproj' -scheme StudioSampleApp -destination 'generic/platform=iOS' build
```

Useful iOS commands:

```bash
cd ios/StudioSample
./scripts/list-destinations.sh
./scripts/test-device.sh
DEVICE_NAME=kellcd ./scripts/install-device.sh
DEVICE_NAME='spacepad air' ./scripts/install-device.sh
DESTINATION_ID=<simulator-id> ./scripts/test-simulator.sh
```

## Environment configuration

The backend reads `STUDIO_*` variables from `backend/.env`.

### Required or commonly used values

```bash
# YouTube ingestion
STUDIO_YOUTUBE_API_KEY=
STUDIO_YOUTUBE_BASE_URL=https://www.googleapis.com/youtube/v3

# Storage
STUDIO_STORAGE_PATH=data/studiosample.db

# APNs push
STUDIO_APNS_ENABLED=false
STUDIO_APNS_TOPIC=com.dreamcrates.studiosample
STUDIO_APNS_KEY_ID=
STUDIO_APNS_TEAM_ID=
STUDIO_APNS_PRIVATE_KEY_PATH=
STUDIO_APNS_USE_SANDBOX=true

# Playback/download resolver
STUDIO_RESOLVER_COMMAND=
STUDIO_RESOLVER_FALLBACK_URL=https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3
STUDIO_RESOLVER_TTL_SECONDS=3600
```

### Resolver contract

If `STUDIO_RESOLVER_COMMAND` is set, it is treated as a shell command template with these placeholders:

- `{video_id}`
- `{sample_id}`
- `{mode}`

The command must print JSON like:

```json
{"url":"https://example.com/audio.mp3","expiresAt":"2026-01-01T00:00:00Z","source":"command"}
```

If the command is missing, fails, or returns invalid data, the backend falls back to `STUDIO_RESOLVER_FALLBACK_URL`.

### APNs notes

Live APNs delivery requires:

- `STUDIO_APNS_ENABLED=true`
- valid `STUDIO_APNS_TOPIC`
- valid `STUDIO_APNS_KEY_ID`
- valid `STUDIO_APNS_TEAM_ID`
- valid `STUDIO_APNS_PRIVATE_KEY_PATH`

When APNs is not fully configured, the backend still records notification events with statuses like:

- `skipped_unconfigured`
- `skipped_missing_token`
- `suppressed_quiet_hours`

## Deployment

The repo includes both:

- a Debian single-node deployment layout under `deploy/debian`
- a Docker deployment path under `deploy/docker` plus `docker-compose.yml`

### Docker quick start

```bash
cp deploy/docker/dream-crates.env.example deploy/docker/dream-crates.env
docker compose up --build -d
```

The Docker image bundles `yt-dlp` and `ffmpeg` so playback and download resolution can happen inside the containerized backend.

### Debian deployment

### Services included

- `dream-crates-api.service`: runs `uvicorn app.main:app`
- `dream-crates-poller.service`: one-shot poller invocation
- `dream-crates-poller.timer`: runs the poller every 5 minutes
- `nginx/dream-crates.conf`: reverse proxy to `127.0.0.1:8000`

### Expected server layout

- App checkout: `/opt/dream-crates/app`
- Backend working directory: `/opt/dream-crates/app/backend`
- Service user: `dream-crates`
- Environment file: `/etc/dream-crates.env`
- Default deployed SQLite path: `/var/lib/dream-crates/studiosample.db`

### Debian bootstrap

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv nginx
sudo useradd --system --create-home --shell /usr/sbin/nologin dream-crates
sudo mkdir -p /opt/dream-crates
sudo chown -R dream-crates:dream-crates /opt/dream-crates
sudo -u dream-crates git clone <repo-url> /opt/dream-crates/app

cd /opt/dream-crates/app/backend
sudo -u dream-crates python3 -m venv .venv
sudo -u dream-crates .venv/bin/pip install -e .[dev]
```

### Install server config

```bash
sudo cp deploy/debian/dream-crates.env.example /etc/dream-crates.env
sudo cp deploy/debian/systemd/*.service deploy/debian/systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dream-crates-api.service
sudo systemctl enable --now dream-crates-poller.timer
```

### Install nginx config

```bash
sudo cp deploy/debian/nginx/dream-crates.conf /etc/nginx/sites-available/dream-crates.conf
sudo ln -s /etc/nginx/sites-available/dream-crates.conf /etc/nginx/sites-enabled/dream-crates.conf
sudo nginx -t
sudo systemctl reload nginx
```

Remember to update `server_name` in `deploy/debian/nginx/dream-crates.conf` before enabling it.

### Deployment smoke checks

```bash
curl -fsS http://127.0.0.1:8000/healthz
cd /opt/dream-crates/app
./scripts/api-smoke.sh
```

## Testing

This repo follows a device-first workflow. See `testing.md` for the full policy.

Default validation path:

1. Run backend tests
2. Run iOS build checks without launching the full simulator UI
3. Prefer real-device validation for runtime behavior

Representative test coverage currently includes:

- Backend API responses
- Poller dedupe behavior
- Resolver behavior
- Push/APNs flows
- Rule-based tagging
- iOS saved/download state invariants
- Relaunch persistence for local sample state and downloaded files
- Playback speed persistence
- Notification preference persistence

## Planning and source-of-truth docs

- `PLAN.md` describes the product goal, milestones, acceptance criteria, and risk register
- `testing.md` is the testing workflow source of truth
- `bd` is the execution source of truth for current tasks and follow-up work

Useful `bd` commands:

```bash
bd ready
bd show <id>
bd update <id> --status in_progress
bd close <id>
bd sync
```

## Known caveats

- The app/backend naming is still mixed between `Dream Crates` and `StudioSample`
- The iOS app currently points to localhost instead of a configurable environment-specific API base URL
- Feed fallback behavior prioritizes resilience, so local mock content can mask backend outages during UI checks
- The backend save model is not yet fully user/device isolated
- Download and playback currently rely on a shared fallback MP3 path unless a real resolver command is provided

## Recommended next steps

- Add runtime-configurable API base URL handling for local, device, and deployed environments
- Replace hard-coded tracked channels with backend-managed channel configuration
- Implement a production-grade resolver path for streaming and downloads
- Complete end-to-end APNs handling on device
- Tighten per-device or per-user library modeling in the backend
- Expand integration coverage around poller -> storage -> notify -> app flows
