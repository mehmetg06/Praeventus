import Foundation

// MARK: - Storm Alert Types

/// Severity of a detected rapid-pressure-drop event (WMO rapid-deepening criteria).
enum StormSeverity: Int, Equatable, Comparable, CaseIterable, Sendable {
    case watch   = 1  // ≥ 3 hPa in 3 h  — conditions may deteriorate
    case warning = 2  // ≥ 5 hPa in 2 h  — squall likely
    case extreme = 3  // ≥ 8 hPa in 90 m — explosive development

    static func < (lhs: StormSeverity, rhs: StormSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var localizedTitle: String {
        switch self {
        case .watch:
            return String(localized: "storm.watch.title",
                          defaultValue: "Atmosferik Dengesizlik İzleme")
        case .warning:
            return String(localized: "storm.warning.title",
                          defaultValue: "Ani Fırtına (Squall) Uyarısı")
        case .extreme:
            return String(localized: "storm.extreme.title",
                          defaultValue: "Patlayıcı Basınç Düşüşü")
        }
    }

    var localizedDescription: String {
        switch self {
        case .watch:
            return String(localized: "storm.watch.desc",
                          defaultValue: "Basınç belirgin şekilde düşüyor. Hava bir saat içinde bozulabilir.")
        case .warning:
            return String(localized: "storm.warning.desc",
                          defaultValue: "Hızlı basınç düşüşü algılandı. Ani squall ve sert rüzgar riski.")
        case .extreme:
            return String(localized: "storm.extreme.desc",
                          defaultValue: "Patlayıcı basınç düşüşü. Hemen güvenli bir alana sığının.")
        }
    }
}

/// An atmospheric instability event detected purely from the device barometer,
/// independent of any network forecast data.
struct StormAlert: Equatable, Sendable {
    let severity: StormSeverity
    /// Actual pressure drop measured over `windowMinutes`.
    let pressureDropHPa: Double
    /// Detection window during which the drop occurred.
    let windowMinutes: Int
    let triggeredAt: Date
}

// MARK: - Engine

#if canImport(CoreMotion)
import CoreMotion

/// Monitors the device barometer and emits `StormAlert` values via `AsyncStream`
/// when a rapid pressure drop is detected — independently of any network forecast.
///
/// **Detection thresholds (WMO rapid-deepening criteria):**
///
/// | Severity  | Drop   | Window |
/// |-----------|--------|--------|
/// | `.watch`  | ≥ 3 hPa | 3 h   |
/// | `.warning`| ≥ 5 hPa | 2 h   |
/// | `.extreme`| ≥ 8 hPa | 90 min|
///
/// The barometer data never leaves the device.
///
/// Usage (from `@MainActor` WeatherStore):
/// ```swift
/// for await alert in await stormSensor.startMonitoring() {
///     stormAlert = alert
/// }
/// ```
actor StormSensorEngine {

    // MARK: - Private Types

    private struct PressureReading: Sendable {
        let time: Date
        let pressureHPa: Double
    }

    private enum DetectionWindow: CaseIterable {
        case threeHour, twoHour, ninetyMinute

        var seconds: Double {
            switch self {
            case .threeHour:    return 3 * 3600
            case .twoHour:      return 2 * 3600
            case .ninetyMinute: return 90 * 60
            }
        }

        var thresholdHPa: Double {
            switch self {
            case .threeHour:    return 3.0
            case .twoHour:      return 5.0
            case .ninetyMinute: return 8.0
            }
        }

        var severity: StormSeverity {
            switch self {
            case .threeHour:    return .watch
            case .twoHour:      return .warning
            case .ninetyMinute: return .extreme
            }
        }

        var windowMinutes: Int { Int(seconds / 60) }
    }

    // MARK: - State

    private let altimeter = CMAltimeter()
    private var readings  = [PressureReading]()
    private var continuation: AsyncStream<StormAlert>.Continuation?
    private var isMonitoring = false

    /// Maximum readings kept in the ring buffer (≈ one sample per 30 s over 4 h).
    private static let bufferLimit = 480

    // MARK: - Public API

    nonisolated var isAvailable: Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    /// Starts barometric monitoring and returns a stream of storm alerts.
    ///
    /// Calling this a second time while already monitoring restarts the sensor
    /// cleanly and returns a fresh stream (the previous stream is finished).
    func startMonitoring() -> AsyncStream<StormAlert> {
        if isMonitoring {
            altimeter.stopRelativeAltitudeUpdates()
            isMonitoring = false
            continuation?.finish()
            continuation = nil
        }

        let (stream, continuation) = AsyncStream.makeStream(of: StormAlert.self)
        self.continuation = continuation

        guard isAvailable else {
            continuation.finish()
            return stream
        }

        isMonitoring = true

        // CMAltimeter delivers on a queue; hop back to the actor for state mutation.
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // CMAltitudeData.pressure is in kPa → convert to hPa.
            let hpa = data.pressure.doubleValue * 10.0
            Task { await self.record(hpa) }
        }

        return stream
    }

    /// Stops monitoring and finishes the active stream.
    func stopMonitoring() {
        guard isMonitoring else { return }
        altimeter.stopRelativeAltitudeUpdates()
        isMonitoring = false
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private: Reading + Detection

    private func record(_ pressureHPa: Double) {
        // Reject physically implausible values (sensor noise / unit error).
        guard (700.0 ... 1100.0).contains(pressureHPa) else { return }

        readings.append(PressureReading(time: Date(), pressureHPa: pressureHPa))

        if readings.count > Self.bufferLimit {
            readings.removeFirst(readings.count - Self.bufferLimit)
        }

        if let alert = detectAlert() {
            continuation?.yield(alert)
        }
    }

    /// Scans every detection window and returns the worst qualifying alert.
    private func detectAlert() -> StormAlert? {
        let now = Date()
        var worst: StormAlert?

        for window in DetectionWindow.allCases {
            let cutoff = now.addingTimeInterval(-window.seconds)
            let windowReadings = readings.filter { $0.time >= cutoff }

            // Need at least two readings spanning the window meaningfully.
            guard windowReadings.count >= 2,
                  let oldest = windowReadings.first,
                  let newest = windowReadings.last
            else { continue }

            let drop = oldest.pressureHPa - newest.pressureHPa
            guard drop >= window.thresholdHPa else { continue }

            let candidate = StormAlert(
                severity:        window.severity,
                pressureDropHPa: drop,
                windowMinutes:   window.windowMinutes,
                triggeredAt:     now
            )

            if let current = worst {
                if candidate.severity > current.severity { worst = candidate }
            } else {
                worst = candidate
            }
        }

        return worst
    }
}

#else

/// Stub for platforms without CoreMotion (macOS CLI, Linux CI).
actor StormSensorEngine {
    nonisolated var isAvailable: Bool { false }

    func startMonitoring() -> AsyncStream<StormAlert> {
        let (stream, continuation) = AsyncStream.makeStream(of: StormAlert.self)
        continuation.finish()
        return stream
    }

    func stopMonitoring() {}
}

#endif
