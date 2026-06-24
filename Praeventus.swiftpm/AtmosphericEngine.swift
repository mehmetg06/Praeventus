#if canImport(SwiftUI)
import SwiftUI

struct AtmosphericState: Equatable {
    let condition: WeatherCondition
    let symbolName: String
    let title: String
    let story: String
    let stormRisk: AtmosphericRisk
    let rainSignal: AtmosphericRisk
    let visibility: AtmosphericVisibility
    let cloudCover: Double
    let instability: Double
    let backgroundMood: BackgroundMood

    var statusText: String { title }
}

enum AtmosphericRisk: String, Equatable {
    case low = "Düşük"
    case moderate = "Orta"
    case high = "Yüksek"

    static func from(_ value: Double) -> AtmosphericRisk {
        switch value {
        case 0..<0.34: return .low
        case 0.34..<0.68: return .moderate
        default: return .high
        }
    }
}

enum AtmosphericVisibility: String, Equatable {
    case clear = "İyi"
    case reduced = "Azalmış"
    case poor = "Zayıf"
}

enum BackgroundMood: Equatable {
    case clear
    case partlyCloudy
    case cloudy
    case wet
    case storm
    case fog
    case snow
}

enum AtmosphericEngine {
    static func calculate(from weather: WeatherData) -> AtmosphericState {
        let humidity = clamp(weather.humidity / 100)
        let rain = clamp(weather.rainProbability / 100)
        let wind = clamp(weather.windSpeed / 90)
        let pressureDeficit = clamp((1013 - weather.pressure) / 33)
        let pressureExcess = clamp((weather.pressure - 1016) / 22)
        let heat = clamp((weather.temperature - 18) / 22)
        let cold = clamp((6 - weather.temperature) / 18)

        let instability = clamp(
            rain * 0.32 +
            humidity * 0.24 +
            pressureDeficit * 0.24 +
            wind * 0.16 +
            heat * humidity * 0.14 -
            pressureExcess * 0.18
        )

        let cloudCover = clamp(
            humidity * 0.42 +
            rain * 0.34 +
            pressureDeficit * 0.18 +
            wind * 0.04 -
            pressureExcess * 0.12
        )

        let stormScore = clamp(
            instability * 0.50 +
            rain * 0.18 +
            wind * 0.18 +
            pressureDeficit * 0.18
        )

        let visibilityScore = clamp(
            humidity * 0.38 +
            rain * 0.28 +
            cold * 0.20 -
            wind * 0.16
        )

        let resolvedCondition = resolveCondition(
            base: weather.condition,
            rain: rain,
            stormScore: stormScore,
            humidity: humidity,
            wind: wind,
            cold: cold,
            cloudCover: cloudCover,
            visibilityScore: visibilityScore
        )

        let visibility: AtmosphericVisibility = visibilityScore > 0.72 ? .poor : (visibilityScore > 0.48 ? .reduced : .clear)
        let rainSignal = AtmosphericRisk.from(rain)
        let stormRisk = AtmosphericRisk.from(stormScore)
        let mood = backgroundMood(for: resolvedCondition, stormScore: stormScore, rain: rain, visibilityScore: visibilityScore)
        let story = buildStory(
            weather: weather,
            condition: resolvedCondition,
            cloudCover: cloudCover,
            instability: instability,
            stormScore: stormScore,
            visibility: visibility
        )

        return AtmosphericState(
            condition: resolvedCondition,
            symbolName: resolvedCondition.symbolName,
            title: title(for: resolvedCondition, stormRisk: stormRisk, visibility: visibility),
            story: story,
            stormRisk: stormRisk,
            rainSignal: rainSignal,
            visibility: visibility,
            cloudCover: cloudCover,
            instability: instability,
            backgroundMood: mood
        )
    }

    private static func resolveCondition(
        base: WeatherCondition,
        rain: Double,
        stormScore: Double,
        humidity: Double,
        wind: Double,
        cold: Double,
        cloudCover: Double,
        visibilityScore: Double
    ) -> WeatherCondition {
        if cold > 0.50 && humidity > 0.62 && rain > 0.30 { return .snow }
        if stormScore > 0.66 { return .storm }
        if visibilityScore > 0.74 && wind < 0.35 { return .fog }
        if rain > 0.52 { return .rain }
        if cloudCover > 0.68 { return .cloudy }
        if cloudCover > 0.36 { return .partlyCloudy }
        if base == .snow || base == .storm || base == .fog || base == .rain { return base }
        return .clear
    }

    private static func backgroundMood(for condition: WeatherCondition, stormScore: Double, rain: Double, visibilityScore: Double) -> BackgroundMood {
        if condition == .snow { return .snow }
        if condition == .storm || stormScore > 0.66 { return .storm }
        if condition == .fog || visibilityScore > 0.72 { return .fog }
        if condition == .rain || rain > 0.48 { return .wet }
        if condition == .cloudy { return .cloudy }
        if condition == .partlyCloudy { return .partlyCloudy }
        return .clear
    }

    private static func title(for condition: WeatherCondition, stormRisk: AtmosphericRisk, visibility: AtmosphericVisibility) -> String {
        if stormRisk == .high { return "Atmosfer Kararsız" }
        if visibility == .poor { return "Görüş Zayıflıyor" }
        switch condition {
        case .clear: return "Atmosfer Parlak"
        case .partlyCloudy: return "Atmosfer Kararlı"
        case .cloudy: return "Bulutlanma Artıyor"
        case .rain: return "Yağış Sinyali Güçlü"
        case .storm: return "Konvektif Risk"
        case .fog: return "Yüzey Sisi Riski"
        case .snow: return "Soğuk Yağış Profili"
        }
    }

    private static func buildStory(
        weather: WeatherData,
        condition: WeatherCondition,
        cloudCover: Double,
        instability: Double,
        stormScore: Double,
        visibility: AtmosphericVisibility
    ) -> String {
        var parts: [String] = [weather.timeOfDay.storyPrefix]

        if stormScore > 0.66 {
            parts.append("Nem, düşük basınç ve rüzgar aynı yönde çalışıyor; atmosfer kararsızlaşıyor.")
        } else if weather.rainProbability > 55 {
            parts.append("Yağış sinyali belirgin. Bulut örtüsü ve nem birlikte artıyor.")
        } else if visibility == .poor {
            parts.append("Yüzey nemi yüksek ve karışım zayıf; görüş düşebilir.")
        } else if cloudCover > 0.65 {
            parts.append("Bulut örtüsü kuvvetli fakat fırtına enerjisi sınırlı görünüyor.")
        } else if instability < 0.30 {
            parts.append("Basınç ve nem dengeli; atmosfer daha sakin bir fazda.")
        } else {
            parts.append("Atmosfer geçiş halinde; kısa vadede küçük değişimler hissedilebilir.")
        }

        if weather.windSpeed > 55 {
            parts.append("Rüzgar kuvvetli, hissedilen hava ve bulut hareketi belirginleşir.")
        } else if weather.windSpeed < 8 && weather.humidity > 80 {
            parts.append("Rüzgar zayıf olduğu için nem yüzeyde kalabilir.")
        }

        return parts.joined(separator: " ")
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
#endif
