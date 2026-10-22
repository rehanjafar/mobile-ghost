# Mobile Ghost

Native, iPhone-only location simulation inspired by [Ghost Transit](https://github.com/rehanjafar/ghost-transit). Version **0.1.0 — experimental device-test build**.

Runs on the iPhone after initial setup; no always-connected Mac backend. **Developer Mode alone is not sufficient:** this implementation requires a device pairing file, LocalDevVPN, a mounted developer image, and a sideloaded/development-signed installation. Target device: **iPhone on iOS 26.5**. Deployment minimum is iOS 17.4; physical compatibility has not yet been verified for Mobile Ghost.

## Features

- Native SwiftUI / Apple Maps interface, map selection, search and coordinate entry.
- Fixed simulated locations and explicit restore through the real idevice developer-service bridge.
- Walking, driving and custom road-based bus routes with 2–12 stops.
- Adjustable 1–160 km/h speed; per-stop waits and departure speeds.
- Pause/resume and hold at destination; failed updates pause progress.
- Nearby mapped bus stops within 1 km, with explicit searches and a 30-second throttle.
- Saved places; persisted last acknowledged point for restore after relaunch.
- One foreground departure schedule within 30 days; captures the route and speed.
- Guided pairing, VPN, developer-image preparation and connection status.

## Setup on your iOS 26.5 iPhone

1. Keep Developer Mode enabled.
2. Obtain a pairing file **for this iPhone**, following the [StikDebug pairing guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md). A one-time computer step is acceptable; keep the file private.
3. Install [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044). Join a Wi-Fi network and connect LocalDevVPN.
4. Install Mobile Ghost using Xcode signing or sign its unsigned IPA with your sideloading tool. An unsigned IPA cannot be installed directly. Signing expiry depends on your signing method.
5. Open Mobile Ghost and import the pairing file. Allow local-network access. Let the developer image download and mount; use Connection → Prepare developer image / Retry if needed.
6. Select a nearby test point, press **Set location**, and check Apple Maps. Return to Mobile Ghost, press **Restore real location**, and check Maps again.
7. After fixed-location and restore checks pass, test a short route. Stay in Mobile Ghost during playback. Leaving the app deliberately pauses movement.

## Build

First run `./scripts/fetch-device-library.sh` to download and verify the pinned device library. Then open `MobileGhost.xcodeproj` in Xcode, choose the MobileGhost target, and select your own development team under Signing & Capabilities. Choose a unique bundle identifier if your signing account requires one. Select your iPhone and Run. No developer team or signing credentials are included.

Unsigned device build:

```sh
xcodebuild -project MobileGhost.xcodeproj -scheme MobileGhost \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build/Device CODE_SIGNING_ALLOWED=NO build
```

Core checks (macOS with Swift installed):

```sh
./scripts/test-core.sh
```

The downloaded idevice static library is for physical iOS devices; this project does not claim Simulator support. Build validation used Xcode 27.1 and its iOS SDK, with a deployment minimum below iOS 26.5.

## Behavior and limitations

- **Keep the app foregrounded.** Mobile Ghost keeps the screen awake during an active session or pending departure. Backgrounding pauses movement and cancels the pending schedule. It does not prove real location was restored.
- A delayed update pauses movement rather than catching up. Progress is committed only when the bridge accepts the location command.
- Starting a route moves to its first point. Setting a fixed location replaces the current route session; resume is then unavailable.
- A manual fixed location, start, resume or restore cancels a pending departure. Schedules are not retained across app restarts.
- Restore is explicit. After a restart, the app may briefly reapply the last stored point to reopen a developer session before clearing it. Errors leave the recovery record intact.
- Accepted commands do not establish what other apps display. Apps can detect software-simulated locations.
- This release is **not feature-complete with Ghost Transit**: mapped bus-service geometry/directions, GPX import/export, background movement, notifications and recurring schedules are not implemented. Bus mode uses automobile roads between selected stops; it is not a transit itinerary or bus-lane router.
- There is no App Store/TestFlight distribution or claim of support for every recent iOS release. Device pairing and VPN behavior can change across iOS versions.

## Privacy

No app accounts or analytics. Saved locations and the last acknowledged session point are stored locally in UserDefaults (not encrypted). Pairing records are managed by the inherited protected file store; do not commit or share them. MapKit sends place searches and route coordinates to Apple. Bus searches send the viewed centre to `overpass-api.de`; map/stop data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL. Developer image downloads use the inherited `doronz88/DeveloperDiskImage` GitHub source and require internet. Provider availability is not guaranteed.

## Origin and license

This is an independent derivative of **[TLocation](https://github.com/truongkma/t-location)** at commit `5e57f815e5958f133dfbaae8252473054adeccf0`, itself derived from **[StikDebug](https://github.com/StikDebug/StikDebug)** by Stephen Bove and contributors. Those projects supply pairing, tunneling, developer image mounting, and the idevice bridge. Mobile Ghost adds the native journey interface, route engine, scheduling and recovery controller. Modified October 22, 2026. Not an official upstream release.

**AGPL-3.0**, inherited unchanged; see [LICENSE](LICENSE). Copyright notices remain in inherited files. See [third-party notices](THIRD_PARTY_NOTICES.md) and [validation](docs/VALIDATION.md). Ghost Transit is the feature reference; its desktop code is not bundled.
