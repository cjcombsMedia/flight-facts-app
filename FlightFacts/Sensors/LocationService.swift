import Foundation
import CoreLocation

/// Thin wrapper over CLLocationManager tuned for flight: full accuracy, no
/// distance filter, the `.airborne` activity type, and background updates so the
/// phone can go in the seat pocket without the feed going quiet.
///
/// GPS works in airplane mode on iPhone — the receiver is receive-only and stays
/// on. What airplane mode removes is *assisted* GPS (cell and Wi-Fi hints), so a
/// cold first fix can take a few minutes. A window seat helps a lot.
final class LocationService: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    private(set) var latest: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Only true between `start()` and `stop()`. Authorization changes must not
    /// switch GPS on by themselves — previously they did, which left location
    /// running in the background whenever the app had permission.
    private(set) var isActive = false

    var onAuthChange: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // Tells CoreLocation it's in an aircraft: no snapping to roads, and the
        // speed and altitude filtering is tuned for flight rather than a car.
        manager.activityType = .airborne
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Only ask for Always once we already have When-In-Use, per Apple's flow.
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func start() {
        isActive = true
        latest = nil
        beginUpdatesIfAuthorized()
    }

    func stop() {
        isActive = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func beginUpdatesIfAuthorized() {
        let status = manager.authorizationStatus
        guard isActive, status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        // Background updates need the "location" UIBackgroundMode (declared) and
        // an authorization; with When-In-Use iOS shows the blue location pill.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive, let loc = locations.last else { return }
        latest = loc
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        authorization = m.authorizationStatus
        onAuthChange?(m.authorizationStatus)
        beginUpdatesIfAuthorized()
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient and normal in a cabin; the next
        // fix will arrive. SensorFusion handles the gap.
    }
}
