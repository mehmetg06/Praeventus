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
        astronomicalCard
        hourlyPreview
        #if canImport(Charts)
        WeatherChartsView(hourly: store.hourly, daily: store.daily, tint: paletteTint)
        #endif
    }

    private var astronomicalCard: some View {
        AstronomicalCard(
            analysis: AstronomicalEngine.analyze(
                at: Date(),
                latitude: store.location?.latitude ?? 0,
                longitude: store.location?.longitude ?? 0
            ),
            tintColor: paletteTint
        )
    }

    private var activitySuitabilityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .semibold))
                Text("home.activities.heading")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 0) {
                ForEach(Array(recommendedActivities.prefix(3).enumerated()), id: \.offset) { index, suitability in
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(suitabilityColor(suitability.suitability).opacity(0.15))
                                    .frame(width: 38, height: 38)
                                Image(systemName: suitability.activity.type.symbolName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(suitabilityColor(suitability.suitability))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(suitability.activity.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                if !suitability.warnings.isEmpty {
                                    Text(suitability.warnings.first ?? "")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 0)

                            Text(suitability.suitability.displayName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(suitabilityColor(suitability.suitability))
                                .padding(.vertical, 5)
                                .padding(.horizontal, 12)
                                .background(suitabilityColor(suitability.suitability).opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 12)

                        if index < recommendedActivities.prefix(3).count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.08))
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .padding(20)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: severity.isNegative ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("home.story.heading")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(severity.isNegative ? .white : .white.opacity(0.56))

            Text(atmosphere.story)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .lineSpacing(6)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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
            .padding(.horizontal, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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

// MARK: - Astronomical Card

private struct AstronomicalCard: View {
    let analysis: AstronomicalAnalysis
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 15, weight: .light))
                Text(String(localized: "astro.heading", defaultValue: "ASTRONOMICAL"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.56))

            SunArcView(analysis: analysis)

            HStack(spacing: 10) {
                moonPanel.frame(maxWidth: .infinity)
                altitudePanel.frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(ThinGlassShape(
            cornerRadius: 28,
            intensity: 0.13,
            highlightOpacity: 0.18,
            innerShadowOpacity: 0.22,
            borderOpacity: 0.22,
            tintColor: tintColor
        ))
    }

    private var moonPanel: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: moonSymbol)
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(.white.opacity(0.22))
                    .blur(radius: 10)
                Image(systemName: moonSymbol)
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(.white.opacity(0.92))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(analysis.moonPhase.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.10)).frame(height: 3)
                        Capsule()
                            .fill(.white.opacity(0.80))
                            .frame(width: max(2, geo.size.width * actualMoonIllumination), height: 3)
                    }
                }
                .frame(height: 3)

                Text("\(Int(actualMoonIllumination * 100))% " + String(localized: "astro.lit", defaultValue: "lit"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var altitudePanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(altitudeColor)
                Text(String(localized: "astro.sunAltitude", defaultValue: "Altitude"))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }

            Text(String(format: "%.1f°", analysis.sunAltitude))
                .font(.system(size: 22, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)

            Text(altitudeLabel)
                .font(.caption2)
                .foregroundStyle(altitudeColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Converts cycle position (0–1) to actual visible illumination (0=new, 1=full, 0=new).
    private var actualMoonIllumination: Double {
        (1.0 - cos(analysis.moonBrightness * 2.0 * .pi)) / 2.0
    }

    private var moonSymbol: String {
        switch analysis.moonPhase {
        case .newMoon:        return "moonphase.new.moon"
        case .waxingCrescent: return "moonphase.waxing.crescent"
        case .firstQuarter:   return "moonphase.first.quarter"
        case .waxingGibbous:  return "moonphase.waxing.gibbous"
        case .fullMoon:       return "moonphase.full.moon"
        case .waningGibbous:  return "moonphase.waning.gibbous"
        case .lastQuarter:    return "moonphase.last.quarter"
        case .waningCrescent: return "moonphase.waning.crescent"
        }
    }

    private var altitudeLabel: String {
        switch analysis.sunAltitude {
        case 45...:   return String(localized: "astro.alt.high",  defaultValue: "High in sky")
        case 15..<45: return String(localized: "astro.alt.above", defaultValue: "Above horizon")
        case 0..<15:  return String(localized: "astro.alt.near",  defaultValue: "Near horizon")
        case -6..<0:  return String(localized: "astro.alt.civil", defaultValue: "Civil twilight")
        default:      return String(localized: "astro.alt.below", defaultValue: "Below horizon")
        }
    }

    private var altitudeColor: Color {
        switch analysis.sunAltitude {
        case 45...:   return .yellow
        case 15..<45: return Color(red: 1.0, green: 0.85, blue: 0.3)
        case 0..<15:  return .orange
        case -6..<0:  return Color(red: 1.0, green: 0.52, blue: 0.25)
        default:      return .white.opacity(0.32)
        }
    }
}

// MARK: - Sun Arc Canvas

private struct SunArcView: View {
    let analysis: AstronomicalAnalysis

    private var sunProgress: Double {
        let now  = Date()
        let rise = analysis.sunriseSunset.sunrise
        let set  = analysis.sunriseSunset.sunset
        guard rise < set,
              abs(rise.timeIntervalSinceNow) < 365 * 24 * 3600,
              abs(set.timeIntervalSinceNow)  < 365 * 24 * 3600
        else { return 0 }
        if now <= rise { return 0 }
        if now >= set  { return 1 }
        return now.timeIntervalSince(rise) / set.timeIntervalSince(rise)
    }

    private var isAboveHorizon: Bool { analysis.sunAltitude > 0 }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func timeStr(_ date: Date) -> String {
        guard abs(date.timeIntervalSinceNow) < 365 * 24 * 3600 else { return "--:--" }
        return Self.timeFmt.string(from: date)
    }

    private var daylightLabel: String {
        let h = Int(analysis.daylightHours)
        let m = Int((analysis.daylightHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var body: some View {
        VStack(spacing: 8) {
            Canvas { ctx, size in
                let cx     = size.width / 2
                let cy     = size.height - 4
                let radius = min(size.width / 2 - 12, size.height - 10)
                let t      = sunProgress

                // Faint dashed background arc
                var bgArc = Path()
                bgArc.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
                             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                ctx.stroke(bgArc, with: .color(.white.opacity(0.10)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))

                // Coloured progress arc (orange → yellow → orange)
                if t > 0.005 {
                    let endDeg = 180.0 - t * 180.0
                    var prog = Path()
                    prog.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
                                startAngle: .degrees(180), endAngle: .degrees(endDeg), clockwise: false)
                    ctx.stroke(
                        prog,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: Color(red: 1.0, green: 0.45, blue: 0.2).opacity(0.75), location: 0),
                                .init(color: Color(red: 1.0, green: 0.88, blue: 0.3).opacity(0.95), location: 0.5),
                                .init(color: Color(red: 1.0, green: 0.55, blue: 0.2).opacity(0.75), location: 1),
                            ]),
                            startPoint: CGPoint(x: cx - radius, y: cy),
                            endPoint:   CGPoint(x: cx + radius, y: cy)
                        ),
                        lineWidth: 2.5
                    )
                }

                // Dashed horizon line
                var hor = Path()
                hor.move(to: CGPoint(x: cx - radius - 10, y: cy))
                hor.addLine(to: CGPoint(x: cx + radius + 10, y: cy))
                ctx.stroke(hor, with: .color(.white.opacity(0.18)),
                           style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))

                // Sunrise / sunset endpoint dots
                let riseR = CGRect(x: cx - radius - 3.5, y: cy - 3.5, width: 7, height: 7)
                let setR  = CGRect(x: cx + radius - 3.5, y: cy - 3.5, width: 7, height: 7)
                ctx.fill(Circle().path(in: riseR), with: .color(Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.80)))
                ctx.fill(Circle().path(in: setR),  with: .color(Color(red: 1.0, green: 0.4, blue: 0.1).opacity(0.65)))

                // Sun dot at current position along the arc
                let sunAngle = Double.pi * (1.0 - t)
                let sunX = cx + radius * cos(sunAngle)
                let sunY = cy - radius * sin(sunAngle)

                if isAboveHorizon {
                    let g1 = CGRect(x: sunX - 14, y: sunY - 14, width: 28, height: 28)
                    let g2 = CGRect(x: sunX - 7,  y: sunY - 7,  width: 14, height: 14)
                    let g3 = CGRect(x: sunX - 4,  y: sunY - 4,  width: 8,  height: 8)
                    ctx.fill(Circle().path(in: g1), with: .color(.yellow.opacity(0.15)))
                    ctx.fill(Circle().path(in: g2), with: .color(.yellow.opacity(0.38)))
                    ctx.fill(Circle().path(in: g3), with: .color(.yellow))
                }
            }
            .frame(height: 78)

            // Sunrise / daylight / sunset labels
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(.orange)
                    Text(timeStr(analysis.sunriseSunset.sunrise))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                .font(.caption2)

                Spacer()

                VStack(spacing: 1) {
                    Text(daylightLabel)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(String(localized: "astro.daylight", defaultValue: "daylight"))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.white.opacity(0.36))
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "sunset.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.25))
                    Text(timeStr(analysis.sunriseSunset.sunset))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.25))
                }
                .font(.caption2)
            }
        }
    }
}
#endif
