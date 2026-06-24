#if canImport(SwiftUI)
import SwiftUI

struct WeatherLabView: View {
    @Binding var weather: WeatherData

    var body: some View {
        Form {
            Section("Atmosfer Tipi") {
                Picker("Durum", selection: $weather.condition) {
                    ForEach(WeatherCondition.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
            }

            Section("Canlı Simülasyon") {
                Slider(value: $weather.temperature, in: -10...48)
                Text("Sıcaklık: \(Int(weather.temperature))°C")

                Slider(value: $weather.humidity, in: 0...100)
                Text("Nem: %\(Int(weather.humidity))")

                Slider(value: $weather.pressure, in: 980...1040)
                Text("Basınç: \(Int(weather.pressure)) hPa")

                Slider(value: $weather.windSpeed, in: 0...100)
                Text("Rüzgar: \(Int(weather.windSpeed)) km/sa")

                Slider(value: $weather.rainProbability, in: 0...100)
                Text("Yağış: %\(Int(weather.rainProbability))")
            }
        }
        .scrollContentBackground(.hidden)
        .onChange(of: weather.temperature) { _, value in
            weather.feelsLike = value + max(0, weather.humidity - 55) / 18
            weather.city = "Mock City"
            weather.country = "Weather Lab"
        }
        .onChange(of: weather.humidity) { _, value in
            weather.feelsLike = weather.temperature + max(0, value - 55) / 18
        }
    }
}
#endif