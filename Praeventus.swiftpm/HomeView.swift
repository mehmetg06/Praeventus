#if canImport(SwiftUI)
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WeatherStore
    private var weather: WeatherData { store.weather }
    private var atmosphere: AtmosphericState { store.atmosphere }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                brandHeader
                    .padding(.top, 28)
                PremiumWeatherCard(weather: weather, atmosphere: atmosphere)
                atmosphereInsightStrip
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.05))
                .frame(width: 72, height: 72)
                .background(ThinGlassShape(cornerRadius: 22, intensity: 0.15, highlightOpacity: 0.26, innerShadowOpacity: 0.24, borderOpacity: 0.34))
                .overlay {
                    AtmosphereOrb(symbolName: atmosphere.symbolName)
                        .padding(10)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Praeventus")
                    .font(.system(size: 34, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(.white)
                Text("Atmospheric intelligence")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.70))
                Text("Havayı yalnızca göstermez; atmosferin ritmini, riskini ve hissini sezdirir.")
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 0)
        }
    }

    private var atmosphereInsightStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atmosfer · canlı katmanlar")
                .font(.headline.weight(.medium))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                InsightPill(symbol: "aqi.medium", title: "Gerçekçi", detail: "Derinlik + ışık")
                InsightPill(symbol: "humidity", title: "Sezgisel", detail: "Risk hikâyesi")
                InsightPill(symbol: "sparkles", title: "Premium", detail: "Liquid glass")
            }
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.11, highlightOpacity: 0.15, innerShadowOpacity: 0.22, borderOpacity: 0.20))
    }
}

private struct PremiumWeatherCard: View {
    let weather: WeatherData
    let atmosphere: AtmosphericState

    private var hours: [HourlyAtmospherePoint] {
        HourlyAtmospherePoint.samples(from: weather, atmosphere: atmosphere)
    }

    var body: some View {
        VStack(spacing: 18) {
            cardTopBar
            temperatureHero
            storyPanel
            metricsGrid
            MiniAtmosphereGraph(points: hours)
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 34, intensity: 0.16, highlightOpacity: 0.26, innerShadowOpacity: 0.30, borderOpacity: 0.32))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 120, height: 120)
                .blur(radius: 44)
                .offset(x: 32, y: -46)
        }
    }

    private var cardTopBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Praeventus")
                    .font(.system(size: 21, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                Label("\(weather.city.uppercased()) · \(weather.country.uppercased())", systemImage: "location")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Image(systemName: atmosphere.symbolName)
                    .font(.system(size: 20, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.08)))
                Text("\(weather.formattedHour) · \(weather.timeOfDay.rawValue)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var temperatureHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(weather.temperature.rounded()))°")
                    .font(.system(size: 86, weight: .ultraLight, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Spacer()
            }
            Text(atmosphere.condition.rawValue)
                .font(.title3.weight(.regular))
                .foregroundStyle(.white.opacity(0.90))
            Text(atmosphere.statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var storyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ATMOSFER HİKÂYESİ")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.50))
            Text(atmosphere.story)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 22, intensity: 0.12, highlightOpacity: 0.14, innerShadowOpacity: 0.18, borderOpacity: 0.18))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            GlassMetric(symbol: "gauge.with.dots.needle.bottom.50percent", title: "Basınç", value: "\(Int(weather.pressure.rounded()))", unit: "hPa")
            GlassMetric(symbol: "humidity", title: "Nem", value: "%\(Int(weather.humidity.rounded()))", unit: humidityLabel)
            GlassMetric(symbol: "wind", title: "Rüzgar", value: "\(Int(weather.windSpeed.rounded()))", unit: "km/sa")
            GlassMetric(symbol: metricRiskSymbol, title: metricRiskTitle, value: metricRiskValue, unit: metricRiskUnit, accent: metricAccent)
        }
    }

    private var humidityLabel: String { weather.humidity > 85 ? "doygun" : "" }
    private var metricRiskSymbol: String { atmosphere.stormRisk == .high ? "bolt.trianglebadge.exclamationmark" : "eye" }
    private var metricRiskTitle: String { atmosphere.stormRisk == .high ? "Fırtına" : "Görüş" }
    private var metricRiskValue: String { atmosphere.stormRisk == .high ? atmosphere.stormRisk.rawValue : atmosphere.visibility.rawValue }
    private var metricRiskUnit: String { atmosphere.stormRisk == .high ? "risk" : "" }
    private var metricAccent: Color { atmosphere.stormRisk == .high ? .orange : .cyan }
}

private struct HourlyAtmospherePoint: Identifiable {
    let id = UUID()
    let time: String
    let temperature: Int
    let rainProbability: Int
    let windSpeed: Int
    let symbol: String

    static func samples(from weather: WeatherData, atmosphere: AtmosphericState) -> [HourlyAtmospherePoint] {
        let start = Int(weather.hour.rounded())
        let base = Int(weather.temperature.rounded())
        let rain = Int(weather.rainProbability.rounded())
        return (0..<7).map { index in
            let wave = Int((sin(Double(index) * 0.85) * 2.4).rounded())
            let cooling = index > 3 ? index - 3 : 0
            return HourlyAtmospherePoint(
                time: index == 0 ? "Şimdi" : String(format: "%02d", (start + index) % 24),
                temperature: base + wave - cooling,
                rainProbability: min(100, max(0, rain + index * (atmosphere.rainSignal == .high ? 4 : 1) - 6)),
                windSpeed: max(0, Int(weather.windSpeed.rounded()) + index - 2),
                symbol: atmosphere.symbolName
            )
        }
    }
}

private struct MiniAtmosphereGraph: View {
    let points: [HourlyAtmospherePoint]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("CANLI ÖNGÖRÜ")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.54))
                Spacer()
                Text("Yağış %\(points.first?.rainProbability ?? 0)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.60))
            }

            GeometryReader { geometry in
                let values = points.map(\.temperature)
                let minValue = values.min() ?? 0
                let maxValue = values.max() ?? 1
                let range = max(1, maxValue - minValue)

                ZStack(alignment: .bottomLeading) {
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                            let normalized = CGFloat(point.temperature - minValue) / CGFloat(range)
                            let y = geometry.size.height * (0.70 - normalized * 0.42)
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(.white.opacity(0.78), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(points) { point in
                            Capsule(style: .continuous)
                                .fill(.blue.opacity(0.32 + Double(point.rainProbability) / 180))
                                .frame(maxWidth: .infinity)
                                .frame(height: CGFloat(8 + point.rainProbability / 3))
                        }
                    }
                    .frame(height: geometry.size.height * 0.58, alignment: .bottom)
                }
            }
            .frame(height: 72)

            HStack(spacing: 0) {
                ForEach(points) { point in
                    VStack(spacing: 5) {
                        Text(point.time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.56))
                        Image(systemName: point.symbol)
                            .font(.caption.weight(.light))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(point.temperature)°")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(15)
        .background(ThinGlassShape(cornerRadius: 22, intensity: 0.10, highlightOpacity: 0.12, innerShadowOpacity: 0.18, borderOpacity: 0.16))
    }
}

private struct InsightPill: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 18, intensity: 0.09, highlightOpacity: 0.10, innerShadowOpacity: 0.14, borderOpacity: 0.14))
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
                    .font(.system(size: 28, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.95))
            }
            .shadow(color: .blue.opacity(0.30), radius: 18)
    }
}
#endif
