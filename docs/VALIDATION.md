# Validation — October 22, 2026

## Completed

- Xcode 27.1: unsigned physical-iPhone Debug and Release builds succeeded.
- Pure Swift journey checks: 19 passed. Covers coordinate validation, spherical distances, dateline interpolation, initial/intermediate waits, segment speeds, destination hold, zero-length segments, invalid plans, and uncommitted versus acknowledged progress.

## Still required on the owner's iOS 26.5 iPhone

No physical device test has been performed for Mobile Ghost. Upstream compatibility statements are not a Mobile Ghost test result.

1. Sign/install and import the correct device pairing file; connect LocalDevVPN with Wi-Fi joined.
2. Verify developer image preparation and mounting.
3. Set a nearby location; confirm in Maps; restore and confirm the real position.
4. Start a short walking route; pause/resume; change speed; verify stop waits and arrival.
5. Background during movement: return and confirm it is paused, then explicitly resume.
6. Disable VPN: confirm a failed operation does not claim successful progress or restoration. Reconnect, retry and restore.
7. Quit during a fixed session, reopen and restore from the recovery record.
8. Schedule a departure with the app foregrounded; separately verify leaving the app cancels it.
9. Check search, road routing and nearby bus stops with live providers.

Command acknowledgement does not prove another app's location. Check actual device behavior before relying on the app.
