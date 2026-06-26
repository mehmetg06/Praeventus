#if canImport(SwiftUI)
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WeatherStore
    @StateObject private var searchVM = SearchViewModel()
    @FocusState private var searchFocused: Bool

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
        VStack(spacing: 0) {
            topBar
            contentArea
        }
        .onChange(of: searchVM.query) { _, newValue in
            searchVM.onQueryChanged(newValue)
        }
    }

    // MARK: - Top bar (non-scrolling)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            CitySearchBar(
                text: $searchVM.query,
                isFocused: $searchFocused,
                isSearching: searchVM.isSearching,
                isLocating: searchVM.isLocating,
                onLocationTap: { Task { await handleLocationTap() } }
            )
            // Location / search errors shown inline when the dropdown is hidden
            if let error = searchVM.searchError, !searchVM.isShowingSuggestions {
                Text(error)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.red.opacity(0.78))
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.20), value: searchVM.searchError != nil)
    }

    // MARK: - Content area with suggestions overlay

    private var contentArea: some View {
        ZStack(alignment: .top) {
            scrollContent

            if searchVM.isShowingSuggestions {
                tapToDismiss
                suggestionsOverlay
            }
        }
        .animation(
            .spring(response: 0.28, dampingFraction: 0.82),
            value: searchVM.isShowingSuggestions
        )
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
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
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    /// Invisible full-screen layer that catches taps outside the suggestions panel.
    private var tapToDismiss: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { dismissSearch() }
    }

    private var suggestionsOverlay: some View {
        SearchSuggestionsView(
            suggestions: searchVM.suggestions,
            error: searchVM.searchError,
            onSelect: { result in Task { await selectSuggestion(result) } }
        )
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AtmosphereOrb(symbolName: atmosphere.symbolName)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
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

            // Focuses the search bar, letting the user type or tap the GPS button.
            Button(action: { searchFocused = true }) {
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
                Button(action: { searchFocused = true }) {
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
        if !recommendedActivities.isEmpty {
            activitySuitabilityCard
        }
        storyCard
        hourlyPreview
        #if canImport(Charts)
        WeatherChartsView(hourly: store.hourly, daily: store.daily, tint: paletteTint)
        #endif
    }

    private var activitySuitabilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 15, weight: .light))
                Text("home.activities.heading")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.56))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(recommendedActivities.prefix(3)) { suitability in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suitability.activity.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            if !suitability.warnings.isEmpty {
                                Text(suitability.warnings.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.66))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(suitability.suitability.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(suitabilityColor(suitability.suitability).opacity(0.3))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 28, intensity: 0.13, highlightOpacity: 0.18, innerShadowOpacity: 0.22, borderOpacity: 0.22, tintColor: paletteTint))
    }

    private var recommendedActivities: [ActivitySuitability] {
        let suitabilities = ActivityAnalysisEngine.evaluateAllActivities(given: weather)
        return ActivityAnalysisEngine.recommendedActivities(from: suitabilities)
    }

    private func suitabilityColor(_ level: SuitabilityLevel) -> Color {
        switch level {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .orange
        case .unsuitable: return .red
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
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            GlassMetric(symbol: "gauge.with.dots.needle.bottom.50percent", title: String(localized: "metric.pressure", defaultValue: "Pressure"), value: "\(Int(weather.pressure.rounded()))", unit: "hPa", accent: .cyan, tintColor: paletteTint)
            GlassMetric(symbol: "humidity", title: String(localized: "metric.humidity", defaultValue: "Humidity"), value: "\(Int(weather.humidity.rounded()))", unit: "%", accent: .blue, tintColor: paletteTint)
            GlassMetric(symbol: "wind", title: String(localized: "metric.wind", defaultValue: "Wind"), value: "\(Int(weather.windSpeed.rounded()))", unit: String(localized: "unit.kmh", defaultValue: "km/h"), accent: .mint, tintColor: paletteTint)
            GlassMetric(symbol: "sun.max", title: String(localized: "metric.uvIndex", defaultValue: "UV Index"), value: "\(weather.uvIndex)", unit: uvIndexLabel, accent: uvIndexAccent, tintColor: paletteTint)
            GlassMetric(symbol: "thermometer.medium", title: String(localized: "metric.dewPoint", defaultValue: "Dew Point"), value: "\(Int(weather.dewPoint.rounded()))", unit: "°C", accent: .teal, tintColor: paletteTint)
            GlassMetric(symbol: "wind.circle", title: String(localized: "metric.windGust", defaultValue: "Wind Gust"), value: "\(Int(weather.windGustSpeed.rounded()))", unit: String(localized: "unit.kmh", defaultValue: "km/h"), accent: .orange, tintColor: paletteTint)
            GlassMetric(symbol: "safari", title: String(localized: "metric.windDir", defaultValue: "Direction"), value: windDirectionLabel(weather.windDirection), unit: "\(weather.windDirection)°", accent: .indigo, tintColor: paletteTint)
            GlassMetric(symbol: "eye", title: String(localized: "metric.visibility", defaultValue: "Visibility"), value: visibilityKmDisplay, unit: "km", accent: .purple, tintColor: paletteTint)
            GlassMetric(symbol: "umbrella.fill", title: String(localized: "metric.rainProb", defaultValue: "Rain"), value: "\(Int(weather.rainProbability.rounded()))", unit: "%", accent: Color(red: 0.2, green: 0.4, blue: 1.0), tintColor: paletteTint)
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

    private var uvIndexLabel: String {
        switch weather.uvIndex {
        case 0...2: return String(localized: "uv.low", defaultValue: "Low")
        case 3...5: return String(localized: "uv.moderate", defaultValue: "Moderate")
        case 6...7: return String(localized: "uv.high", defaultValue: "High")
        case 8...10: return String(localized: "uv.veryHigh", defaultValue: "Very High")
        default:    return String(localized: "uv.extreme", defaultValue: "Extreme")
        }
    }

    private var uvIndexAccent: Color {
        switch weather.uvIndex {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default:    return .purple
        }
    }

    private func windDirectionLabel(_ degrees: Int) -> String {
        let normalized = ((degrees % 360) + 360) % 360
        let index = Int((Double(normalized) / 45.0).rounded()) % 8
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][index]
    }

    private var visibilityKmDisplay: String {
        // Open-Meteo returns visibility in meters; convert to km for display.
        let km = weather.visibility > 200 ? weather.visibility / 1000 : weather.visibility
        return "\(Int(km.rounded()))"
    }

    // MARK: - Search actions

    private func selectSuggestion(_ result: GeocodingResult) async {
        searchVM.dismissSuggestions()
        searchFocused = false
        searchVM.clearSearch()
        await store.load(
            latitude: result.latitude,
            longitude: result.longitude,
            name: result.name,
            country: result.country ?? ""
        )
    }

    private func handleLocationTap() async {
        #if canImport(CoreLocation)
        searchFocused = false
        searchVM.dismissSuggestions()
        guard let loc = await searchVM.requestCurrentLocation() else { return }
        await store.load(
            latitude: loc.latitude,
            longitude: loc.longitude,
            name: loc.name,
            country: loc.country
        )
        #endif
    }

    private func dismissSearch() {
        searchFocused = false
        searchVM.dismissSuggestions()
    }
}

// MARK: - Supporting types (private to this file)

private struct HourlyStripPoint: Identifiable {
    let id = UUID()
    let time: String
    let temperature: Int
    let rainProbability: Int
    let symbol: String

    static func synthetic(from weather: WeatherData, atmosphere: AtmosphericState) -> [HourlyStripPoint] {
        let start = Int(weather.hour.rounded())
        let base  = Int(weather.temperature.rounded())
        let rain  = Int(weather.rainProbability.rounded())
        let nowLabel = String(localized: "home.now", defaultValue: "Now")
        return (0..<6).map { index in
            let wave    = Int((sin(Double(index) * 0.85) * 2.2).rounded())
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
