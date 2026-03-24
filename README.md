# Dream Crates

Internal iOS app + backend for discovering and playing newly uploaded YouTube samples from curated channels.

## Repo Layout
- `ios/StudioSample`: SwiftUI iPhone app (Dream Crates)
- `backend`: FastAPI ingestion/API service
- `testing.md`: device-first testing policy (minimal simulator usage)
- `PLAN.md`: scope, milestones, acceptance criteria

## Quickstart
### Backend
```bash
cd /Users/kell/dev/dream-crates/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
uvicorn app.main:app --reload
```

### iOS (build-only)
```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
xcodegen generate
xcodebuild -project StudioSample.xcodeproj -scheme StudioSampleApp -destination 'generic/platform=iOS' build
```

## Device-First Workflow
- Use `/Users/kell/dev/dream-crates/testing.md` as source of truth.
- Prefer local device validation (`kellcd`/`spacepad air`) over full simulator launches.

## Useful Scripts
- `/Users/kell/dev/dream-crates/scripts/doctor.sh`
- `/Users/kell/dev/dream-crates/scripts/api-smoke.sh`
- `/Users/kell/dev/dream-crates/backend/scripts/run-tests.sh`
- `/Users/kell/dev/dream-crates/ios/StudioSample/scripts/list-destinations.sh`
- `/Users/kell/dev/dream-crates/ios/StudioSample/scripts/build-device.sh`
- `/Users/kell/dev/dream-crates/ios/StudioSample/scripts/install-device.sh`
