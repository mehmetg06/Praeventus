import Foundation

/// On-device thermal & UV hazard engine for Praeventus.
///
/// Foundation-only (no SwiftUI, no network, no LLM) so it compiles and runs on
/// Linux/macOS CLI alongside the rest of the data + domain layer. Every health
/// decision here is a hardcoded scientific heuristic: heat-index physics,
/// Foehn-wind heat stress, Fitzpatrick photobiology, and solar geometry.
///
/// All user-facing warning copy is intentionally Turkish, since these are
/// medical-grade safety messages shown verbatim to the user.

/// Coarse risk band for a single hour of outdoor exposure.
enum ActivityRiskLevel: Int, Comparable {
    case safe = 0
    case caution = 1
    case extremeDanger = 2

    static func < (lhs: ActivityRiskLevel, rhs: ActivityRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Medical-grade Turkish guidance for the band.
    var warning: String {
        switch self {
        case .safe:
            return "Termal risk düşük. Açık havada bulunmak güvenli; yine de su tüketmeyi ihmal etmeyin."
        case .caution:
            return "Orta düzey termal stres. Doğrudan güneşten kaçının, sık sık su için ve mümkünse gölgeyi tercih edin."
        case .extremeDanger:
            return "Aşırı termal tehlike! Sıcak çarpması riski yüksek. Açık havaya çıkmayın; serin ve kapalı bir alanda kalın, bol sıvı alın."
        }
    }
}

/// Result of evaluating one hour of conditions.
struct ThermalAssessment: Equatable {
    let riskScore: Double
    let level: ActivityRiskLevel
    let isFoehnActive: Bool

    /// Full Turkish warning, including a Foehn-effect note when the hot wind
    /// is actively amplifying — rather than relieving — heat stress.
    var warning: String {
        guard isFoehnActive else { return level.warning }
        return level.warning + " "
            + "Föhn etkisi: Sıcak ve kuru rüzgâr serinletmiyor; terlemeyi hızlandırarak su kaybını ve sıcak çarpması riskini artırıyor."
    }
}

/// The six Fitzpatrick phototypes, ordered by melanin / burn resistance.
enum FitzpatrickSkinType: Int, CaseIterable {
    case type1 = 1   // Very fair, always burns, never tans
    case type2 = 2   // Fair, burns easily, tans minimally
    case type3 = 3   // Medium, sometimes burns, tans gradually
    case type4 = 4   // Olive, rarely burns, tans easily
    case type5 = 5   // Brown, very rarely burns
    case type6 = 6   // Deeply pigmented, almost never burns

    /// Minimal erythema baseline (minutes) at the WHO reference of UV index 3.
    var baseSafeMinutesAtUV3: Double {
        switch self {
        case .type1: return 10
        case .type2: return 15
        case .type3: return 20
        case .type4: return 30
        case .type5: return 40
        case .type6: return 60
        }
    }
}

final class ThermalPredictionEngine {

    // MARK: - Tunable thresholds

    /// Apparent temperature above which a hot wind stops cooling and starts
    /// harming (Foehn / "hair-dryer" regime).
    private static let foehnTempThreshold = 36.0
    /// Wind speed (km/h) above which moving air drives, rather than relieves,
    /// dehydration once it is hot.
    private static let foehnWindThreshold = 15.0
    /// WHO "low" UV ceiling — at or below this, unprotected exposure is benign.
    private static let lowUVThreshold = 3.0
    /// Solar elevation above which a person's shadow is shorter than their
    /// height, i.e. UV is near its daily peak.
    private static let shadowRuleElevation = 45.0

    // MARK: - Feature 1: Hourly thermal risk & the Foehn effect

    /// Scores a single hour of conditions on a 0…~190 hazard scale.
    ///
    /// Heat load is driven by the apparent temperature (heat index) rather than
    /// the raw thermometer reading, because humidity is what defeats the body's
    /// evaporative cooling. UV adds a photobiological load on top. Wind is the
    /// subtle part: a breeze normally sheds heat, but once the air is hot and
    /// fast (the Foehn regime) it accelerates dehydration, so we *add* to the
    /// score instead of subtracting from it.
    static func calculateRiskScore(
        temperature: Double,
        humidity: Double,
        uvIndex: Double,
        windSpeed: Double
    ) -> Double {
        var score = 0.0

        // Thermal load from apparent temperature (NWS heat-index bands, °C).
        let apparent = heatIndex(temperatureC: temperature, humidity: humidity)
        switch apparent {
        case ..<27:     score += 0
        case 27..<32:   score += 25   // Caution
        case 32..<41:   score += 50   // Extreme caution
        case 41..<54:   score += 80   // Danger
        default:        score += 110  // Extreme danger / heat stroke imminent
        }

        // UV photobiological load, capped so it cannot alone dominate the score.
        score += min(uvIndex * 3.0, 30)

        // Wind: cooling in the normal regime, additional danger in the Foehn one.
        if temperature > foehnTempThreshold && windSpeed > foehnWindThreshold {
            // Hot, dry, fast air — never a relief; scale danger with wind.
            score += min((windSpeed - foehnWindThreshold) * 1.5 + 15, 45)
        } else {
            // Convective relief from a benign breeze.
            score -= min(windSpeed * 0.8, 15)
        }

        return max(0, score)
    }

