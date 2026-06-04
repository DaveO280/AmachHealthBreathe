# Amach Breathe

Resonance-breathing trainer for iPhone and Apple Watch. It guides paced breathing,
measures heart-rate variability (HRV) in real time, scores your physiological
**coherence** during a session, and offers an AI breathing coach. Part of the
[Amach Health](https://www.amachhealth.com) platform.

> **Status: early beta (TestFlight).** This is a small, invite-only release with a
> handful of testers; it hasn't been packaged for a wider audience yet.

## What it does

- **Resonance breathing sessions** on Apple Watch with live heart rate via HealthKit.
- **HRV-based calibration** that scans 4.5–7.0 BPM to find your personal resonance frequency.
- **Coherence scoring** computed on-device with a Goertzel filter, updated live during a session.
- **5-phase session structure**: baseline → warm-up → main → recovery → cool-down.
- **Pacing** via visual, audio, and haptic cues (Watch) and an audio/visual pacer (iPhone).
- **Session history & trends** (7/30/90-day windows) on iPhone.
- **Apple Watch complication** (corner / circular / rectangular) that deep-links into a quick-start session.
- **Daily reminders** (up to two times, timezone-aware) via local notifications.
- **AI breathing coach** — see below.
- **Optional wallet + encrypted sync** (Privy + Storj) so sessions follow you across devices.

## AI coaching

After a session you can ask the coach (**Luma**) for feedback. The app sends only
**bounded, derived session facts** (BPM, coherence, durations, aggregate audio-breath
metrics) — never raw audio or microphone data — to the Amach web backend at
`POST /api/ai/chat`. This is the **same endpoint and AI route used by the Amach Health
web app and iOS app**; the backend proxies the request to **Venice**, so all of Amach's
AI runs through a single Venice-backed route rather than the client calling any model
provider directly.

## Architecture

| Layer | Path | Notes |
|---|---|---|
| Shared logic | `Shared/` | Swift Package (`AmachBreatheShared`) consumed by both apps: HRV/coherence/calibration engines, models, networking, wallet crypto. |
| iOS app | `iOS/` | SwiftUI app — onboarding, session runner, history/trends, settings, subscription, coach. |
| watchOS app | `watchOS/` | SwiftUI app — pacers (visual/audio/haptic), workout session manager, complication, calibration loop. |
| Backend client | `Shared/.../Networking/AmachAPIClient.swift` | Talks to `amachhealth.com` (`/api/storj`, `/api/ai/chat`, `/api/tracking`). Base URL overridable via `AMACH_API_URL`. |

**Privacy-first:** all signal processing (HRV, coherence) runs on-device during a
session with no network calls; session data is AES-256-GCM encrypted before upload and
Storj stores only ciphertext; there is no analytics or tracking SDK
(`NSPrivacyTracking = false`).

## Requirements

- Xcode 16.x, Swift 6
- iOS 17+, watchOS 10+
- [XcodeGen](https://github.com/yonisol/xcodegen) (`brew install xcodegen`) — the Xcode project is generated from `project.yml`
- An Apple Watch is recommended; the iPhone app runs standalone with sensible empty states

## Build & run

```bash
# 1. Generate the Xcode project from project.yml
xcodegen generate

# 2. Open the workspace
open AmachBreathe.xcodeproj   # or "Amach Breathe.xcworkspace"

# 3. Build/run the AmachBreathe (iOS) or AmachBreatheWatch (watchOS) scheme.
#    For a signed build, set your Development Team in Signing & Capabilities
#    (HealthKit + Push Notifications capabilities required).
```

### Tests

```bash
# Shared package (fast, no simulator) — ~294 unit tests
cd Shared && swift test --parallel

# iOS unit tests
xcodebuild test -project AmachBreathe.xcodeproj -scheme AmachBreathe \
  -destination "platform=iOS Simulator,name=iPhone 15" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

CI (`.github/workflows/ci.yml`) runs the shared package tests, iOS unit tests, iOS/watchOS
builds, a Release archive-config check, and SwiftLint on every push and PR.

A no-signing simulator smoke loop is also available via `./sim-launch.sh` and
`./sim-calibration-loop.sh`. See [`TESTFLIGHT_NOTES.md`](TESTFLIGHT_NOTES.md) for the full
build/QA checklist.

## Subscription

StoreKit 2: a 7-day trial converts to monthly ($4.99), or a free "Connected" tier for
users who complete ≥ 3 sessions per 30 days. Subscription state is evaluated locally from
StoreKit transaction history (no server-side receipt validation) and synced across devices
via encrypted Storj.

## License

See repository for license details.
