#if canImport(SwiftUI)
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WeatherStore
    private var weather: WeatherData { store.weather }
    private var atmosphere: AtmosphericState { store.atmosphere }
    private var paletteTint: Color { atmosphere.condition.palette[1] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                temperatureHero
                metricsGrid
                storyCard
                hourlyPreview
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AtmosphereOrb(symbolName: atmosphere.symbolName)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(weather.city)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(weather.country) · \(weather.formattedHour) · \(weather.timeOfDay.rawValue)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Spacer(minLength: 0)
        }
    }

    private var temperatureHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(weather.temperature.rounded()))°")
                    .font(.system(size: 98, weight: .ultraLight, design: .rounded))
                    .minimumScaleFactor(0.70)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text(atmosphere.condition.rawValue)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.white.opacity(0.92))

                Text("·")
                    .foregroundStyle(.white.opacity(0.34))

                Text(atmosphere.statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.66))
            }

            Text("Hissedilen \(Int(weather.feelsLike.rounded()))°")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.top, 12)
    }

    private var storyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .light))
                Text("ATMOSFER HİKÂYESİ")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.56))

            Text(atmosphere.story)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.13, highlightOpacity: 0.18, innerShadowOpacity: 0.22, borderOpacity: 0.22, tintColor: paletteTint))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            GlassMetric(symbol: "gauge.with.dots.needle.bottom.50percent", title: "Basınç", value: "\(Int(weather.pressure.rounded()))", unit: "hPa", accent: .cyan, tintColor: paletteTint)
            GlassMetric(symbol: "humidity", title: "Nem", value: "%\(Int(weather.humidity.rounded()))", unit: humidityLabel, accent: .blue, tintColor: paletteTint)
            GlassMetric(symbol: "wind", title: "Rüzgar", value: "\(Int(weather.windSpeed.rounded()))", unit: "km/sa", accent: .mint, tintColor: paletteTint)
            GlassMetric(symbol: riskSymbol, title: riskTitle, value: riskValue, unit: riskUnit, accent: riskAccent, tintColor: paletteTint)
        }
    }

    private var hourlyPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CANLI ÖNGÖRÜ")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.54))
                Spacer()
                Text("Yağış %\(Int(weather.rainProbability.rounded()))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.60))
            }

            HStack(spacing: 0) {
                ForEach(HourlyAtmospherePoint.samples(from: weather, atmosphere: atmosphere)) { point in
                    VStack(spacing: 7) {
                        Text(point.time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.56))
                        Image(systemName: point.symbol)
                            .font(.caption.weight(.light))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(point.temperature)°")
                            .font(.caption.monospacedDigit())
                        Text("%\(point.rainProbability)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.50))
                    }
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(ThinGlassShape(cornerRadius: 26, intensity: 0.10, highlightOpacity: 0.14, innerShadowOpacity: 0.18, borderOpacity: 0.18, tintColor: paletteTint))
    }

    private var humidityLabel: String {
        switch weather.humidity {
        case ..<35: return "kuru"
        case ..<65: return "dengeli"
        case ..<85: return "nemli"
        default: return "doygun"
        }
    }

    private var riskSymbol: String { atmosphere.stormRisk == .high ? "bolt.trianglebadge.exclamationmark" : "eye" }
    private var riskTitle: String { atmosphere.stormRisk == .high ? "Fırtına" : "Görüş" }
    private var riskValue: String { atmosphere.stormRisk == .high ? atmosphere.stormRisk.rawValue : atmosphere.visibility.rawValue }
    private var riskUnit: String { atmosphere.stormRisk == .high ? "risk" : "" }
    private var riskAccent: Color { atmosphere.stormRisk == .high ? .orange : .cyan }
}

private struct HourlyAtmospherePoint: Identifiable {
    let id = UUID()
    let time: String
    let temperature: Int
    let rainProbability: Int
    let symbol: String

    static func samples(from weather: WeatherData, atmosphere: AtmosphericState) -> [HourlyAtmospherePoint] {
        let start = Int(weather.hour.rounded())
        let base = Int(weather.temperature.rounded())
        let rain = Int(weather.rainProbability.rounded())
        return (0..<6).map { index in
            let wave = Int((sin(Double(index) * 0.85) * 2.2).rounded())
            let cooling = index > 3 ? index - 3 : 0
            return HourlyAtmospherePoint(
                time: index == 0 ? "Şimdi" : String(format: "%02d", (start + index) % 24),
                temperature: base + wave - cooling,
                rainProbability: min(100, max(0, rain + index * (atmosphere.rainSignal == .high ? 5 : 2) - 5)),
                symbol: atmosphere.symbolName
            )
        }
    }
}

struct AtmosphereOrb: View {
    let symbolName: String

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial.opacity(0.18))
            .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
            .overlay {
                RadialGradient(colors: [.white.opacity(0.38), .cyan.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: 54)
                    .clipShape(Circle())
            }
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: 25, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.95))
            }
            .shadow(color: .blue.opacity(0.24), radius: 16)
    }
}
#endif