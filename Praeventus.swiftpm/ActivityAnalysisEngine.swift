import Foundation

enum ActivityAnalysisEngine {

    static func evaluateSuitability(for activity: Activity, given weather: WeatherData) -> ActivitySuitability {
        var warnings: [String] = []
        var score = 100.0

        if weather.temperature < activity.minTemperature {
            warnings.append(String(localized: "warning.tooCol", defaultValue: "Too cold for this activity"))
            score -= 15
        } else if weather.temperature > activity.maxTemperature {
            warnings.append(String(localized: "warning.tooWarm", defaultValue: "Too warm for this activity"))
            score -= 15
        }

        if weather.windGustSpeed > activity.maxWindGust {
            warnings.append(String(localized: "warning.strongWindGusts", defaultValue: "Strong wind gusts"))
            score -= 20
        } else if weather.windSpeed > activity.maxWindSpeed {
            warnings.append(String(localized: "warning.windyConditions", defaultValue: "Windy conditions"))
            score -= 10
        }

        if weather.visibility < activity.minVisibility {
            warnings.append(String(localized: "warning.lowVisibility", defaultValue: "Low visibility"))
            score -= 15
        }

        if weather.uvIndex > activity.maxUVIndex {
            warnings.append(String(localized: "warning.highUV", defaultValue: "High UV exposure"))
            score -= 10
        }

        if activity.avoidRain && weather.condition == .rain {
            warnings.append(String(localized: "warning.rainy", defaultValue: "Rain in forecast"))
            score -= 25
        }

        if activity.avoidSnow && weather.condition == .snow {
            warnings.append(String(localized: "warning.snowy", defaultValue: "Snow in forecast"))
            score -= 25
        }

        if activity.avoidFog && weather.condition == .fog {
            warnings.append(String(localized: "warning.foggy", defaultValue: "Fog conditions"))
            score -= 20
        }

        if activity.avoidStorm && weather.condition == .storm {
            warnings.append(String(localized: "warning.stormy", defaultValue: "Storm risk"))
            score -= 30
        }

        let suitability = suitabilityLevel(from: score)
        let recommendations = generateRecommendations(for: activity, weather: weather, suitability: suitability)

        return ActivitySuitability(
            activity: activity,
            suitability: suitability,
            warnings: warnings,
            recommendations: recommendations
        )
    }

    static func evaluateAllActivities(given weather: WeatherData) -> [ActivitySuitability] {
        let activities = ActivityStorage.loadActivities()
        return activities.map { evaluateSuitability(for: $0, given: weather) }
    }

    static func recommendedActivities(from suitabilities: [ActivitySuitability]) -> [ActivitySuitability] {
        suitabilities.filter { $0.suitability == .good || $0.suitability == .excellent }
            .sorted { $0.suitability.rawValue > $1.suitability.rawValue }
    }

    private static func suitabilityLevel(from score: Double) -> SuitabilityLevel {
        switch score {
        case 85...: return .excellent
        case 70..<85: return .good
        case 55..<70: return .fair
        case 40..<55: return .poor
        default: return .unsuitable
        }
    }

    private static func generateRecommendations(
        for activity: Activity,
        weather: WeatherData,
        suitability: SuitabilityLevel
    ) -> [String] {
        var recommendations: [String] = []

        if weather.uvIndex >= 8 {
            recommendations.append(String(localized: "recommendation.sunscreen", defaultValue: "Apply sunscreen"))
        }

        if weather.temperature < activity.minTemperature {
            recommendations.append(String(localized: "recommendation.warmClothing", defaultValue: "Wear warm clothing"))
        } else if weather.temperature > activity.maxTemperature {
            recommendations.append(String(localized: "recommendation.lightClothing", defaultValue: "Wear light clothing"))
        }

        if weather.windSpeed > activity.maxWindSpeed * 0.8 {
            recommendations.append(String(localized: "recommendation.windProtection", defaultValue: "Bring wind protection"))
        }

        if weather.rainProbability > 50 && activity.avoidRain {
            recommendations.append(String(localized: "recommendation.rainGear", defaultValue: "Bring rain gear"))
        }

        if weather.humidity > 80 {
            recommendations.append(String(localized: "recommendation.bringWater", defaultValue: "Bring plenty of water"))
        }

        if suitability == .excellent {
            recommendations.append(String(localized: "recommendation.perfectConditions", defaultValue: "Perfect conditions for this activity!"))
        }

        return recommendations
    }
}
