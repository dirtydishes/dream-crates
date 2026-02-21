# StudioSample iOS Scaffold

Generated with XcodeGen (`project.yml`) for iPhone-first development.

## Commands

```bash
cd ios/StudioSample
xcodegen generate
xcodebuild -project StudioSample.xcodeproj -scheme StudioSampleApp -destination 'generic/platform=iOS' build
```

## Current scope
- Base tab navigation (`Feed`, `Player`, `Library`, `Settings`)
- Studio-style dark analog palette
- Player shell with spinning record animation and pause deceleration
- Core domain models including saved/download/stream state
