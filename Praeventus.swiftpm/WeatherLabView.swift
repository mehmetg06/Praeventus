#if canImport(SwiftUI)
import SwiftUI

struct WeatherLabView: View {
    @Binding var weather: WeatherData

    var body: some View {
        Form {
            Section("Atmosfer Tipi") {
                Picker("Durum", selection: conditionBinding) {
                    ForEach(WeatherCondition.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
            }

            Section("Saat / Işık") {
                Slider(value: hourBinding, in: 0...23, step: 1)
                HStack {
                    Text("Saat: \(weather.formattedHour)")
                    Spacer()
                    Text(weather.timeOfDay.rawValue)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Canlı Simülasyon") {
                Slider(value: temperatureBinding, in: -10...48)
                Text("Sıcaklık: \(Int(weather.temperature))°C")

                Slider(value: humidityBinding, in: 0...100)
                Text("Nem: %\(Int(weather.humidity))")

                Slider(value: pressureBinding, in: 980...1040)
                Text("Basınç: \(Int(weather.pressure)) hPa")

                Slider(value: windBinding, in: 0...100)
                Text("Rüzgar: \(Int(weather.windSpeed)) km/sa")

                Slider(value: rainBinding, in: 0...100)
                Text("Yağış: %\(Int(weather.rainProbability))")
            }

            Section("Hızlı Senaryolar") {
                Button("Yaz Günü") { applyPreset(.clear, temp: 34, humidity: 42, pressure: 1018, wind: 10, rain: 4, hour: 14) }
                Button("Sabah Sisi") { applyPreset(.fog, temp: 14, humidity: 96, pressure: 1012, wind: 4, rain: 12, hour: 7) }
                Button("Gün Batımı Yağmuru") { applyPreset(.rain, temp: 22, humidity: 88, pressure: 1004, wind: 28, rain: 78, hour: 19) }
                Button("Gece Fırtınası") { applyPreset(.storm, temp: 27, humidity: 91, pressure: 996, wind: 46, rain: 92, hour: 23) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var conditionBinding: Binding<WeatherCondition> {
        Binding(get: { weather.condition }, set: { updateWeather(condition: $0) })
    }

    private var hourBinding: Binding<Double> {
        Binding(get: { weather.hour }, set: { updateWeather(hour: $0) })
    }

    private var temperatureBinding: Binding<Double> {
        Binding(get: { weather.temperature }, set: { updateWeather(temperature: $0) })
    }

    private var humidityBinding: Binding<Double> {
        Binding(get: { weather.humidity }, set: { updateWeather(humidity: $0) })
    }

    private var pressureBinding: Binding<Double> {
        Binding(get: { weather.pressure }, set: { updateWeather(pressure: $0) })
    }

    private var windBinding: Binding<Double> {
        Binding(get: { weather.windSpeed }, set: { updateWeather(windSpeed: $0) })
    }

    private var rainBinding: Binding<Double> {
        Binding(get: { weather.rainProbability }, set: { updateWeather(rainProbability: $0) })
    }

    private func updateWeather(
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

    private func applyPreset(_ condition: WeatherCondition, temp: Double, humidity: Double, pressure: Double, wind: Double, rain: Double, hour: Double) {
        var next = weather
        next.city = "Mock City"
        next.country = "Weather Lab"
        next.condition = condition
        next.hour = hour
        next.temperature = temp
        next.humidity = humidity
        next.pressure = pressure
        next.windSpeed = wind
        next.rainProbability = rain
        next.feelsLike = temp + max(0, humidity - 55) / 18
        weather = next
    }
}
#endif