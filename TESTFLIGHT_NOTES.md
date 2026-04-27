# Amach Breathe — TestFlight Build Notes

## Build Information

| Field | Value |
|---|---|
| Marketing Version | 1.0 |
| Build Number | 2 |
| iOS Deployment Target | 17.0 |
| watchOS Deployment Target | 10.0 |
| Swift Version | 6.0 |
| Xcode | 16.x |

---

## What's In This Build

This is the first TestFlight release of Amach Breathe. It covers the complete feature set across Phases 1–7:

- **Resonance breathing sessions** on Apple Watch with real-time heart rate via HealthKit
- **HRV-based calibration** to find your personal resonance frequency (4.5–7.0 BPM scan)
- **Coherence scoring** (Goertzel algorithm) displayed during sessions
- **5-phase session structure** (baseline → warm-up → main → recovery → cool-down)
- **Session history + trend analysis** (7/30/90-day windows) on iPhone
- **Apple Watch complication** (corner/circular/rectangular families) with deep-link quickstart
- **Local notification reminders** (up to 2 daily times, timezone-aware, daily repeat)
- **First-launch onboarding** (5 pages: welcome → permissions → calibration → session length → reminders)
- **Subscription layer** (StoreKit 2): 7-day trial → monthly ($4.99) or free Connected tier (≥ 3 sessions/30 days)
- **Wallet integration** (Privy) + encrypted session sync (Storj) for Connected/Subscribed users
- **Privacy-first** data model: on-device HealthKit, AES-256-GCM encrypted cloud sync, no tracking

---

## Automated Test Status

| Suite | Tests | Status |
|---|---|---|
| Shared package unit tests | 294 | ✅ All pass (1 skipped: real Storj server, requires AMACH_API_URL_TEST env) |
| iOS unit tests | 12 | ✅ All pass |
| Performance regression (15-min synthetic session) | 12 | ✅ Within budget |
| Subscription edge cases | 29 | ✅ All pass |
| WatchConnectivity integration | 12 | ✅ All pass |
| CI pipeline | — | ✅ Green on `main` |

**Battery proxy result:** 900 coherence calls complete in < 1 s on macOS →
estimated Series 4 time < 20 s across a 900 s session → < 2.5% CPU duty cycle (spec: < 5%). ✅

---

## Manual Steps Required Before Submission

> The following steps require hands-on attention and cannot be automated. None of these block the TestFlight invite, but all must be complete before App Store submission.

### 🔴 Required for TestFlight

1. **Set Development Team in Xcode**
   - Open `AmachBreathe.xcodeproj` → Target → Signing & Capabilities
   - Set your Development Team for both `AmachBreathe` and `AmachBreatheWatch`
   - Enable automatic signing (or manually assign provisioning profiles)
   - Profiles must include: HealthKit, Push Notifications

2. **Archive the iOS app**
   ```
   Product → Archive  (scheme: AmachBreathe, destination: Any iOS Device)
   ```
   Then: Distribute App → TestFlight → Upload

3. **Bump build number for each upload**
   - Edit `iOS/Sources/App/Info.plist`: increment `CFBundleVersion` (currently **2**)
   - Edit `watchOS/Sources/App/Info.plist`: same value
   - Run `xcodegen generate` to regenerate the project

### 🟡 Test Pass (Device Required)

4. **Apple Watch Series 4 + latest hardware**
   - Install via Xcode Devices, not TestFlight (can't direct-install watchOS via TF)
   - Run a full 15-minute session; confirm coherence updates live; confirm session saves to History
   - Check complication appears and taps into a 5-minute quickstart session
   - Confirm Watch ↔ iPhone connectivity message flow (session result appears on iPhone)

5. **iPhone-only fallback (no Watch paired)**
   - iPhone 14 or 15 without a paired Watch
   - Verify History and Trends tabs load with empty states
   - Verify Settings → Reminders adds/removes notification times
   - Verify Subscription → Manage page is accessible
   - Confirm onboarding flows through all 5 pages; calibration page shows "Find Your Rate" (no calibration yet)

6. **StoreKit sandbox purchase**
   - Sign in with a Sandbox Apple ID in Settings → App Store on device
   - Run through Conversion screen → "Subscribe $4.99/month"
   - Confirm subscription state transitions to `.subscribed`
   - Test Restore Purchases
   - Cancel in App Store sandbox; confirm state eventually transitions to `.expired`

7. **Privy + Storj connection flow (test environment)**
   - Use test wallet credentials from `amach-test-env`
   - Complete wallet connection via Privy modal
   - Run a session; confirm it uploads to Storj
   - Re-install app; reconnect wallet; confirm sessions restore from Storj

---

## Known Issues

| # | Description | Severity | Workaround |
|---|---|---|---|
| 1 | HealthKit permissions prompt does not appear on iOS Simulator (expected OS limitation) | Low | Test on real device |
| 2 | WCSession unavailable when Watch is not reachable — session start button is hidden; no user-facing error message | Low | Pair a Watch |
| 3 | Complication requires at least one app launch before it appears in the Watch face picker | Low | Launch Watch app once |
| 4 | Privy SDK web modal may show a blank screen on first launch if network is slow | Low | Dismiss and retry |
| 5 | `armv7` capability was in the original Info.plist — fixed to `arm64` in build 2; no impact on TestFlight but flagged for awareness | Fixed in build 2 | — |

---

## What Testers Should Focus On

### Core breathing loop
- [ ] 5-minute session completes end-to-end (Watch → save → iPhone History)
- [ ] 15-minute session: coherence score updates smoothly throughout, no freezes
- [ ] Session result appears in History within 10 seconds of Watch completion
- [ ] Trend view updates after ≥ 2 sessions

### Calibration
- [ ] Calibration scan (runs ~6 test BPMs on Watch) completes and saves a resonance BPM
- [ ] Calibration page in onboarding shows the saved BPM after completing a calibration

### Notifications
- [ ] Add a reminder in Settings; verify it fires at the set time
- [ ] Delete a reminder; confirm notification is cancelled
- [ ] Test with 2 reminders (maximum)

### Onboarding (fresh install)
- [ ] All 5 pages scroll/advance correctly
- [ ] "Skip" on Permissions page still advances
- [ ] Done on the Reminders page marks onboarding complete; Home tab appears

### Subscription
- [ ] 7-day trial countdown is visible in Settings → Manage
- [ ] Conversion screen shows two cards (Free Connected / Subscribed)

### Wallet / Sync
- [ ] Connecting wallet triggers Storj session upload for any pending sessions
- [ ] Disconnecting wallet hides the sync banner

---

## Environment

| Component | Version |
|---|---|
| Privy SDK | Latest (integrated via iOS SDK) |
| Storj | Test bucket via AMACH_API_URL_TEST |
| StoreKit | Sandbox (`iOS/AmachBreathe.storekit` product: `com.amach.breathe.monthly`) |
| HealthKit | Read: heart rate; Write: none (sessions saved to local store only) |

---

## Architecture Notes for Testers

- All signal processing (HRV, coherence) runs **on-device on the Watch** — no network calls during a session
- Session data is **AES-256-GCM encrypted** before upload; Storj stores opaque ciphertext
- No analytics or tracking SDK; `NSPrivacyTracking = false` in `PrivacyInfo.xcprivacy`
- Subscription state is evaluated **locally** from StoreKit transaction history — no server-side receipt validation
