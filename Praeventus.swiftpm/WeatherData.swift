import Foundation

/// Plain weather snapshot consumed by `AtmosphericEngine` and the UI.
///
/// This type is intentionally Foundation-only (no SwiftUI) so the data + mapping
/// layer compiles and can be exercised on any platform, including Linux CI.
struct WeatherData: Equatable {
    var city: String
    var country: String
    var temperature: Double
    var feelsLike: Double
    var condition: WeatherCondition
    var humidity: Double
    var pressure: Double
    var windSpeed: Double
    var rainProbability: Double
    var hour: Double

    var timeOfDay: TimeOfDay {
        TimeOfDay(hour: Int(hour.rounded()))
    }

    var formattedHour: String {
        String(format: "%02d:00", Int(hour.rounded()) % 24)
    }

    var statusText: String {
        switch condition {
        case .clear: return String(localized: "status.clear", defaultValue: "Atmosphere Bright")
        case .partlyCloudy: return String(localized: "status.partlyCloudy", defaultValue: "Atmosphere Stable")
        case .cloudy: return String(localized: "status.cloudy", defaultValue: "Cloud Cover Increasing")
        case .rain: return String(localized: "status.rain", defaultValue: "Precipitation Active")
        case .storm: return String(localized: "status.storm", defaultValue: "Convective Risk")
        case .fog: return String(localized: "status.fog", defaultValue: "Visibility Dropping")
        case .snow: return String(localized: "status.snow", defaultValue: "Cold Core")
        }
    }

    var story: String {
        let timePrefix = timeOfDay.storyPrefix
        switch condition {
        case .clear:
            return timePrefix + " " + String(localized: "story.clear", defaultValue: "Pressure is balanced. Humidity is low to moderate. The sky may stay clear and calm in the coming hours.")
        case .partlyCloudy:
            return timePrefix + " " + String(localized: "story.partlyCloudy", defaultValue: "The atmosphere is generally stable. Local clouds may form, but no strong precipitation signal stands out.")
        case .cloudy:
            return timePrefix + " " + String(localized: "story.cloudy", defaultValue: "Humidity and cloud cover are rising. If pressure does not drop sharply, precipitation risk may stay limited.")
        case .rain:
            return timePrefix + " " + String(localized: "story.rain", defaultValue: "Humidity is high and the precipitation signal is clear. Intermittent rain can be expected in the short term.")
        case .storm:
            return timePrefix + " " + String(localized: "story.storm", defaultValue: "Falling pressure, high humidity and wind together are destabilizing the atmosphere. Watch for sudden showers and storms.")
        case .fog:
            return timePrefix + " " + String(localized: "story.fog", defaultValue: "Surface humidity is high. With weak wind, visibility may drop and a fog layer can form.")
        case .snow:
            return timePrefix + " " + String(localized: "story.snow", defaultValue: "The cold air profile is strengthening. With enough moisture, snow or sleet may occur.")
        }
    }
}

enum TimeOfDay: String, Equatable {
    case dawn
    case day
    case sunset
    case night

    init(hour: Int) {
        let normalized = ((hour % 24) + 24) % 24
        switch normalized {
        case 5...8:
            self = .dawn
        case 9...16:
            self = .day
        case 17...20:
            self = .sunset
        default:
            self = .night
        }
    }

    /// Localized display name (e.g. "Day" / "Gündüz").
    var displayName: String {
        switch self {
        case .dawn: return String(localized: "timeOfDay.dawn", defaultValue: "Dawn")
        case .day: return String(localized: "timeOfDay.day", defaultValue: "Day")
        case .sunset: return String(localized: "timeOfDay.sunset", defaultValue: "Sunset")
        case .night: return String(localized: "timeOfDay.night", defaultValue: "Night")
        }
    }

    var storyPrefix: String {
        switch self {
        case .dawn: return String(localized: "storyPrefix.dawn", defaultValue: "With the morning light, the surface layer is just warming up.")
        case .day: return String(localized: "storyPrefix.day", defaultValue: "Daytime heating makes the atmosphere more visible.")
        case .sunset: return String(localized: "storyPrefix.sunset", defaultValue: "At sunset the surface begins to cool.")
        case .night: return String(localized: "storyPrefix.night", defaultValue: "At night, radiative cooling and weak mixing dominate.")
        }
    }

    var darkness: Double {
        switch self {
        case .dawn: return 0.08
        case .day: return 0.0
        case .sunset: return 0.16
        case .night: return 0.48
        }
    }

    var warmth: Double {
        switch self {
        case .dawn: return 0.16
        case .day: return 0.08
        case .sunset: return 0.30
        case .night: return 0.0
        }
    }

    var coolness: Double {
        switch self {
        case .dawn: return 0.12
        case .day: return 0.0
        case .sunset: return 0.04
        case .night: return 0.28
        }
    }
}

enum WeatherCondition: String, CaseIterable, Identifiable, Equatable {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case storm
    case fog
    case snow

    var id: String { rawValue }

    /// Localized display name (e.g. "Clear" / "Açık").
    var displayName: String {
        switch self {
        case .clear: return String(localized: "condition.clear", defaultValue: "Clear")
        case .partlyCloudy: return String(localized: "condition.partlyCloudy", defaultValue: "Partly Cloudy")
        case .cloudy: return String(localized: "condition.cloudy", defaultValue: "Cloudy")
        case .rain: return String(localized: "condition.rain", defaultValue: "Rainy")
        case .storm: return String(localized: "condition.storm", defaultValue: "Stormy")
        case .fog: return String(localized: "condition.fog", defaultValue: "Foggy")
        case .snow: return String(localized: "condition.snow", defaultValue: "Snowy")
        }
    }

    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .storm: return "cloud.bolt.rain.fill"
        case .fog: return "cloud.fog.fill"
        case .snow: return "snowflake"
        }
    }
}
