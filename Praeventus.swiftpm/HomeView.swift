#if canImport(SwiftUI)
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WeatherStore
    @State private var showingSearch = false

    private var weather: WeatherData { store.weather }
    private var atmosphere: AtmosphericState { store.atmosphere }
    private var paletteTint: Color { atmosphere.condition.palette[1] }

    private var severity: WeatherSeverity {
        StorySentiment.severity(
            story: atmosphere.story,
            instability: atmosphere.instability,
            stormRiskIsHigh: atmosphere.stormRisk == .high
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                switch store.phase {
                case .idle:
                    idlePrompt
                case .loading:
                    loadingCard
                case .failed(let message):
                    errorCard(message)
                case .loaded:
                    loadedContent
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showingSearch) {
            LocationSearchView(store: store)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AtmosphereOrb(symbolName: atmosphere.symbolName)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Spacer(minLength: 0)

            Button(action: { showingSearch = true }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(ThinGlassShape(cornerRadius: 18, intensity: 0.14))
            }
            .accessibilityLabel(Text("search.title"))
        }
    }

    private var headerTitle: String {
        if store.phase == .idle || weather.city.isEmpty {
            return String(localized: "app.name", defaultValue: "Praeventus")
        }
        return weather.city
    }

    private var headerSubtitle: String {
        if store.phase == .idle {
            return String(localized: "home.tagline", defaultValue: "Privacy-first weather, anywhere")
        }
        let country = weather.country.isEmpty ? "" : "\(weather.country) · "
        return "\(country)\(weather.formattedHour) · \(weather.timeOfDay.displayName)"
    }

    // MARK: - Phase states

    private var idlePrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.9))

            Text("home.empty.title")
                .font(.system(size: 22, weight: .light, design: .rounded))
                .foregroundStyle(.white)

            Text("home.empty.subtitle")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { showingSearch = true }) {
                Label("home.empty.cta", systemImage: "location.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(ThinGlassShape(cornerRadius: 20, intensity: 0.18, tintColor: paletteTint))
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.12, tintColor: paletteTint))
        .padding(.top, 24)
    }

    private var loadingCard: some View {
        HStack(spacing: 14) {
            ProgressView().tint(.white)
            Text("home.loading")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.12, tintColor: paletteTint))
        .padding(.top, 24)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("home.error.title", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action: { Task { await store.retry() } }) {
                    Label("common.retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(ThinGlassShape(cornerRadius: 16, intensity: 0.16, tintColor: paletteTint))
                }
                Button(action: { showingSearch = true }) {
                    Label("home.empty.cta", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(ThinGlassShape(cornerRadius: 16, intensity: 0.16))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.12, tintColor: .red))
        .padding(.top, 24)
    }

    @ViewBuilder
    private var loadedContent: some View {
        temperatureHero
        metricsGrid
        storyCard
        hourlyPreview
        #if canImport(Charts)
        WeatherChartsView(hourly: store.hourly, daily: store.daily, tint: paletteTint)
        #endif
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
                Text(atmosphere.condition.displayName)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.white.opacity(0.92))
                Text("·")
                    .foregroundStyle(.white.opacity(0.34))
                Text(atmosphere.statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.66))
            }

            Text(String(localized: "home.feelsLike", defaultValue: "Feels like \(Int(weather.feelsLike.rounded()))°"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.top, 12)
    }

    private var storyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: severity.isNegative ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 15, weight: .light))
                Text("home.story.heading")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(severity.isNegative ? .white : .white.opacity(0.56))

            Text(atmosphere.story)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.13, highlightOpacity: 0.18, innerShadowOpacity: 0.22, borderOpacity: 0.22, tintColor: storyTint))
    }

    private var storyTint: Color {
        switch severity {
        case .alert: return .red
        case .caution: return .orange
        case .calm: return paletteTint
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            GlassMetric(symbol: "gauge.with.dots.needle.bottom.50percent", title: String(localized: "metric.pressure", defaultValue: "Pressure"), value: "\(Int(weather.pressure.rounded()))", unit: "hPa", accent: .cyan, tintColor: paletteTint)
            GlassMetric(symbol: "humidity", title: String(localized: "metric.humidity", defaultValue: "Humidity"), value: "%\(Int(weather.humidity.rounded()))", unit: humidityLabel, accent: .blue, tintColor: paletteTint)
            GlassMetric(symbol: "wind", title: String(localized: "metric.wind", defaultValue: "Wind"), value: "\(Int(weather.windSpeed.rounded()))", unit: String(localized: "unit.kmh", defaultValue: "km/h"), accent: .mint, tintColor: paletteTint)
            GlassMetric(symbol: riskSymbol, title: riskTitle, value: riskValue, unit: riskUnit, accent: riskAccent, tintColor: paletteTint)
        }
    }

    private var hourlyPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("home.hourly.heading")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.54))
                Spacer()
                Text(String(localized: "home.rainShort", defaultValue: "Rain") + " %\(Int(weather.rainProbability.rounded()))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.60))
            }

            HStack(spacing: 0) {
                ForEach(hourlyStrip) { point in
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

    /// Prefer real hourly data; fall back to the synthetic preview (Lab mode).
    private var hourlyStrip: [HourlyStripPoint] {
        if !store.hourly.isEmpty {
            let nowLabel = String(localized: "home.now", defaultValue: "Now")
            return store.hourly.prefix(6).enumerated().map { index, p in
                HourlyStripPoint(
                    time: index == 0 ? nowLabel : String(format: "%02d", p.hour),
                    temperature: Int(p.temperature.rounded()),
                    rainProbability: Int(p.precipitationProbability.rounded()),
                    symbol: p.condition.symbolName
                )
            }
        }
        return HourlyStripPoint.synthetic(from: weather, atmosphere: atmosphere)
    }

    private var humidityLabel: String {
        switch weather.humidity {
        case ..<35: return String(localized: "humidity.dry", defaultValue: "dry")
        case ..<65: return String(localized: "humidity.balanced", defaultValue: "balanced")
        case ..<85: return String(localized: "humidity.humid", defaultValue: "humid")
        default: return String(localized: "humidity.saturated", defaultValue: "saturated")
        }
    }

    private var riskSymbol: String { atmosphere.stormRisk == .high ? "bolt.trianglebadge.exclamationmark" : "eye" }
    private var riskTitle: String { atmosphere.stormRisk == .high ? String(localized: "metric.storm", defaultValue: "Storm") : String(localized: "metric.visibility", defaultValue: "Visibility") }
    private var riskValue: String { atmosphere.stormRisk == .high ? atmosphere.stormRisk.displayName : atmosphere.visibility.displayName }
    private var riskUnit: String { atmosphere.stormRisk == .high ? String(localized: "metric.risk", defaultValue: "risk") : "" }
    private var riskAccent: Color { atmosphere.stormRisk == .high ? .orange : .cyan }
}

private struct HourlyStripPoint: Identifiable {
    let id = UUID()
    let time: String
    let temperature: Int
    let rainProbability: Int
    let symbol: String

    static func synthetic(from weather: WeatherData, atmosphere: AtmosphericState) -> [HourlyStripPoint] {
        let start = Int(weather.hour.rounded())
        let base = Int(weather.temperature.rounded())
        let rain = Int(weather.rainProbability.rounded())
        let nowLabel = String(localized: "home.now", defaultValue: "Now")
        return (0..<6).map { index in
            let wave = Int((sin(Double(index) * 0.85) * 2.2).rounded())
            let cooling = index > 3 ? index - 3 : 0
            return HourlyStripPoint(
                time: index == 0 ? nowLabel : String(format: "%02d", (start + index) % 24),
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
