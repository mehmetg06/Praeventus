#if canImport(SwiftUI)
import SwiftUI

struct AtmosphericState: Equatable {
    let condition: WeatherCondition
    let symbolName: String
    let title: String
    var story: String
    let stormRisk: AtmosphericRisk
    let rainSignal: AtmosphericRisk
    let visibility: AtmosphericVisibility
    let cloudCover: Double
    let instability: Double
    let backgroundMood: BackgroundMood

    var statusText: String { title }
}

enum AtmosphericRisk: String, Equatable {
    case low
    case moderate
    case high

    var displayName: String {
        switch self {
        case .low: return String(localized: "risk.low", defaultValue: "Low")
        case .moderate: return String(localized: "risk.moderate", defaultValue: "Moderate")
        case .high: return String(localized: "risk.high", defaultValue: "High")
        }
    }

    static func from(_ value: Double) -> AtmosphericRisk {
        switch value {
        case 0..<0.34: return .low
        case 0.34..<0.68: return .moderate
        default: return .high
        }
    }
}

enum AtmosphericVisibility: String, Equatable {
    case clear
    case reduced
    case poor

    var displayName: String {
        switch self {
        case .clear: return String(localized: "visibility.clear", defaultValue: "Good")
        case .reduced: return String(localized: "visibility.reduced", defaultValue: "Reduced")
        case .poor: return String(localized: "visibility.poor", defaultValue: "Poor")
        }
    }
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
        return base
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
        if stormRisk == .high { return String(localized: "title.unstable", defaultValue: "Atmosphere Unstable") }
        if visibility == .poor { return String(localized: "title.lowVisibility", defaultValue: "Visibility Weakening") }
        switch condition {
        case .clear: return String(localized: "title.clear", defaultValue: "Atmosphere Bright")
        case .partlyCloudy: return String(localized: "title.partlyCloudy", defaultValue: "Atmosphere Stable")
        case .cloudy: return String(localized: "title.cloudy", defaultValue: "Cloud Cover Increasing")
        case .rain: return String(localized: "title.rain", defaultValue: "Strong Precipitation Signal")
        case .storm: return String(localized: "title.storm", defaultValue: "Convective Risk")
        case .fog: return String(localized: "title.fog", defaultValue: "Surface Fog Risk")
        case .snow: return String(localized: "title.snow", defaultValue: "Cold Precipitation Profile")
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
            parts.append(String(localized: "engineStory.storm", defaultValue: "Humidity, low pressure and wind are acting together; the atmosphere is becoming unstable."))
        } else if weather.rainProbability > 55 {
            parts.append(String(localized: "engineStory.rain", defaultValue: "The precipitation signal is clear. Cloud cover and humidity are rising together."))
        } else if visibility == .poor {
            parts.append(String(localized: "engineStory.lowVisibility", defaultValue: "Surface humidity is high and mixing is weak; visibility may drop."))
        } else if cloudCover > 0.65 {
            parts.append(String(localized: "engineStory.cloudy", defaultValue: "Cloud cover is strong, but storm energy looks limited."))
        } else if instability < 0.30 {
            parts.append(String(localized: "engineStory.calm", defaultValue: "Pressure and humidity are balanced; the atmosphere is in a calmer phase."))
        } else {
            parts.append(String(localized: "engineStory.transition", defaultValue: "The atmosphere is in transition; small short-term changes may be felt."))
        }

        if weather.windSpeed > 55 {
            parts.append(String(localized: "engineStory.windStrong", defaultValue: "Wind is strong, making the felt conditions and cloud motion more pronounced."))
        } else if weather.windSpeed < 8 && weather.humidity > 80 {
            parts.append(String(localized: "engineStory.windWeak", defaultValue: "Because wind is weak, humidity may linger near the surface."))
        }

        return parts.joined(separator: " ")
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
#endif
