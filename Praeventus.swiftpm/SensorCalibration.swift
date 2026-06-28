import Foundation

/// Opt-in, on-device calibration of the model snapshot using the iPad's
/// barometer. A pressure sensor measures *pressure* directly, so we only
/// calibrate `pressure` — nudging the grid-point value toward the reading
/// actually taken where the user is standing (a micro-climate the ~10 km model
/// cell can't resolve). Nothing leaves the device.
///
/// iOS-only; a no-op stub keeps the macOS CLI / Linux build compiling.
#if canImport(CoreMotion)
import CoreMotion

@MainActor
final class SensorCalibration {

    /// Largest correction we trust from a single sensor reading (hPa), so a bad
    /// sample can't distort the snapshot.
    private static let maxPressureOffset = 25.0

    private let altimeter = CMAltimeter()
    private var latestPressureHPa: Double?
    private var isRunning = false

    var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    /// Begins streaming barometric pressure. Safe to call repeatedly.
    func start() {
        guard isAvailable, !isRunning else { return }
        isRunning = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // CMAltitudeData.pressure is in kPa; the app works in hPa.
            self.latestPressureHPa = data.pressure.doubleValue * 10
        }
    }

    func stop() {
        guard isRunning else { return }
        altimeter.stopRelativeAltitudeUpdates()
        isRunning = false
    }

    /// Returns a copy with `pressure` shifted toward the device barometer, or the
    /// snapshot unchanged when no reading is available yet.
    func calibrate(_ weather: WeatherData) -> WeatherData {
        guard let device = latestPressureHPa, device.isFinite, weather.pressure > 0 else {
            return weather
        }
        let delta = (device - weather.pressure)
            .clamped(to: -Self.maxPressureOffset...Self.maxPressureOffset)
        var adjusted = weather
        adjusted.pressure = weather.pressure + delta
        return adjusted
    }
}

#else

/// No-op on platforms without CoreMotion (macOS CLI, Linux CI).
@MainActor
final class SensorCalibration {
    var isAvailable: Bool { false }
    func start() {}
    func stop() {}
    func calibrate(_ weather: WeatherData) -> WeatherData { weather }
}

#endif

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