    /// Full assessment (score + band + Foehn flag + Turkish warning) for an hour.
    static func assessHourlyRisk(
        temperature: Double,
        humidity: Double,
        uvIndex: Double,
        windSpeed: Double
    ) -> ThermalAssessment {
        let score = calculateRiskScore(
            temperature: temperature,
            humidity: humidity,
            uvIndex: uvIndex,
            windSpeed: windSpeed
        )
        let isFoehnActive = temperature > foehnTempThreshold && windSpeed > foehnWindThreshold
        return ThermalAssessment(riskScore: score, level: riskLevel(for: score), isFoehnActive: isFoehnActive)
    }

    /// Maps a raw hazard score onto the coarse risk band.
    static func riskLevel(for score: Double) -> ActivityRiskLevel {
        switch score {
        case ..<35:     return .safe
        case 35..<75:   return .caution
        default:        return .extremeDanger
        }
    }

    // MARK: - Feature 2: Heatwave detection (7-day array)

    /// Returns a persistent heatwave alert when 3+ consecutive days reach
    /// 35 °C or above, otherwise `nil`.
    static func detectHeatwave(dailyMaxTemperatures: [Double]) -> String? {
        var consecutive = 0
        var longestRun = 0

        for maxTemp in dailyMaxTemperatures {
            if maxTemp >= 35.0 {
                consecutive += 1
                longestRun = max(longestRun, consecutive)
            } else {
                consecutive = 0
            }
        }

        guard longestRun >= 3 else { return nil }

        return "Sıcak Hava Dalgası uyarısı: Önümüzdeki günlerde \(longestRun) gün üst üste sıcaklık 35°C ve üzerinde seyredecek. "
            + "Gün ortasında dışarı çıkmaktan kaçının, bol su için ve serin kalın."
    }

    // MARK: - Feature 3: Fitzpatrick "time-to-burn" calculator

    /// Estimates the unprotected minutes before erythema (skin reddening) for a
    /// given UV index, phototype, and sunscreen SPF.
    ///
    /// Safe time = base time × (3 / current UV) × SPF, anchored to the WHO
    /// reference UV of 3. UV is treated purely as a hazard to be minimized:
    /// the returned value is the *ceiling* of safe exposure, not a target.
    static func calculateSafeExposureTime(
        uvIndex: Double,
        skinType: FitzpatrickSkinType,
        spfValue: Int = 1
    ) -> Int {
        // No meaningful UV (night / heavy overcast): no burn pressure.
        guard uvIndex > 0 else { return Int(skinType.baseSafeMinutesAtUV3 * 60) }

        let spf = max(1, spfValue)
        let safeMinutes = skinType.baseSafeMinutesAtUV3 * (3.0 / uvIndex) * Double(spf)
        return max(0, Int(safeMinutes.rounded(.down)))
    }

    // MARK: - Feature 4: The astronomical shadow rule

    /// Triggers the "shadow rule" when the sun is high enough that a person's
    /// shadow is shorter than their height — the practical sign that UV is at
    /// or near its daily peak.
    static func shadowRuleWarning(solarElevationAngle: Double) -> String? {
        guard solarElevationAngle > shadowRuleElevation else { return nil }
        return "Gölgeniz boyunuzdan kısa, UV radyasyonu tepe noktasında. Derhal gölgeye geçin."
    }

    // MARK: - Feature 5: The optimal outdoor window (best hours finder)

