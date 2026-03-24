# Dream Crates Internal Release Checklist

## Build and Signing
- [ ] Xcode account for team `6263528F3C` is signed in.
- [ ] `StudioSampleApp` and `StudioSampleTests` use automatic signing.
- [ ] Device install works on at least one iPhone (`kellcd`) and one iPad (`spacepad air`) when available.

## Core Functional Validation
- [ ] New uploads appear once in feed.
- [ ] Save from feed/player appears in Library and persists after relaunch.
- [ ] Save state remains independent from download state.
- [ ] Downloaded sample plays without network.
- [ ] Player artwork spins while playing and decelerates on pause.
- [ ] Background playback + lock screen controls work.
- [ ] Speed control persists and applies to next playback.

## Notifications
- [ ] Device registration succeeds.
- [ ] New sample triggers exactly one notification.
- [ ] APNs fallback logging is visible when APNs config is missing.

## Verification Commands
```bash
cd /Users/kell/dev/dream-crates
./scripts/doctor.sh
./backend/scripts/run-tests.sh
```

## Documentation
- [ ] `/Users/kell/dev/dream-crates/testing.md` is up to date.
- [ ] `/Users/kell/dev/dream-crates/ios/StudioSample/README.md` reflects current install/test commands.
- [ ] `/Users/kell/dev/dream-crates/backend/README.md` reflects current env vars and test workflow.
