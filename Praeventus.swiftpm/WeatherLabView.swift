#if canImport(SwiftUI)
import SwiftUI

struct WeatherLabView: View {
    @Binding var weather: WeatherData

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                labHeader
                    .padding(.top, 34)

                conditionPicker

                sliderCard(title: "Sıcaklık", symbol: "thermometer.sun", value: $weather.temperature, range: -10...48, suffix: "°C")
                sliderCard(title: "Nem", symbol: "drop", value: $weather.humidity, range: 5...100, suffix: "%")
                sliderCard(title: "Basınç", symbol: "gauge.with.dots.needle.bottom.50percent", value: $weather.pressure, range: 980...1040, suffix: " hPa")
                sliderCard(title: "Rüzgar", symbol: "wind", value: $weather.windSpeed, range: 0...95, suffix: " km/sa")
                sliderCard(title: "Yağış", symbol: "cloud.rain", value: $weather.rainProbability, range: 0...100, suffix: "%")

                presetGrid
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private var labHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "flask.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white)
                .padding(16)
                .background(ThinGlassShape(cornerRadius: 28, intensity: 0.18))

            Text("Weather Lab")
                .font(.system(size: 38, weight: .light, design: .rounded))
                .foregroundStyle(.white)

            Text("Mock City atmosferini değiştir. Ana ekran ve arka plan anında tepki verir.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 16)
        }
    }

    private var conditionPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbol: "wand.and.stars", title: "Atmosfer Tipi")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(WeatherCondition.allCases) { condition in
                        Button {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                weather.condition = condition
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: condition.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                Text(condition.rawValue)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(
                                ThinGlassShape(
                                    cornerRadius: 20,
                                    intensity: weather.condition == condition ? 0.28 : 0.12
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.14))
    }

    private func sliderCard(title: String, symbol: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3)
                Text(title)
                    .font(.headline.weight(.medium))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))\(suffix)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)

            Slider(value: value, in: range)
                .tint(.white.opacity(0.86))
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.13))
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbol: "square.grid.2x2", title: "Hazır Senaryolar")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                presetButton("Yaz Günü", .clear, 34, 42, 1018, 10, 4)
                presetButton("Cephe Geçişi", .rain, 22, 88, 1004, 28, 78)
                presetButton("Fırtına", .storm, 27, 91, 996, 46, 92)
                presetButton("Sis", .fog, 14, 96, 1012, 4, 12)
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.14))
    }

    private func presetButton(_ title: String, _ condition: WeatherCondition, _ temp: Double, _ humidity: Double, _ pressure: Double, _ wind: Double, _ rain: Double) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                weather.city = "Mock City"
                weather.country = "Weather Lab"
                weather.condition = condition
                weather.temperature = temp
                weather.feelsLike = temp + max(0, humidity - 55) / 18
                weather.humidity = humidity
                weather.pressure = pressure
                weather.windSpeed = wind
                weather.rainProbability = rain
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: condition.symbolName)
                    .font(.title2)
                    .symbolRenderingMode(.multicolor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(Int(temp))° · %\(Int(rain))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(ThinGlassShape(cornerRadius: 24, intensity: 0.13))
        }
        .buttonStyle(.plain)
    }
}
#endif
