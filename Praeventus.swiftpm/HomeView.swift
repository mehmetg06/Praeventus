#if canImport(SwiftUI)
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WeatherStore
    private var weather: WeatherData { store.weather }
    private var atmosphere: AtmosphericState { store.atmosphere }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header
                    .padding(.top, 34)

                metricsStrip
                    .padding(.top, 8)

                atmosphereStoryCard

                atmosphericDiagnostics

                hourlyPreview

                dailyPreview
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(weather.city)
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(.white)

            Text(weather.country)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))

            Text(weather.formattedHour)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 4)

            Text("\(Int(weather.temperature.rounded()))°")
                .font(.system(size: 142, weight: .ultraLight, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.18), radius: 18)
                .padding(.top, -2)
                .contentTransition(.numericText())

            Text(atmosphere.condition.rawValue)
                .font(.title3.weight(.light))
                .foregroundStyle(.white.opacity(0.92))

            HStack(spacing: 8) {
                Circle()
                    .fill(atmosphere.stormRisk == .high ? .orange : .green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.5), radius: 6)
                Text(atmosphere.statusText)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(ThinGlassShape(cornerRadius: 20, intensity: 0.18))
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.22), value: weather)
        .animation(.easeInOut(duration: 0.22), value: atmosphere)
    }

    private var metricsStrip: some View {
        HStack(spacing: 0) {
            GlassMetric(symbol: "thermometer.medium", title: "Hissedilen", value: "\(Int(weather.feelsLike))°", unit: "")
            Divider().background(.white.opacity(0.28))
            GlassMetric(symbol: "drop", title: "Nem", value: "%\(Int(weather.humidity))", unit: "")
            Divider().background(.white.opacity(0.28))
            GlassMetric(symbol: "gauge.with.dots.needle.bottom.50percent", title: "Basınç", value: "\(Int(weather.pressure))", unit: "hPa")
            Divider().background(.white.opacity(0.28))
            GlassMetric(symbol: "wind", title: "Rüzgar", value: "\(Int(weather.windSpeed))", unit: "km/sa")
        }
        .frame(height: 118)
        .padding(.horizontal, 14)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.14))
    }

    private var atmosphereStoryCard: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(symbol: "sparkles", title: "Atmosfer Hikâyesi")

                Text(atmosphere.story)
                    .font(.body.weight(.regular))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.90))
            }

            Spacer(minLength: 4)

            AtmosphereOrb(condition: atmosphere.condition)
                .frame(width: 112, height: 112)
        }
        .padding(22)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.16))
    }

    private var atmosphericDiagnostics: some View {
        HStack(spacing: 0) {
            GlassMetric(symbol: "bolt.trianglebadge.exclamationmark", title: "Fırtına", value: atmosphere.stormRisk.rawValue, unit: "")
            Divider().background(.white.opacity(0.28))
            GlassMetric(symbol: "cloud.rain", title: "Yağış", value: atmosphere.rainSignal.rawValue, unit: "")
            Divider().background(.white.opacity(0.28))
            GlassMetric(symbol: "eye", title: "Görüş", value: atmosphere.visibility.rawValue, unit: "")
        }
        .frame(height: 104)
        .padding(.horizontal, 14)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.13))
    }

    private var hourlyPreview: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Saatlik")
                    .font(.headline.weight(.medium))
                Spacer()
                Text("Yağış %\(Int(weather.rainProbability))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)

            HStack(spacing: 0) {
                ForEach(sampleHours, id: \.time) { hour in
                    VStack(spacing: 9) {
                        Text(hour.time)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.74))
                        Image(systemName: hour.symbol)
                            .font(.title3)
                            .symbolRenderingMode(.multicolor)
                        Text("\(hour.temp)°")
                            .font(.title3.weight(.light))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.14))
    }

    private var dailyPreview: some View {
        VStack(spacing: 12) {
            ForEach(sampleDays, id: \.day) { item in
                HStack {
                    Image(systemName: item.symbol)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 28)
                    Text(item.day)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("\(item.low)°")
                        .foregroundStyle(.white.opacity(0.70))
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(width: 82, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.82))
                                .frame(width: CGFloat(max(1, item.high - item.low)) * 6 + 22, height: 5)
                        }
                    Text("\(item.high)°")
                }
                .foregroundStyle(.white)
                if item.day != sampleDays.last?.day {
                    Divider().background(.white.opacity(0.18))
                }
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.14))
    }

    private var sampleHours: [(time: String, symbol: String, temp: Int)] {
        let start = Int(weather.hour.rounded())
        return [
            ("Şu An", atmosphere.symbolName, Int(weather.temperature)),
            (String(format: "%02d:00", (start + 1) % 24), atmosphere.symbolName, Int(weather.temperature + 1)),
            (String(format: "%02d:00", (start + 2) % 24), atmosphere.symbolName, Int(weather.temperature + 2)),
            (String(format: "%02d:00", (start + 3) % 24), atmosphere.symbolName, Int(weather.temperature + 2)),
            (String(format: "%02d:00", (start + 4) % 24), atmosphere.condition == .storm ? "cloud.bolt.rain.fill" : atmosphere.symbolName, Int(weather.temperature + 1))
        ]
    }

    private var sampleDays: [(day: String, symbol: String, low: Int, high: Int)] {
        [
            ("Bugün", atmosphere.symbolName, Int(weather.temperature - 7), Int(weather.temperature + 3)),
            ("Yarın", atmosphere.symbolName, Int(weather.temperature - 8), Int(weather.temperature + 2)),
            ("Pazar", atmosphere.rainSignal == .high ? "cloud.rain.fill" : atmosphere.symbolName, Int(weather.temperature - 9), Int(weather.temperature - 1)),
            ("Pazartesi", atmosphere.condition == .clear ? "cloud.sun.fill" : atmosphere.symbolName, Int(weather.temperature - 8), Int(weather.temperature))
        ]
    }
}

struct AtmosphereOrb: View {
    let condition: WeatherCondition

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial.opacity(0.30))
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: .white.opacity(0.14), radius: 18)

            Image(systemName: condition.symbolName)
                .font(.system(size: 42, weight: .light))
                .symbolRenderingMode(.multicolor)
        }
    }
}
#endif