import Foundation

/// Ready-to-display bundle of `ThermalPredictionEngine` output for the current
/// location.
///
/// Foundation-only (no SwiftUI) so it stays exercisable on the macOS/Linux CLI
/// like the rest of the data + domain layer. Everything here is a derived view
/// of live weather — it holds no state and is recomputed on demand.
struct HealthInsights: Equatable {
    /// Persistent multi-day heatwave alert, or `nil` when no 3+ day ≥35 °C run.
    let heatwaveAlert: String?
    /// Risk band for the current hour's conditions.
    let currentRiskLevel: ActivityRiskLevel
    /// Full warning for the current hour, including the Foehn note when active.
    let currentRiskWarning: String
    /// Whether a hot, dry wind is amplifying — rather than relieving — heat now.
    let isFoehnActive: Bool
    /// Unprotected minutes before erythema for the assumed phototype + SPF.
    let minutesToBurn: Int
    /// Live UV index used for the burn estimate (0 ⇒ no meaningful burn risk).
    let uvIndex: Int
    /// Fitzpatrick phototype assumed for the burn estimate.
    let skinType: FitzpatrickSkinType
    /// Sunscreen SPF assumed for the burn estimate.
    let spf: Int
    /// Recommendation of the best continuous outdoor windows for today.
    let bestHours: String

    /// True when the sun is actually capable of burning right now.
    var hasBurnRisk: Bool { uvIndex > 0 }

    /// Builds the full insight set from a live snapshot and its forecast series.
    ///
    /// Defaults match the product spec: Fitzpatrick type 3, no sunscreen (SPF 1).
    static func make(
        current: WeatherData,
        hourly: [HourlyPoint],
        dailyMaxTemperatures: [Double],
        skinType: FitzpatrickSkinType = .type3,
        spf: Int = 1
    ) -> HealthInsights {
        let assessment = ThermalPredictionEngine.assessHourlyRisk(
            temperature: current.temperature,
            humidity: current.humidity,
            uvIndex: Double(current.uvIndex),
            windSpeed: current.windSpeed
        )

        // The engine scans a labelled 24-hour series; map each hour to "HH:00".
        let forecast = hourly.map {
            (hour: String(format: "%02d:00", $0.hour),
             temp: $0.temperature,
             humidity: $0.humidity,
             uvIndex: Double($0.uvIndex),
             windSpeed: $0.windSpeed)
        }

        return HealthInsights(
            heatwaveAlert: ThermalPredictionEngine.detectHeatwave(
                dailyMaxTemperatures: dailyMaxTemperatures
            ),
            currentRiskLevel: assessment.level,
            currentRiskWarning: assessment.warning,
            isFoehnActive: assessment.isFoehnActive,
            minutesToBurn: ThermalPredictionEngine.calculateSafeExposureTime(
                uvIndex: Double(current.uvIndex),
                skinType: skinType,
                spfValue: spf
            ),
            uvIndex: current.uvIndex,
            skinType: skinType,
            spf: spf,
            bestHours: ThermalPredictionEngine.findBestHoursToGoOutside(
                hourlyForecasts: forecast
            )
        )
    }
}
