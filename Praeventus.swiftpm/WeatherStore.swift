#if canImport(SwiftUI)
import SwiftUI

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var weather: WeatherData

    init(weather: WeatherData = .mersin) {
        self.weather = weather
    }

    func update(
        condition: WeatherCondition? = nil,
        hour: Double? = nil,
        temperature: Double? = nil,
        humidity: Double? = nil,
        pressure: Double? = nil,
        windSpeed: Double? = nil,
        rainProbability: Double? = nil
    ) {
        var next = weather
        next.city = "Mock City"
        next.country = "Weather Lab"
        if let condition { next.condition = condition }
        if let hour { next.hour = hour }
        if let temperature { next.temperature = temperature }
        if let humidity { next.humidity = humidity }
        if let pressure { next.pressure = pressure }
        if let windSpeed { next.windSpeed = windSpeed }
        if let rainProbability { next.rainProbability = rainProbability }
        next.feelsLike = next.temperature + max(0, next.humidity - 55) / 18
        weather = next
    }

    func applyPreset(
        _ condition: WeatherCondition,
        temp: Double,
        humidity: Double,
        pressure: Double,
        wind: Double,
        rain: Double,
        hour: Double
    ) {
        weather = WeatherData(
            city: "Mock City",
            country: "Weather Lab",
            temperature: temp,
            feelsLike: temp + max(0, humidity - 55) / 18,
            condition: condition,
            humidity: humidity,
            pressure: pressure,
            windSpeed: wind,
            rainProbability: rain,
            hour: hour
        )
    }
}
#endif