    /// Scans a 24-hour forecast and returns a formatted Turkish recommendation
    /// of the continuous windows that are strictly `.safe` *and* low-UV.
    static func findBestHoursToGoOutside(
        hourlyForecasts: [(hour: String, temp: Double, humidity: Double, uvIndex: Double, windSpeed: Double)]
    ) -> String {
        var windows: [String] = []
        var runStartLabel: String?
        var runEndHour: Int?

        func closeRun() {
            if let start = runStartLabel, let end = runEndHour {
                windows.append("\(start) - \(formatHour(end))")
            }
            runStartLabel = nil
            runEndHour = nil
        }

        for forecast in hourlyForecasts {
            let level = riskLevel(
                for: calculateRiskScore(
                    temperature: forecast.temp,
                    humidity: forecast.humidity,
                    uvIndex: forecast.uvIndex,
                    windSpeed: forecast.windSpeed
                )
            )
            let isComfortable = level == .safe && forecast.uvIndex <= lowUVThreshold

            if isComfortable, let startHour = parseHour(forecast.hour) {
                if runStartLabel == nil { runStartLabel = forecast.hour }
                runEndHour = startHour + 1   // window extends to the end of this hour
            } else {
                closeRun()
            }
        }
        closeRun()

        guard !windows.isEmpty else {
            return "Bugün dışarı çıkmak için güvenli bir saat dilimi bulunmuyor, lütfen kapalı alanlarda kalın."
        }

        return "Bugün dışarı çıkmak için en elverişli ve serin saatler: " + windows.joined(separator: " ile ") + " arası."
    }

    // MARK: - Feature 6: Cold stress (wind chill, hypothermia & frostbite)

    /// Environment Canada wind-chill index in °C. Valid for cold, breezy air;
    /// for mild or near-still conditions it returns the air temperature so the
    /// caller can treat "no meaningful chill" uniformly.
    static func windChillIndex(temperatureC: Double, windSpeedKmh: Double) -> Double {
        guard temperatureC <= 10.0, windSpeedKmh > 4.8 else { return temperatureC }
        let v = pow(windSpeedKmh, 0.16)
        return 13.12 + 0.6215 * temperatureC - 11.37 * v + 0.3965 * temperatureC * v
    }

    /// Cold-exposure band + Turkish guidance from the wind-chill apparent
    /// temperature, or `nil` when it is not cold enough to be a hazard. Mirrors
    /// the heat path so the UI can headline whichever extreme is worse.
    static func assessColdRisk(temperature: Double, windSpeed: Double) -> (level: ActivityRiskLevel, warning: String)? {
        let apparent = windChillIndex(temperatureC: temperature, windSpeedKmh: windSpeed)
        let felt = Int(apparent.rounded())
        switch apparent {
        case ..<(-27):
            return (.extremeDanger,
                "Aşırı soğuk tehlikesi! Hissedilen sıcaklık \(felt)°C. Açıkta kalan ciltte birkaç dakika içinde donma (frostbite) ve hipotermi riski var. Dışarı çıkmayın; çıkmanız gerekirse tüm cildi örtün.")
        case -27 ..< (-10):
            return (.caution,
                "Şiddetli soğuk. Hissedilen sıcaklık \(felt)°C. Uzun süre dışarıda kalmak hipotermiye yol açabilir; katmanlı giyinin ve cildinizi rüzgârdan koruyun.")
        default:
            return nil
        }
    }

    // MARK: - Heat index (apparent temperature)

    /// NWS Rothfusz heat-index regression, expressed in °C.
    ///
    /// Below ~27 °C the regression is not meaningful, so we return the raw
    /// temperature; above it we apply the full formula plus the standard
    /// low/high-humidity adjustments.
    static func heatIndex(temperatureC: Double, humidity: Double) -> Double {
        guard temperatureC >= 27 else { return temperatureC }

        let t = temperatureC * 9.0 / 5.0 + 32.0   // °F, the regression's native unit
        let r = max(0, min(100, humidity))

        var hi = -42.379
            + 2.04901523 * t
            + 10.14333127 * r
            - 0.22475541 * t * r
            - 0.00683783 * t * t
            - 0.05481717 * r * r
            + 0.00122874 * t * t * r
            + 0.00085282 * t * r * r
            - 0.00000199 * t * t * r * r

        // Dry-air correction (low humidity overstates relief).
        if r < 13 && t >= 80 && t <= 112 {
            hi -= ((13 - r) / 4) * sqrt((17 - abs(t - 95)) / 17)
        }
        // Humid-air correction (cooling fails faster than the base curve).
        else if r > 85 && t >= 80 && t <= 87 {
            hi += ((r - 85) / 10) * ((87 - t) / 5)
        }

        return (hi - 32.0) * 5.0 / 9.0   // back to °C
    }

    // MARK: - Hour-string helpers

    /// Parses the leading hour from a `"HH:mm"` label, e.g. `"07:00"` → `7`.
    private static func parseHour(_ label: String) -> Int? {
        Int(label.prefix(2)) ?? Int(label.split(separator: ":").first ?? "")
    }

    /// Renders an hour-of-day back to a `"HH:00"` label.
    private static func formatHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
