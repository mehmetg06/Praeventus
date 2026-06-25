#if canImport(SwiftUI)
import SwiftUI

struct WeatherLabView: View {
    @ObservedObject var store: WeatherStore
    private var weather: WeatherData { store.weather }

    var body: some View {
        Form {
            Section("lab.section.type") {
                Picker("lab.condition", selection: conditionBinding) {
                    ForEach(WeatherCondition.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
            }

            Section("lab.section.light") {
                Slider(value: hourBinding, in: 0...23, step: 1)
                HStack {
                    Text(String(localized: "lab.hour", defaultValue: "Hour: \(weather.formattedHour)"))
                    Spacer()
                    Text(weather.timeOfDay.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            Section("lab.section.simulation") {
                Slider(value: temperatureBinding, in: -10...48)
                Text(String(localized: "lab.temperature", defaultValue: "Temperature: \(Int(weather.temperature))°C"))

                Slider(value: humidityBinding, in: 0...100)
                Text(String(localized: "lab.humidity", defaultValue: "Humidity:") + " %\(Int(weather.humidity))")

                Slider(value: pressureBinding, in: 980...1040)
                Text(String(localized: "lab.pressure", defaultValue: "Pressure: \(Int(weather.pressure)) hPa"))

                Slider(value: windBinding, in: 0...100)
                Text(String(localized: "lab.wind", defaultValue: "Wind: \(Int(weather.windSpeed)) km/h"))

                Slider(value: rainBinding, in: 0...100)
                Text(String(localized: "lab.rain", defaultValue: "Rain:") + " %\(Int(weather.rainProbability))")
            }

            Section("lab.section.scenarios") {
                Button("lab.preset.summer") { store.applyPreset(.clear, temp: 34, humidity: 42, pressure: 1018, wind: 10, rain: 4, hour: 14) }
                Button("lab.preset.fog") { store.applyPreset(.fog, temp: 14, humidity: 96, pressure: 1012, wind: 4, rain: 12, hour: 7) }
                Button("lab.preset.sunsetRain") { store.applyPreset(.rain, temp: 22, humidity: 88, pressure: 1004, wind: 28, rain: 78, hour: 19) }
                Button("lab.preset.nightStorm") { store.applyPreset(.storm, temp: 27, humidity: 91, pressure: 996, wind: 46, rain: 92, hour: 23) }
            }

            Section(String(localized: "lab.section.computed", defaultValue: "Computed State")) {
                LabeledContent(
                    String(localized: "lab.computed.condition", defaultValue: "Condition"),
                    value: store.atmosphere.condition.displayName
                )
                LabeledContent(
                    String(localized: "lab.computed.mood", defaultValue: "Background"),
                    value: moodDisplayName(store.atmosphere.backgroundMood)
                )
                LabeledContent(
                    String(localized: "lab.computed.cloudCover", defaultValue: "Cloud Cover"),
                    value: "\(Int(store.atmosphere.cloudCover * 100))%"
                )
                LabeledContent(
                    String(localized: "lab.computed.instability", defaultValue: "Instability"),
                    value: "\(Int(store.atmosphere.instability * 100))%"
                )
                LabeledContent(
                    String(localized: "lab.computed.stormRisk", defaultValue: "Storm Risk"),
                    value: store.atmosphere.stormRisk.displayName
                )
                LabeledContent(
                    String(localized: "lab.computed.visibility", defaultValue: "Visibility"),
                    value: store.atmosphere.visibility.displayName
                )
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

    private func moodDisplayName(_ mood: BackgroundMood) -> String {
        switch mood {
        case .clear:        return String(localized: "mood.clear", defaultValue: "Clear")
        case .partlyCloudy: return String(localized: "mood.partlyCloudy", defaultValue: "Partly Cloudy")
        case .cloudy:       return String(localized: "mood.cloudy", defaultValue: "Cloudy")
        case .wet:          return String(localized: "mood.wet", defaultValue: "Wet / Rain")
        case .storm:        return String(localized: "mood.storm", defaultValue: "Storm")
        case .fog:          return String(localized: "mood.fog", defaultValue: "Fog")
        case .snow:         return String(localized: "mood.snow", defaultValue: "Snow")
        }
    }
}
#endif