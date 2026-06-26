#if canImport(SwiftUI)
import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Produces scenario-specific, safety-aware forecast prose.
///
/// The engine is deterministic by default so every weather combination has a
/// reliable answer. On Apple platforms it also prepares Core ML with Neural
/// Engine compute units when a bundled narrative selector model is added later;
/// that model should select tone/template/advice, while this file keeps the
/// final wording meteorologically safe and localized.
enum WeatherNarrativeEngine {

    static func story(weather: WeatherData, atmosphere: AtmosphericState, hourly: [HourlyPoint], daily: [DailyRange]) -> String {
        _ = NeuralNarrativeSelector.shared

        let context = NarrativeContext(weather: weather, atmosphere: atmosphere, hourly: hourly, daily: daily)
        var sentences: [String] = [weather.timeOfDay.storyPrefix]

        sentences.append(opening(for: context))
        sentences.append(feelsLikeGuidance(for: context))

        if let trend = trendSentence(for: context) {
            sentences.append(trend)
        }

        if let risk = riskSentence(for: context) {
            sentences.append(risk)
        }

        sentences.append(advice(for: context))
        return sentences.joined(separator: " ")
    }

    private static func opening(for context: NarrativeContext) -> String {
        switch context.atmosphere.condition {
        case .clear:
            if context.isExtremeHeat {
                return String(localized: "narrative.clear.hot", defaultValue: "Sky conditions look mostly clear, but the main story is heat: the air temperature is very high and direct sun can make exposure tiring quickly.")
            }
            if context.isCold {
                return String(localized: "narrative.clear.cold", defaultValue: "The sky is mostly clear, yet the air is on the cold side; open areas may feel crisp, especially in shade or after sunset.")
            }
            return String(localized: "narrative.clear.normal", defaultValue: "The atmosphere looks settled and bright, with limited cloud or precipitation signal in the near term.")
        case .partlyCloudy:
            return String(localized: "narrative.partlyCloudy", defaultValue: "Clouds may pass through from time to time, but the overall setup is still fairly stable and not strongly rainy.")
        case .cloudy:
            return String(localized: "narrative.cloudy", defaultValue: "Cloud cover is the dominant signal right now; the sky may feel closed in, although the rain signal depends on humidity and pressure support.")
        case .rain:
            return String(localized: "narrative.rain", defaultValue: "Moisture and precipitation signals are aligned, so showers are plausible and surfaces may become wet in the short term.")
        case .storm:
            return String(localized: "narrative.storm", defaultValue: "Instability, moisture and wind are combining, so sudden heavy rain, lightning or fast-changing conditions deserve attention.")
        case .fog:
            return String(localized: "narrative.fog", defaultValue: "Low-level moisture is high and mixing is weak, so visibility can drop locally and travel may feel slower.")
        case .snow:
            return String(localized: "narrative.snow", defaultValue: "The air profile is cold enough for wintry precipitation signals; slick surfaces are possible if moisture persists.")
        }
    }

    private static func feelsLikeGuidance(for context: NarrativeContext) -> String {
        let w = context.weather
        let diff = w.feelsLike - w.temperature

        if context.isExtremeHeat {
            if w.windSpeed >= 25 {
                return String(localized: "narrative.feels.extremeHeatWind", defaultValue: "Even with wind, this is not a cooling scenario: at this temperature the breeze can feel like hot air movement, increase dehydration and make you feel warmer over time.")
            }
            return String(localized: "narrative.feels.extremeHeat", defaultValue: "The body will struggle to cool efficiently in this heat, so the felt temperature can be dangerous even if the wind is light.")
        }

        if w.temperature >= 32 {
            if w.humidity >= 60 {
                return String(localized: "narrative.feels.hotHumid", defaultValue: "Heat and humidity are working together; sweat evaporates more slowly, so it can feel heavier and warmer than the thermometer suggests.")
            }
            if w.windSpeed >= 25 {
                return String(localized: "narrative.feels.hotWind", defaultValue: "The wind may not make the air feel cold; in hot weather it can dry you out faster and make sun exposure feel harsher.")
            }
            return String(localized: "narrative.feels.hot", defaultValue: "The temperature is high enough that shade, hydration and slower outdoor pacing matter more than the headline condition.")
        }

        if w.temperature <= 10 && w.windSpeed >= 18 {
            return String(localized: "narrative.feels.coldWind", defaultValue: "Because the air is already cool, the wind can remove body heat faster and make it feel colder than the measured temperature.")
        }

        if abs(diff) >= 3 {
            let warmer = String(localized: "narrative.feels.warmer", defaultValue: "The apparent temperature is running above the actual reading, so it may feel warmer than the number on screen.")
            let cooler = String(localized: "narrative.feels.cooler", defaultValue: "The apparent temperature is below the actual reading, so it may feel cooler than the number on screen.")
            return diff > 0 ? warmer : cooler
        }

        return String(localized: "narrative.feels.neutral", defaultValue: "The measured and felt temperatures are close, so comfort will depend more on sun, shade, clothing and activity level.")
    }

