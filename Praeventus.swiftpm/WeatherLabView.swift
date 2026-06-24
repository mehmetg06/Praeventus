#if canImport(SwiftUI)
import SwiftUI

struct WeatherLabView: View {
    @ObservedObject var store: WeatherStore
    private var weather: WeatherData { store.weather }

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
                Button("Yaz Günü") { store.applyPreset(.clear, temp: 34, humidity: 42, pressure: 1018, wind: 10, rain: 4, hour: 14) }
                Button("Sabah Sisi") { store.applyPreset(.fog, temp: 14, humidity: 96, pressure: 1012, wind: 4, rain: 12, hour: 7) }
                Button("Gün Batımı Yağmuru") { store.applyPreset(.rain, temp: 22, humidity: 88, pressure: 1004, wind: 28, rain: 78, hour: 19) }
                Button("Gece Fırtınası") { store.applyPreset(.storm, temp: 27, humidity: 91, pressure: 996, wind: 46, rain: 92, hour: 23) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var conditionBinding: Binding<WeatherCondition> {
        Binding(get: { weather.condition }, set: { store.update(condition: $0) })
    }

    private var hourBinding: Binding<Double> {
        Binding(get: { weather.hour }, set: { store.update(hour: $0) })
    }

    private var temperatureBinding: Binding<Double> {
        Binding(get: { weather.temperature }, set: { store.update(temperature: $0) })
    }

    private var humidityBinding: Binding<Double> {
        Binding(get: { weather.humidity }, set: { store.update(humidity: $0) })
    }

    private var pressureBinding: Binding<Double> {
        Binding(get: { weather.pressure }, set: { store.update(pressure: $0) })
    }

    private var windBinding: Binding<Double> {
        Binding(get: { weather.windSpeed }, set: { store.update(windSpeed: $0) })
    }

    private var rainBinding: Binding<Double> {
        Binding(get: { weather.rainProbability }, set: { store.update(rainProbability: $0) })
    }
}
#endif