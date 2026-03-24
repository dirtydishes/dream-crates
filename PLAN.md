# Dream Crates v1 - Implementation Plan

## 1) Product Goal
Build an internal iPhone app in Swift that aggregates recent YouTube uploads from tracked channels, notifies users about new samples, and provides a studio-style listening experience with save-to-library, background playback, speed control, and downloadable offline playback.

## 2) Non-Goals (v1)
- Public App Store compliance work.
- User account system and cross-device identity merge.
- Social features (comments/likes/sharing threads).
- Advanced ML model training pipeline for tagging.

## 3) Architecture (Text Diagram)

```text
+------------------- iOS App (SwiftUI) --------------------+
| Modules: AppCore, FeedFeature, PlayerFeature, Library,   |
| Settings                                                  |
| Frameworks: AVFoundation, SwiftData, Notifications, BG   |
|                                                           |
|  Feed Sync <------ REST API ------> Backend API           |
|  Playback Resolve <----------------> Worker Resolver      |
|  Download Prepare <---------------> Worker Resolver       |
|  APNs Device Register <-----------> API + Push Service    |
+-----------------------------------------------------------+

+---------------- Backend (FastAPI + Scheduler) ------------+
| Poll YouTube Data API for tracked channels                |
| Dedupe uploads, classify tags, persist metadata           |
| Resolve stream URLs, prepare downloads, manage TTL URLs   |
| Send APNs push notifications for new samples              |
+-----------------------------------------------------------+
```

## 4) Public Interfaces

### iOS model (core)
- `SampleItem`
  - `id: String`
  - `youtubeVideoId: String`
  - `channelId: String`
  - `title: String`
  - `descriptionText: String`
  - `publishedAt: Date`
  - `artworkURL: URL?`
  - `durationSeconds: Int?`
  - `genreTags: [TagScore]`
  - `toneTags: [TagScore]`
  - `isSaved: Bool`
  - `savedAt: Date?`
  - `downloadState: DownloadState`
  - `streamState: StreamState`

### REST endpoints (device-scoped)
- `GET /v1/channels/defaults`
- `GET /v1/users/{deviceId}/channels`
- `PUT /v1/users/{deviceId}/channels`
- `GET /v1/samples?channelIds=&since=&cursor=`
- `GET /v1/users/{deviceId}/library?cursor=`
- `PUT /v1/users/{deviceId}/library/{sampleId}?saved=true|false`
- `POST /v1/playback/resolve`
- `POST /v1/download/prepare`
- `POST /v1/devices/register`
- `PUT /v1/users/{deviceId}/preferences`

## 5) Delivery Milestones

### M1 Foundation
- Done: repo bootstrap, plan docs, and base iOS/backend scaffolds.
- Remaining cleanup tracked in `bd` for naming, deployment, and workflow hardening.

### M2 Ingestion + Feed
- Partial: YouTube polling, dedupe, feed API, and iOS feed loading exist.
- Remaining: tracked-channel management, stronger local cache, and production deployment.

### M3 Player Experience
- Partial: player UI, record spin/deceleration, background audio, remote controls, and speed changes exist.
- Remaining: real playback resolver, persisted speed preference, and richer now-playing metadata.

### M4 Library + Downloads + Offline
- Partial: save/unsave flows, backend library endpoints, and local offline files exist.
- Remaining: full backend sync, durable relaunch restore, and resolver-backed download preparation.

### M5 Notifications + Stabilization
- Partial: backend device registration, preferences, APNs dispatch, and notification event logging exist.
- Remaining: iOS APNs registration/onboarding, end-to-end push handling, and broader integration/UI coverage.

## 6) Acceptance Criteria
1. New tracked-channel upload appears once and triggers one notification. Partial backend support exists; full end-to-end device validation remains.
2. Save from feed/player appears in Library and persists on relaunch. In progress.
3. Save state remains independent from download state. Covered by unit tests.
4. Downloaded sample plays fully offline. In progress; durable relaunch restore is being added, resolver-backed preparation still remains.
5. Record artwork rotates while playing and decelerates to stop on pause. Implemented in current iOS scaffold.
6. Background playback works from lock screen with remote controls. Implemented at scaffold level; needs device validation.
7. Speed selection (0.5x-2.0x) applies immediately and persists. Immediate apply exists; persistence still tracked.
8. Expired stream URL is refreshed without user-visible failure. Not implemented yet.

## 7) Release Checklist (Internal)
- Build signed internal app configuration.
- Verify API URL and key env values.
- Smoke-test push, playback, download, and offline behavior.
- Validate first-launch onboarding for notification preferences.
- Confirm crash-free run on at least two iPhone device types.

## 8) Risk Register
- YouTube extraction fragility: resolver breakage when upstream signatures change.
- APNs delivery variance: occasional delays/drop requiring retry/metrics.
- Stream URL expiry: requires automatic refresh and seamless player handoff.

## 9) Beads Tracking Source of Truth
`bd` is authoritative for execution status and dependency order.