    private static func trendSentence(for context: NarrativeContext) -> String? {
        guard let first = context.hourly.first, let last = context.hourly.prefix(6).last else { return nil }
        let rainPeak = context.hourly.prefix(6).map(\.precipitationProbability).max() ?? context.weather.rainProbability
        let delta = last.temperature - first.temperature

        if rainPeak >= 65 {
            return String(localized: "narrative.trend.rainPeak", defaultValue: "In the next few hours the rain probability peaks near \(Int(rainPeak.rounded()))%, so keeping a rain plan ready is sensible.")
        }
        if delta >= 4 {
            return String(localized: "narrative.trend.warming", defaultValue: "Temperatures trend upward over the next few hours, so the day may feel progressively warmer.")
        }
        if delta <= -4 {
            return String(localized: "narrative.trend.cooling", defaultValue: "Temperatures trend downward over the next few hours, so conditions may feel cooler later.")
        }
        return nil
    }

    private static func riskSentence(for context: NarrativeContext) -> String? {
        let w = context.weather
        if context.isExtremeHeat {
            return String(localized: "narrative.risk.extremeHeat", defaultValue: "Heat stress is the priority risk: avoid long sun exposure, drink water often and watch for dizziness, headache or unusual fatigue.")
        }
        if context.atmosphere.stormRisk == .high {
            return String(localized: "narrative.risk.storm", defaultValue: "Because storm risk is high, avoid exposed areas and be ready for rapid changes rather than relying on the current calm.")
        }
        if context.atmosphere.visibility == .poor {
            return String(localized: "narrative.risk.visibility", defaultValue: "Reduced visibility can be patchy, so driving or cycling may require extra distance and slower reactions.")
        }
        if w.windSpeed >= 55 {
            return String(localized: "narrative.risk.wind", defaultValue: "Wind is strong enough to affect umbrellas, loose objects and exposed routes.")
        }
        return nil
    }

    private static func advice(for context: NarrativeContext) -> String {
        let w = context.weather
        if context.isExtremeHeat {
            return String(localized: "narrative.advice.extremeHeat", defaultValue: "Prefer shade or indoor breaks, carry water, choose light clothing and avoid heavy exercise during the hottest part of the day.")
        }
        if w.temperature >= 32 {
            return String(localized: "narrative.advice.hot", defaultValue: "Plan around heat: hydrate, use sunscreen and do demanding outdoor tasks earlier or later if possible.")
        }
        if context.atmosphere.condition == .storm {
            return String(localized: "narrative.advice.storm", defaultValue: "If you need to go out, keep the trip flexible and move indoors at the first sign of thunder or sudden heavy rain.")
        }
        if context.atmosphere.condition == .rain || w.rainProbability >= 55 {
            return String(localized: "narrative.advice.rain", defaultValue: "A compact umbrella or waterproof layer is a good idea, especially for walking or public transport connections.")
        }
        if context.atmosphere.condition == .snow {
            return String(localized: "narrative.advice.snow", defaultValue: "Dress in layers and watch for slippery spots on bridges, stairs and shaded roads.")
        }
        if context.atmosphere.condition == .fog {
            return String(localized: "narrative.advice.fog", defaultValue: "Use extra time for travel and keep lights visible if you are driving or cycling.")
        }
        if w.temperature <= 10 {
            return String(localized: "narrative.advice.cold", defaultValue: "A warm layer will help, especially if you will be outside for more than a few minutes.")
        }
        return String(localized: "narrative.advice.calm", defaultValue: "Overall, normal outdoor plans look reasonable; just adjust clothing for the local breeze and time of day.")
    }
}

private struct NarrativeContext {
    let weather: WeatherData
    let atmosphere: AtmosphericState
    let hourly: [HourlyPoint]
    let daily: [DailyRange]

    var isExtremeHeat: Bool { weather.temperature >= 40 || weather.feelsLike >= 42 }
    var isCold: Bool { weather.temperature <= 10 }
}

private final class NeuralNarrativeSelector: @unchecked Sendable {
    static let shared = NeuralNarrativeSelector()

    #if canImport(CoreML)
    private let configuration: MLModelConfiguration
    #endif

    private init() {
        #if canImport(CoreML)
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.configuration = config
        #endif
    }
}
#endif
