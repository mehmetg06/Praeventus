import Foundation

/// Ready-to-display bundle of `ThermalPredictionEngine` output for the current
/// location.
///
/// Foundation-only (no SwiftUI) so it stays exercisable on the macOS/Linux CLI
/// like the rest of the data + domain layer. Everything here is a derived view
/// of live weather — it holds no state and is recomputed on demand.
/// Whether the dominant thermal hazard right now is heat or cold.
enum ThermalRiskKind: Equatable { case heat, cold }

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
    /// Whether the headline risk is a heat or a cold hazard (drives the icon).
    let riskKind: ThermalRiskKind

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
        let heat = ThermalPredictionEngine.assessHourlyRisk(
            temperature: current.temperature,
            humidity: current.humidity,
            uvIndex: Double(current.uvIndex),
            windSpeed: current.windSpeed
        )
        let cold = ThermalPredictionEngine.assessColdRisk(
            temperature: current.temperature,
            windSpeed: current.windSpeed
        )

        // Headline whichever extreme is more severe; ties go to cold, since at
        // freezing temperatures the heat band is `.safe` by construction.
        let riskKind: ThermalRiskKind
        let level: ActivityRiskLevel
        let warning: String
        if let cold, cold.level >= heat.level {
            riskKind = .cold
            level = cold.level
            warning = cold.warning
        } else {
            riskKind = .heat
            level = heat.level
            warning = heat.warning
        }

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
            currentRiskLevel: level,
            currentRiskWarning: warning,
            isFoehnActive: heat.isFoehnActive,
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
            ),
            riskKind: riskKind
        )
    }
}

// MARK: - Forced sandbox states

extension HealthInsights {
    /// Sandbox: force the card into an extreme-heat / heatstroke state.
    static var forcedHeatstroke: HealthInsights {
        HealthInsights(
            heatwaveAlert: "Sıcak Hava Dalgası uyarısı: Önümüzdeki günlerde sıcaklık 35°C ve üzerinde seyredecek. Gün ortasında dışarı çıkmaktan kaçının, bol su için ve serin kalın.",
            currentRiskLevel: .extremeDanger,
            currentRiskWarning: ActivityRiskLevel.extremeDanger.warning
                + " Föhn etkisi: Sıcak ve kuru rüzgâr serinletmiyor; terlemeyi hızlandırarak su kaybını ve sıcak çarpması riskini artırıyor.",
            isFoehnActive: true,
            minutesToBurn: 6,
            uvIndex: 11,
            skinType: .type3,
            spf: 1,
            bestHours: "Bugün dışarı çıkmak için güvenli bir saat dilimi bulunmuyor, lütfen kapalı alanlarda kalın.",
            riskKind: .heat
        )
    }

    /// Sandbox: force the card into a frostbite / hypothermia cold-stress state.
    static var forcedHypothermia: HealthInsights {
        let cold = ThermalPredictionEngine.assessColdRisk(temperature: -40, windSpeed: 120)
        return HealthInsights(
            heatwaveAlert: nil,
            currentRiskLevel: .extremeDanger,
            currentRiskWarning: cold?.warning
                ?? "Aşırı soğuk tehlikesi! Donma ve hipotermi riski yüksek.",
            isFoehnActive: false,
            minutesToBurn: ThermalPredictionEngine.calculateSafeExposureTime(uvIndex: 0, skinType: .type3),
            uvIndex: 0,
            skinType: .type3,
            spf: 1,
            bestHours: "Şiddetli soğuk nedeniyle dışarısı güvenli değil; kapalı ve ısıtılmış bir alanda kalın.",
            riskKind: .cold
        )
    }

    /// Sandbox: force the card into an extreme-UV warning state.
    static var forcedExtremeUV: HealthInsights {
        HealthInsights(
            heatwaveAlert: nil,
            currentRiskLevel: .caution,
            currentRiskWarning: "Aşırı UV uyarısı: UV indeksi tepe seviyede. Gölgeniz boyunuzdan kısa; korumasız ciltte birkaç dakikada yanık oluşabilir. Gölgede kalın, güneş kremi ve koruyucu giysi kullanın.",
            isFoehnActive: false,
            minutesToBurn: 4,
            uvIndex: 12,
            skinType: .type3,
            spf: 1,
            bestHours: "UV'nin en zayıf olduğu erken sabah ve akşam saatlerini tercih edin.",
            riskKind: .heat
        )
    }
}
