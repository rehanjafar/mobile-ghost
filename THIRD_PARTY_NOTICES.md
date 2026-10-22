# Third-party notices

- **TLocation**: https://github.com/truongkma/t-location, commit `5e57f815e5958f133dfbaae8252473054adeccf0`. AGPL-3.0. Native infrastructure, Xcode project and app icon inherited; original copyright notices retained. Upstream itself attributes its core to StikDebug, © Stephen Bove and contributors.
- **StikDebug**: https://github.com/StikDebug/StikDebug. AGPL-3.0. Device connection, pairing, developer image and location bridge ancestry through TLocation.
- **idevice**, Jackson Coxson: https://github.com/jkcoxson/idevice. MIT; see `docs/IDEVICE-LICENSE.txt`. The build script downloads `MobileGhost/idevice/libidevice_ffi.a`; its header and module map are copied unchanged from the pinned TLocation revision. The exact idevice source revision used to create that upstream binary is not specified by TLocation; a fully reproducible dependency build is not claimed. The pinned TLocation source provides the exact distributed binary and bridge sources.
- **OpenStreetMap contributors**, ODbL: https://www.openstreetmap.org/copyright. Nearby stop data via Overpass API. Apple MapKit provides map rendering, search and road/walking routes.
- **DeveloperDiskImage**: https://github.com/doronz88/DeveloperDiskImage. Download locations are inherited from TLocation; Apple developer images are not included in this repository or IPA.

Mobile Ghost modifications are dated October 22, 2026 and distributed under the same AGPL-3.0 license. This is an independent derivative, not an upstream product. No warranty is provided.

Pinned idevice archive SHA-256: `6524066d54ef23e00d46445c04dfc694e180196d54119d718f68434fa225be35`.
