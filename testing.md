# Testing Policy (Device-First, Lightweight)

This project should **not** rely on full iOS Simulator launches by default.

## Default Testing Path (Fast + Lightweight)
1. Run backend tests first:
   ```bash
   cd /Users/kell/dev/dream-crates
   backend/.venv/bin/pytest -q backend/tests
   ```
2. Run iOS build checks without launching a full simulator UI:
   ```bash
   cd /Users/kell/dev/dream-crates/ios/StudioSample
   xcodegen generate
   xcodebuild -project StudioSample.xcodeproj -scheme StudioSampleApp -destination 'generic/platform=iOS' build
   ```
3. Prefer real-device validation for runtime behavior:
   ```bash
   cd /Users/kell/dev/dream-crates/ios/StudioSample
   ./scripts/test-device.sh
   ```

## Full iOS Simulator Rule
Use a full simulator session **only when absolutely necessary**:
- UI layout debugging that cannot be validated on a connected device.
- Reproducing a simulator-only issue.
- Capturing simulator screenshots specifically requested for documentation.

If simulator use is required, run one targeted pass and stop:
```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
DESTINATION_ID=D910A717-F352-4B33-9EB5-5D89AD4B123E ./scripts/test-simulator.sh
```

## Local Device Install (Preferred)
Install and launch on connected local devices, not simulator.

### iPhone `kellcd`
```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
xcodegen generate
xcodebuild \
  -project StudioSample.xcodeproj \
  -scheme StudioSampleApp \
  -configuration Debug \
  -destination 'id=00008110-001A40DC0E79401E' \
  -derivedDataPath /tmp/StudioSampleDerived \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=6263528F3C \
  build
xcrun devicectl device install app \
  --device 'kellcd' \
  /tmp/StudioSampleDerived/Build/Products/Debug-iphoneos/StudioSampleApp.app
xcrun devicectl device process launch \
  --device 'kellcd' \
  com.dreamcrates.studiosample
```

### iPad `spacepad air`
```bash
cd /Users/kell/dev/dream-crates/ios/StudioSample
xcodegen generate
xcodebuild \
  -project StudioSample.xcodeproj \
  -scheme StudioSampleApp \
  -configuration Debug \
  -destination 'id=00008122-001665562E61801C' \
  -derivedDataPath /tmp/StudioSampleDerived \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=6263528F3C \
  build
xcrun devicectl device install app \
  --device 'spacepad air' \
  /tmp/StudioSampleDerived/Build/Products/Debug-iphoneos/StudioSampleApp.app
xcrun devicectl device process launch \
  --device 'spacepad air' \
  com.dreamcrates.studiosample
```

## Signing Preconditions
If install/test on device fails, first verify in Xcode:
1. Apple account is signed in for team `6263528F3C`.
2. `StudioSampleApp` and `StudioSampleTests` both use Automatic Signing with that team.
3. A valid iOS Development certificate/profile exists for `com.dreamcrates.studiosample`.
