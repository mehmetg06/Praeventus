#if canImport(CoreLocation)
import CoreLocation

/// Privacy-first one-shot location.
///
/// - Requests **When In Use** authorization only (never `.always`).
/// - Uses `kCLLocationAccuracyReduced` so iOS hands back a fuzzed coordinate
///   (~1–20 km), and additionally rounds the result to ~1 km before use, so even
///   if the user granted Precise Location the app never consumes a sharp fix.
/// - Fetches a single fix on demand (no continuous tracking, easy on battery).
///
/// Manual Swift Playgrounds step (no `Info.plist` to edit by hand): in
/// App Settings → Capabilities, add **Core Location When in Use** and a usage
/// description such as:
/// "Praeventus uses your approximate location to show local weather. /
///  Praeventus, yerel hava durumunu göstermek için yaklaşık konumunuzu kullanır."
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {

    enum LocationError: Error { case denied, unavailable }

    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        self.authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// Requests permission if needed and resolves a single coarse coordinate.
    func requestCoordinate() async throws -> CLLocationCoordinate2D {
        // Don't allow overlapping requests.
        if continuation != nil { throw LocationError.unavailable }

        switch manager.authorizationStatus {
        case .notDetermined:
            return try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.manager.requestWhenInUseAuthorization()
                // Resolution continues in `locationManagerDidChangeAuthorization`.
            }
        case .authorizedWhenInUse, .authorizedAlways:
            return try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.manager.requestLocation()
            }
        default:
            throw LocationError.denied
        }
    }

    // MARK: - CLLocationManagerDelegate
    // Core Location calls these on the main thread (the manager is created on the
    // main actor). They're marked `nonisolated` to satisfy the protocol under
    // Swift 6 strict concurrency, then hop back onto the main actor.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorization = self.manager.authorizationStatus
            guard continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            default:
                break // still .notDetermined — wait for the user's choice
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let coordinate = locations.last?.coordinate else {
                finish(.failure(LocationError.unavailable))
                return
            }
            finish(.success(coarsen(coordinate)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            finish(.failure(error))
        }
    }

    // MARK: - Helpers

    /// Round to ~2 decimal places (~1.1 km) so we never retain a sharp fix.
    private func coarsen(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (c.latitude * 100).rounded() / 100,
            longitude: (c.longitude * 100).rounded() / 100
        )
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }
}
#endif
