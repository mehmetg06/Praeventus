#if canImport(SwiftUI)
import Foundation

/// Thin adapter between the SwiftUI-facing `AtmosphericState` and the
/// Foundation-only `MeteorologicalExpertSystem`.
///
/// All the meteorology — the computed dynamics and the scenario matrix — lives
/// in `MeteorologicalExpertSystem`, which is deterministic, CPU-only and unit
/// testable on the headless CLI. This type only translates the atmospheric
/// engine's scalars into the expert system's primitive inputs and returns its
/// single, self-consistent Turkish paragraph.
enum WeatherNarrativeEngine {

    static func story(weather: WeatherData, atmosphere: AtmosphericState, hourly: [HourlyPoint], daily: [DailyRange]) -> String {
        let dynamics = AtmosphericDynamics.from(
            weather: weather,
            hourly: hourly,
            instability: atmosphere.instability,
            stormScore: stormScore(for: atmosphere.stormRisk),
            visibilityPoor: atmosphere.visibility == .poor,
            isDaytime: weather.timeOfDay == .day
        )
        return MeteorologicalExpertSystem.narrative(for: dynamics)
    }

    /// Maps the coarse storm-risk band back onto the 0…1 scalar the dynamics
    /// computation expects for its barometric-tendency inference.
    private static func stormScore(for risk: AtmosphericRisk) -> Double {
        switch risk {
        case .low:      return 0.2
        case .moderate: return 0.5
        case .high:     return 0.85
        }
    }
}
#endif
