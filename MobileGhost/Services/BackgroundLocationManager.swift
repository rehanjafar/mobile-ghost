// Derived from TLocation / StikDebug, © Stephen Bove and contributors.
// Mobile Ghost background lifecycle changes, 2026-10-22. AGPL-3.0.
import Combine
import CoreLocation

final class BackgroundLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BackgroundLocationManager()
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isRunning = false
    private let locationManager = CLLocationManager()
    private var requested = false

    var canContinueInBackground: Bool {
        isRunning && (authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse)
    }
    var permissionDescription: String {
        switch authorizationStatus {
        case .authorizedAlways: return "Always allowed"
        case .authorizedWhenInUse: return "While Using — active session only"
        case .denied: return "Denied — enable in iPhone Settings"
        case .restricted: return "Restricted by this iPhone"
        default: return "Not requested"
        }
    }
    private override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    /// Must be initiated in the foreground. While Using permission can continue
    /// an already-active background location session with the visible indicator.
    /// Neither permission level guarantees that iOS will never suspend the app.
    func requestStart() {
        requested = true
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        updateService()
    }
    func requestAlwaysPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }
    func requestStop() { requested = false; updateService() }
    func refreshAuthorizationStatus() { updateService() }
    private func updateService() {
        authorizationStatus = locationManager.authorizationStatus
        let allowed = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
        if requested && allowed {
            if !isRunning { locationManager.startUpdatingLocation(); isRunning = true }
        } else {
            locationManager.stopUpdatingLocation(); isRunning = false
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { updateService() }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary absence of GPS is not proof that the developer tunnel failed.
        if let e = error as? CLError, e.code == .denied { updateService() }
    }
}
