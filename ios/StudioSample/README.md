# Dream Crates iOS App

Generated with XcodeGen (`project.yml`) for iPhone-first development.

## Core Commands

```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
xcodegen generate
xcodebuild -project 'dream crates.xcodeproj' -scheme StudioSampleApp -destination 'generic/platform=iOS' build
./scripts/list-destinations.sh
./scripts/test-device.sh
./scripts/install-device.sh
```

Script overrides:
- `DEVICE_NAME=kellcd ./scripts/install-device.sh`
- `DEVICE_NAME='spacepad air' ./scripts/install-device.sh`
- `DESTINATION_ID=<simulator-id> ./scripts/test-simulator.sh`

## Device Deploy/Test Runbook (`kellcd`)

### 1) One-time Xcode signing setup
1. Open `dream crates.xcodeproj` in Xcode.
2. Xcode -> Settings -> Accounts: sign in with the Apple ID for team `6263528F3C`.
3. In target `StudioSampleApp`:
   - Signing -> `Automatically manage signing` = enabled
   - Team = `6263528F3C`
4. In target `StudioSampleTests`, set the same signing values.
5. Build once in Xcode to let Apple certificates/profiles download.

### 2) Discover destinations
```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
./scripts/list-destinations.sh
```

### 3) Install and launch on device
```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
DEVICE_NAME=kellcd ./scripts/install-device.sh
```

### 4) Run tests on device
```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
./scripts/test-device.sh
```

### 5) Known signing failures and fixes
- `No Account for Team ...`: sign in in Xcode Settings -> Accounts.
- `No signing certificate "iOS Development" found`: allow Xcode to manage signing and re-run once in Xcode UI.
- `No profiles for 'com.dreamcrates.studiosample'`: confirm bundle id/team pair in Signing and retry with `-allowProvisioningUpdates`.

## Testing Policy
Use `/Users/kell/dev/dream-crates/testing.md` as testing source of truth.

## Current scope
- Base tab navigation (`Feed`, `Player`, `Library`, `Settings`)
- Studio-style dark analog palette
- Player shell with spinning record animation and pause deceleration
- Core domain models including saved/download/stream state
