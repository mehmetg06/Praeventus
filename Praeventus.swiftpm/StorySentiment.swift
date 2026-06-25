import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Risk severity that drives the warning-card tint in the UI.
enum WeatherSeverity {
    case calm
    case caution
    case alert

    var isNegative: Bool { self == .alert }
}

/// Combines the deterministic `AtmosphericEngine` signal with an on-device
/// NaturalLanguage sentiment read of the generated story.
///
/// Everything runs locally — no network, no LLM, no data leaves the device.
///
/// Caveat: `NLTagger`'s `.sentimentScore` only supports a limited set of
/// languages (Turkish, for example, may score ~0). So the engine-derived
/// severity is always the baseline; NL sentiment can only *raise* the level
/// when it detects clearly negative language. This keeps behaviour correct in
/// every locale.
enum StorySentiment {

    static func severity(story: String, instability: Double, stormRiskIsHigh: Bool) -> WeatherSeverity {
        var level = engineSeverity(instability: instability, stormRiskIsHigh: stormRiskIsHigh)

        if let score = sentimentScore(for: story) {
            if score <= -0.5 {
                level = .alert
            } else if score <= -0.2 && level == .calm {
                level = .caution
            }
        }
        return level
    }

    private static func engineSeverity(instability: Double, stormRiskIsHigh: Bool) -> WeatherSeverity {
        if stormRiskIsHigh || instability > 0.66 { return .alert }
        if instability > 0.40 { return .caution }
        return .calm
    }

    /// On-device sentiment in [-1, 1], or `nil` if unsupported for this text.
    static func sentimentScore(for text: String) -> Double? {
        #if canImport(NaturalLanguage)
        guard !text.isEmpty else { return nil }
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        guard let raw = tag?.rawValue, let value = Double(raw) else { return nil }
        // NL returns 0 for unsupported languages; treat that as "no signal".
        return value == 0 ? nil : value
        #else
        return nil
        #endif
    }
}
