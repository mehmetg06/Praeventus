#if canImport(SwiftUI)
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WeatherStore
    private var weather: WeatherData { store.weather }
    private var atmosphere: AtmosphericState { store.atmosphere }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                    .padding(.top, 30)
                metricsStrip
                atmosphereStoryCard
                atmosphericDiagnostics
                hourlyPreview
                dailyPreview
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        VStack(spacing: 7) {
            Text(weather.city)
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(.white)

            Text("Weather Lab · \(weather.country)")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.70))

            Text(weather.formattedHour)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.70))
                .padding(.top, 2)

            Text("\(Int(weather.temperature.rounded()))°")
                .font(.system(size: 136, weight: .ultraLight, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.top, -2)

            Text(atmosphere.condition.rawValue)
                .font(.title3.weight(.regular))
                .foregroundStyle(.white.opacity(0.92))

            statusPill
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(atmosphere.stormRisk == .high ? .orange : .mint)
                .frame(width: 7, height: 7)
            Text(atmosphere.statusText)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(ThinGlassShape(cornerRadius: 18, intensity: 0.10))
    }

    private var metricsStrip: some View {
        HStack(spacing: 0) {
            GlassMetric(symbol: "thermometer.medium", title: "Hissedilen", value: "\(Int(weather.feelsLike.rounded()))°", unit: "")
            Divider().background(.white.opacity(0.20))
            GlassMetric(symbol: "drop", title: "Nem", value: "%\(Int(weather.humidity.rounded()))", unit: "")
            Divider().background(.white.opacity(0.20))
            GlassMetric(symbol: "gauge.with.dots.needle.bottom.50percent", title: "Basınç", value: "\(Int(weather.pressure.rounded()))", unit: "hPa")
            Divider().background(.white.opacity(0.20))
            GlassMetric(symbol: "wind", title: "Rüzgar", value: "\(Int(weather.windSpeed.rounded()))", unit: "km/sa")
        }
        .frame(height: 112)
        .padding(.horizontal, 12)
        .background(ThinGlassShape(cornerRadius: 26, intensity: 0.11))
    }

    private var atmosphereStoryCard: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Atmosfer Hikâyesi")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white)

                Text(atmosphere.story)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.90))
            }

            Spacer(minLength: 0)

            AtmosphereOrb(symbolName: atmosphere.symbolName)
                .frame(width: 96, height: 96)
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 26, intensity: 0.11))
    }

    private var atmosphericDiagnostics: some View {
        HStack(spacing: 0) {
            GlassMetric(symbol: "bolt.trianglebadge.exclamationmark", title: "Fırtına", value: atmosphere.stormRisk.rawValue, unit: "")
            Divider().background(.white.opacity(0.20))
            GlassMetric(symbol: "cloud.rain", title: "Yağış", value: atmosphere.rainSignal.rawValue, unit: "")
            Divider().background(.white.opacity(0.20))
            GlassMetric(symbol: "eye", title: "Görüş", value: atmosphere.visibility.rawValue, unit: "")
        }
        .frame(height: 98)
        .padding(.horizontal, 12)
        .background(ThinGlassShape(cornerRadius: 26, intensity: 0.11))
    }

    private var hourlyPreview: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Saatlik")
                    .font(.headline.weight(.medium))
                Spacer()
                Text("Yağış %\(Int(weather.rainProbability.rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.70))
            }
            .foregroundStyle(.white)

            HStack(spacing: 0) {
                ForEach(sampleHours, id: \.time) { hour in
                    VStack(spacing: 8) {
                        Text(hour.time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                        Image(systemName: hour.symbol)
                            .font(.title3.weight(.light))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(hour.temp)°")
                            .font(.title3.weight(.light))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 26, intensity: 0.10))
    }

    private var dailyPreview: some View {
        VStack(spacing: 10) {
            ForEach(sampleDays, id: \.day) { item in
                HStack(spacing: 12) {
                    Text(item.day)
                        .font(.body.weight(.medium))
                        .frame(width: 90, alignment: .leading)
                    Image(systemName: item.symbol)
                        .font(.body.weight(.light))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 24)
                    Spacer()
                    Text("\(item.low)°")
                        .foregroundStyle(.white.opacity(0.70))
                        .monospacedDigit()
                    Capsule()
                        .fill(.white.opacity(0.20))
                        .frame(width: 76, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.85))
                                .frame(width: CGFloat(max(1, item.high - item.low)) * 5 + 18, height: 4)
                        }
                    Text("\(item.high)°")
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                if item.day != sampleDays.last?.day {
                    Divider().background(.white.opacity(0.12))
                }
            }
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 26, intensity: 0.10))
    }

    private var sampleHours: [(time: String, symbol: String, temp: Int)] {
        let start = Int(weather.hour.rounded())
        let base = Int(weather.temperature.rounded())
        return [
            ("Şu An", atmosphere.symbolName, base),
            (String(format: "%02d:00", (start + 1) % 24), atmosphere.symbolName, base + 1),
            (String(format: "%02d:00", (start + 2) % 24), atmosphere.symbolName, base + 1),
            (String(format: "%02d:00", (start + 3) % 24), atmosphere.symbolName, base),
            (String(format: "%02d:00", (start + 4) % 24), atmosphere.symbolName, base - 1)
        ]
    }

    private var sampleDays: [(day: String, symbol: String, low: Int, high: Int)] {
        let base = Int(weather.temperature.rounded())
        return [
            ("Bugün", atmosphere.symbolName, base - 6, base + 2),
            ("Yarın", atmosphere.symbolName, base - 7, base + 1),
            ("Pazar", atmosphere.symbolName, base - 8, base),
            ("Pazartesi", atmosphere.symbolName, base - 7, base + 1)
        ]
    }
}

struct AtmosphereOrb: View {
    let symbolName: String

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial.opacity(0.15))
            .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: 36, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.95))
            }
    }
}
#endif
