#if canImport(SwiftUI)
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WeatherStore
    @StateObject private var searchVM = SearchViewModel()
    @FocusState private var searchFocused: Bool

    private var weather: WeatherData { store.weather }
    private var atmosphere: AtmosphericState { store.atmosphere }
    private var paletteTint: Color { atmosphere.condition.palette[1] }

    @State private var currentMetricIndex = 0
    @State private var weatherNarrative: String = ""
    @State private var isFetchingNarrative = false
    @State private var minutecastPoints: [MinutePoint] = []

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
            // Show only when the barometer and the displayed forecast are co-located:
            // the sensor reads the user's physical surroundings, not a remote city.
            if store.isGPSLocation, let alert = store.stormAlert {
                StormWarningBanner(alert: alert)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
            }
            contentArea
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.74), value: store.stormAlert != nil)
        .onChange(of: searchVM.query) { _, newValue in
            searchVM.onQueryChanged(newValue)
        }
        .onChange(of: store.phase) { _, newPhase in
            // Clear narrative UI state when a new location load begins.
            if case .loading = newPhase {
                weatherNarrative = ""
                isFetchingNarrative = false
            }
        }
        // Trigger narrative fetch and minutecast recompute whenever real forecast
        // data arrives — fires on every applyForecast call (cache hit, network
        // refresh, or location switch) regardless of whether phase stays .loaded
        // or city is empty (GPS location).
        .onChange(of: store.forecastID) { _, _ in
            minutecastPoints = computeMinutecastPoints()
            startNarrativeFetch()
        }
        .onAppear {
            // Catch re-appears (tab switch back) when data is ready but narrative is absent.
            if case .loaded = store.phase, weatherNarrative.isEmpty, !isFetchingNarrative {
                startNarrativeFetch()
            }
            minutecastPoints = computeMinutecastPoints()
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
        .scrollContentBackground(.hidden)
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
                    .background(ThinGlassShape(cornerRadius: 20))
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 28))
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
        .background(ThinGlassShape(cornerRadius: 28))
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
                        .background(ThinGlassShape(cornerRadius: 16))
                }
                Button(action: { searchFocused = true }) {
                    Label("home.empty.cta", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(ThinGlassShape(cornerRadius: 16))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 28))
        .padding(.top, 24)
    }

    @ViewBuilder
    private var loadedContent: some View {
        temperatureHero
        storyCard
        if isFetchingNarrative {
            fetchingNarrativeCard
        } else if !weatherNarrative.isEmpty
            && !weatherNarrative.contains("**")
            && !weatherNarrative.contains("Analyze")
            && weatherNarrative.count < 600 {
            narrativeCard
        }
        if !minutecastPoints.isEmpty {
            MinutecastGraphCard(minutePoints: minutecastPoints, paletteTint: paletteTint)
        }
        atmosphericSignalsCard
        HealthInsightsCard(insights: store.healthInsights)
        rotatingMetricCard
        let activities = recommendedActivities
        if !activities.isEmpty {
            activitySuitabilityCard(activities)
        }
        astronomicalCard
        hourlyPreview
        if !store.daily.isEmpty {
            dailyForecastCard
        }
        #if canImport(Charts)
        WeatherChartsView(hourly: store.hourly, daily: store.daily, tint: paletteTint)
        #endif
    }

    private var fetchingNarrativeCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white.opacity(0.6))
            Text(String(localized: "narrative.fetching", defaultValue: "Fetching weather insight…"))
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 28))
    }

    private var narrativeCard: some View {
        Text(weatherNarrative)
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThinGlassShape(cornerRadius: 28))
    }

    private func computeMinutecastPoints() -> [MinutePoint] {
        guard store.hourly.count >= 2 else { return [] }
        let anchors = Array(store.hourly.prefix(4))
        let all = MinutecastEngine.interpolate(
            temperatures:      anchors.map(\.temperature),
            humidities:        anchors.map(\.humidity),
            windSpeeds:        anchors.map(\.windSpeed),
            anchorDate:        anchors[0].date,
            latitude:          store.location?.latitude  ?? 0,
            longitude:         store.location?.longitude ?? 0,
            dailyMaxUV:        Double(store.daily.first?.uvIndexMax ?? weather.uvIndex),
            cloudCoverPercent: atmosphere.cloudCover * 100
        )
        return Array(all.prefix(61))
    }

    private func startNarrativeFetch() {
        weatherNarrative = ""
        isFetchingNarrative = true
        let w = weather
        let firstDaily = store.daily.first
        let provider = CloudflareWeatherProvider(baseURL: WeatherSettings.cloudflareWorkerURL)
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        Task {
            let text = await provider.narrative(
                temp: w.temperature,
                feelsLike: w.feelsLike,
                humidity: w.humidity,
                windSpeed: w.windSpeed,
                windDir: Double(w.windDirection),
                weatherCode: w.weatherCode,
                tempMax: firstDaily?.max ?? 0,
                tempMin: firstDaily?.min ?? 0,
                precipProb: w.rainProbability,
                uvIndex: Double(w.uvIndex),
                visibility: w.visibility,
                pressure: w.pressure,
                lang: lang
            )
            await MainActor.run {
                weatherNarrative = text
                isFetchingNarrative = false
            }
        }
    }

    private var astronomicalCard: some View {
        AstronomicalCard(analysis: store.astronomicalAnalysis(at: Date()))
    }

    private func activitySuitabilityCard(_ activities: [ActivitySuitability]) -> some View {
        let top = Array(activities.prefix(3))
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(localized: "home.activities.heading", defaultValue: "TODAY'S ACTIVITIES"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.offset) { index, suitability in
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

                        if index < top.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.08))
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 28))
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
        VStack(alignment: .center, spacing: 8) {
            Text("\(Int(weather.temperature.rounded()))°")
                .font(.system(size: 110, weight: .thin, design: .default))
                .minimumScaleFactor(0.70)
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            Text(atmosphere.condition.displayName)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))

            Text(String(format: String(localized: "home.feelsLike", defaultValue: "Feels like %lld°"), Int(weather.feelsLike.rounded())))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))

            if store.isStale {
                Label(
                    String(localized: "home.stale", defaultValue: "Cached data"),
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.orange.opacity(0.9))
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(.orange.opacity(0.14))
                .clipShape(Capsule())
                .padding(.top, 2)
            }

            if let confidence = store.fusionConfidence, !confidence.models.isEmpty {
                HStack(spacing: 5) {
                    ForEach(confidence.models, id: \.self) { model in
                        Text(model)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.vertical, 3)
                            .padding(.horizontal, 7)
                            .background(.white.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.30))
                    Text("\(confidence.agreementPercent)% " + String(localized: "home.fusion.agreement", defaultValue: "consensus"))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
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
                .font(.system(size: 20, weight: .regular))
                .lineSpacing(6)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(ThinGlassShape(cornerRadius: 28))
    }

    private var storyTint: Color {
        switch severity {
        case .alert: return .red
        case .caution: return .orange
        case .calm: return paletteTint
        }
    }

    private var rotatingMetrics: [MetricItem] {
        [
            MetricItem(
                icon: "humidity",
                title: String(localized: "metric.humidity", defaultValue: "Nem"),
                value: "\(Int(weather.humidity.rounded()))%",
                description: "Havadaki su buharı oranı. %60 üzeri bunaltıcı hissettirebilir.",
                accent: .blue
            ),
            MetricItem(
                icon: "gauge.with.dots.needle.bottom.50percent",
                title: String(localized: "metric.pressure", defaultValue: "Basınç"),
                value: "\(Int(weather.pressure.rounded())) hPa",
                description: "Atmosferin uyguladığı kuvvet. Düşük basınç yağış, yüksek basınç açık hava getirir.",
                accent: .cyan
            ),
            MetricItem(
                icon: "wind",
                title: String(localized: "metric.wind", defaultValue: "Rüzgar"),
                value: "\(Int(weather.windSpeed.rounded())) km/h",
                description: "Rüzgar hızlandıkça hissedilen sıcaklık düşer.",
                accent: .mint
            ),
            MetricItem(
                icon: "sun.max",
                title: String(localized: "metric.uvIndex", defaultValue: "UV İndeksi"),
                value: "\(weather.uvIndex) · \(uvIndexLabel)",
                description: "Ultraviyole radyasyon seviyesi. Yüksek UV'de cilt koruması şarttır.",
                accent: uvIndexAccent
            ),
            MetricItem(
                icon: "thermometer.medium",
                title: String(localized: "metric.dewPoint", defaultValue: "Çiy Noktası"),
                value: "\(Int(weather.dewPoint.rounded()))°C",
                description: "Havanın doygunluğa ulaştığı sıcaklık. Yüksekse yapışkan hava hissedilir.",
                accent: .teal
            ),
            MetricItem(
                icon: "wind.circle",
                title: String(localized: "metric.windGust", defaultValue: "Ani Rüzgar"),
                value: "\(Int(weather.windGustSpeed.rounded())) km/h",
                description: "Anlık maksimum rüzgar hızı. Yüksek değerler dışarıda dikkat gerektirir.",
                accent: .orange
            ),
            MetricItem(
                icon: "safari",
                title: String(localized: "metric.windDir", defaultValue: "Yön"),
                value: windDirectionLabel(weather.windDirection),
                description: "Rüzgarın estiği yön. Bulut hareketini ve hava koşullarını etkiler.",
                accent: .indigo
            ),
            MetricItem(
                icon: "eye",
                title: String(localized: "metric.visibility", defaultValue: "Görüş"),
                value: "\(visibilityKmDisplay) km",
                description: "Gözle görülebilen maksimum mesafe. Sis ve yağış görüş mesafesini kısaltır.",
                accent: .purple
            ),
            MetricItem(
                icon: "umbrella.fill",
                title: String(localized: "metric.rainProb", defaultValue: "Yağış"),
                value: "%\(Int(weather.rainProbability.rounded()))",
                description: "Bir saat içinde yağış düşme ihtimali. %70 üzeri yağmur kıyafeti önerilir.",
                accent: Color(red: 0.2, green: 0.4, blue: 1.0)
            )
        ]
    }

    private var rotatingMetricCard: some View {
        let metrics = rotatingMetrics
        let safeIndex = currentMetricIndex % max(1, metrics.count)
        let metric = metrics[safeIndex]

        return VStack(alignment: .leading, spacing: 0) {
            MetricProgressBar(metricsCount: metrics.count, currentIndex: currentMetricIndex) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentMetricIndex = (currentMetricIndex + 1) % metrics.count
                }
            }

            VStack(alignment: .center, spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.system(size: 42, weight: .thin))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(metric.accent)

                Text(metric.value)
                    .font(.system(size: 46, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(metric.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.54))

                Text(metric.description)
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(.white.opacity(0.80))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .id(safeIndex)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .padding(22)
        .background(ThinGlassShape(cornerRadius: 28))
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        withAnimation(.easeInOut(duration: 0.4)) {
                            if location.x < geometry.size.width / 2 {
                                currentMetricIndex = max(0, currentMetricIndex - 1)
                            } else {
                                currentMetricIndex = (currentMetricIndex + 1) % metrics.count
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Atmospheric Signals Card

    private var atmosphericSignalsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(localized: "home.atmosphere.heading", defaultValue: "ATMOSPHERE"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.56))

            HStack(spacing: 8) {
                atmosphereChip(
                    icon: "bolt.fill",
                    label: String(localized: "home.stormRisk", defaultValue: "Storm Risk"),
                    value: atmosphere.stormRisk.displayName,
                    color: riskLevelColor(atmosphere.stormRisk)
                )
                atmosphereChip(
                    icon: "cloud.rain.fill",
                    label: String(localized: "home.rainSignal", defaultValue: "Rain Signal"),
                    value: atmosphere.rainSignal.displayName,
                    color: riskLevelColor(atmosphere.rainSignal)
                )
                atmosphereChip(
                    icon: "eye.fill",
                    label: String(localized: "metric.visibility", defaultValue: "Visibility"),
                    value: atmosphere.visibility.displayName,
                    color: visibilityLevelColor(atmosphere.visibility)
                )
            }

            VStack(spacing: 10) {
                atmosphereProgressRow(
                    label: String(localized: "home.instability", defaultValue: "Instability"),
                    value: atmosphere.instability,
                    accent: instabilityAccentColor(atmosphere.instability)
                )
                atmosphereProgressRow(
                    label: String(localized: "home.cloudCover", defaultValue: "Cloud Cover"),
                    value: atmosphere.cloudCover,
                    accent: .white.opacity(0.75)
                )
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 28))
    }

    private func atmosphereChip(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.50))
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func atmosphereProgressRow(label: String, value: Double, accent: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: 4)
                    Capsule()
                        .fill(accent.opacity(0.80))
                        .frame(width: max(4, geo.size.width * CGFloat(value)), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private func riskLevelColor(_ risk: AtmosphericRisk) -> Color {
        switch risk {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        }
    }

    private func visibilityLevelColor(_ vis: AtmosphericVisibility) -> Color {
        switch vis {
        case .clear: return .green
        case .reduced: return .yellow
        case .poor: return .orange
        }
    }

    private func instabilityAccentColor(_ value: Double) -> Color {
        switch value {
        case 0..<0.34: return .green
        case 0.34..<0.67: return .orange
        default: return .red
        }
    }

    // MARK: - 7-Day Daily Forecast Card

    private var dailyForecastCard: some View {
        let days = Array(store.daily.prefix(7))
        let globalMin = days.map(\.min).min() ?? 0
        let globalMax = days.map(\.max).max() ?? 0
        let tempRange = max(1.0, globalMax - globalMin)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(localized: "home.daily.heading", defaultValue: "7-DAY FORECAST"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text(index == 0
                                ? String(localized: "home.today", defaultValue: "Today")
                                : dayAbbreviation(day.date))
                                .font(.system(size: 14,
                                              weight: index == 0 ? .semibold : .regular,
                                              design: .rounded))
                                .foregroundStyle(.white.opacity(index == 0 ? 0.95 : 0.75))
                                .frame(width: 52, alignment: .leading)

                            Image(systemName: day.condition.symbolName)
                                .font(.system(size: 16, weight: .light))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 30)

                            if day.precipitationAmount > 0.5 {
                                Text(String(format: "%.0fmm", day.precipitationAmount))
                                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color(red: 0.4, green: 0.65, blue: 1.0))
                                    .frame(width: 38, alignment: .leading)
                            } else {
                                Color.clear.frame(width: 38)
                            }

                            Spacer(minLength: 8)

                            Text("\(Int(day.min.rounded()))°")
                                .font(.system(size: 14, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(width: 32, alignment: .trailing)

                            GeometryReader { geo in
                                let w = geo.size.width
                                let lo = CGFloat((day.min - globalMin) / tempRange)
                                let hi = CGFloat((day.max - globalMin) / tempRange)
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.10))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [dayTempColor(day.min), dayTempColor(day.max)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .frame(width: max(6, w * (hi - lo)), height: 4)
                                        .offset(x: w * lo)
                                }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 8)
                            .frame(width: 70)

                            Text("\(Int(day.max.rounded()))°")
                                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.92))
                                .frame(width: 32, alignment: .leading)
                        }
                        .padding(.vertical, 11)

                        if index < days.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.07))
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 28))
    }

    private func dayAbbreviation(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayTempColor(_ temp: Double) -> Color {
        switch temp {
        case ..<0:    return Color(red: 0.5, green: 0.72, blue: 1.0)
        case 0..<10:  return Color(red: 0.55, green: 0.82, blue: 1.0)
        case 10..<20: return Color(red: 0.3, green: 0.85, blue: 0.72)
        case 20..<30: return Color(red: 1.0, green: 0.82, blue: 0.3)
        case 30..<38: return Color(red: 1.0, green: 0.52, blue: 0.22)
        default:      return Color(red: 1.0, green: 0.22, blue: 0.22)
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
        .background(ThinGlassShape(cornerRadius: 26))
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
        // Use loadCurrentLocation so WeatherStore knows the barometer and the
        // forecast are physically co-located — enabling the storm warning banner.
        await store.loadCurrentLocation(
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

private struct MetricItem {
    let icon: String
    let title: String
    let value: String
    let description: String
    let accent: Color
}

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

// Isolated progress bar so its 6-second @State animation never invalidates HomeView's body.
private struct MetricProgressBar: View {
    let metricsCount: Int
    let currentIndex: Int
    let onAdvance: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<metricsCount, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.white)
                                .frame(width: barWidth(for: index, totalWidth: geo.size.width))
                        }
                    }
            }
        }
        .padding(.bottom, 22)
        .task(id: currentIndex) {
            progress = 0
            withAnimation(.linear(duration: 6.0)) { progress = 1.0 }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            onAdvance()
        }
    }

    private func barWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        let safe = currentIndex % max(1, metricsCount)
        if index < safe { return totalWidth }
        if index > safe { return 0 }
        return totalWidth * progress
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
            cornerRadius: 28
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

// MARK: - Storm Warning Banner

private struct StormWarningBanner: View {
    let alert: StormAlert
    @State private var pulseOpacity: Double = 0.65

    private var accentColor: Color {
        switch alert.severity {
        case .watch:   return .orange
        case .warning: return Color(red: 1.0, green: 0.28, blue: 0.06)
        case .extreme: return .red
        }
    }

    private var icon: String {
        switch alert.severity {
        case .watch:   return "cloud.bolt"
        case .warning: return "cloud.bolt.fill"
        case .extreme: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(pulseOpacity), lineWidth: 1.5)
                    .frame(width: 50, height: 50)
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.severity.localizedTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                Text(alert.severity.localizedDescription)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "−%.1f", alert.pressureDropHPa))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accentColor)
                Text("hPa/\(alert.windowMinutes)dk")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Material.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(accentColor.opacity(0.10))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: accentColor.opacity(0.60), location: 0),
                                .init(color: accentColor.opacity(0.18), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: accentColor.opacity(0.32), radius: 16, y: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.08
            }
        }
    }
}

// MARK: - Minutecast Graph Card

private struct MinutecastGraphCard: View {
    let minutePoints: [MinutePoint]
    let paletteTint: Color

    private var temperatures: [Double] { minutePoints.map(\.temperature) }
    private var tempMin: Double { (temperatures.min() ?? 0) - 0.5 }
    private var tempMax: Double { (temperatures.max() ?? 0) + 0.5 }
    private var tempRange: Double { max(0.1, tempMax - tempMin) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(localized: "home.minutecast.heading",
                            defaultValue: "DAKİKALIK TAHMİN"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Spacer()
                Text(String(localized: "home.minutecast.label", defaultValue: "60 dk"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .foregroundStyle(.white.opacity(0.56))

            GeometryReader { _ in
                Canvas { ctx, size in
                    drawGraph(ctx: ctx, size: size)
                }
            }
            .frame(height: 90)

            HStack(spacing: 0) {
                ForEach(
                    [String(localized: "minutecast.now", defaultValue: "Şimdi"),
                     "+15m", "+30m", "+45m",
                     String(localized: "minutecast.60m", defaultValue: "+60m")],
                    id: \.self
                ) { label in
                    Text(label)
                        .font(.system(size: 9, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(maxWidth: .infinity,
                               alignment: label.hasSuffix("Şimdi") || label == "Şimdi"
                                   ? .leading
                                   : label.hasSuffix("60m") || label == "+60m"
                                       ? .trailing
                                       : .center)
                }
            }

            if let first = minutePoints.first, let last = minutePoints.last {
                let delta = last.temperature - first.temperature
                let isRising = delta >= 0.05
                let isFalling = delta <= -0.05
                HStack(spacing: 6) {
                    Text(String(format: "%.1f°C", first.temperature))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.88))
                    Image(systemName: isRising ? "arrow.up.right" : isFalling ? "arrow.down.right" : "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isRising ? .orange : isFalling ? .cyan : .white.opacity(0.45))
                    Text(isRising
                         ? String(format: "+%.1f°", delta)
                         : String(format: "%.1f°", delta))
                        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isRising ? .orange.opacity(0.85) : isFalling ? .cyan.opacity(0.85) : .white.opacity(0.45))
                    Spacer()
                    Text(String(localized: "minutecast.temp.label",
                                defaultValue: "Sıcaklık Eğrisi"))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 28))
    }

    private func drawGraph(ctx: GraphicsContext, size: CGSize) {
        guard minutePoints.count > 1 else { return }
        let w = size.width
        let h = size.height
        let n = minutePoints.count

        func px(_ i: Int) -> CGFloat { w * CGFloat(i) / CGFloat(n - 1) }
        func py(_ temp: Double) -> CGFloat {
            let norm = (temp - tempMin) / tempRange
            return h - CGFloat(norm) * (h - 12) - 6
        }

        // Dashed vertical grid at 15-minute marks
        for tick in stride(from: 15, through: 45, by: 15) where tick < n {
            var grid = Path()
            let gx = px(tick)
            grid.move(to:    CGPoint(x: gx, y: 0))
            grid.addLine(to: CGPoint(x: gx, y: h))
            ctx.stroke(grid, with: .color(.white.opacity(0.08)),
                       style: StrokeStyle(lineWidth: 0.75, dash: [3, 4]))
        }

        // Build the smooth polyline from interpolated 1-min points
        var curve = Path()
        curve.move(to: CGPoint(x: px(0), y: py(minutePoints[0].temperature)))
        for i in 1 ..< n {
            curve.addLine(to: CGPoint(x: px(i), y: py(minutePoints[i].temperature)))
        }

        // Gradient fill below the curve
        var fill = curve
        fill.addLine(to: CGPoint(x: px(n - 1), y: h))
        fill.addLine(to: CGPoint(x: px(0),     y: h))
        fill.closeSubpath()
        ctx.fill(fill, with: .linearGradient(
            Gradient(stops: [
                .init(color: paletteTint.opacity(0.42), location: 0),
                .init(color: paletteTint.opacity(0.04), location: 1)
            ]),
            startPoint: CGPoint(x: w / 2, y: 0),
            endPoint:   CGPoint(x: w / 2, y: h)
        ))

        // Stroke the temperature line
        ctx.stroke(curve, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.88), location: 0),
                .init(color: paletteTint.opacity(0.72), location: 1)
            ]),
            startPoint: CGPoint(x: 0,   y: h / 2),
            endPoint:   CGPoint(x: w,   y: h / 2)
        ), lineWidth: 2)

        // "Now" indicator — halo + solid dot
        let nx = px(0)
        let ny = py(minutePoints[0].temperature)
        ctx.fill(Circle().path(in: CGRect(x: nx - 8,   y: ny - 8,   width: 16, height: 16)),
                 with: .color(.white.opacity(0.15)))
        ctx.fill(Circle().path(in: CGRect(x: nx - 3.5, y: ny - 3.5, width: 7,  height: 7)),
                 with: .color(.white))
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

    private func timeStr(_ date: Date) -> String {
        guard abs(date.timeIntervalSinceNow) < 365 * 24 * 3600 else { return "--:--" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = analysis.locationTimezone
        return f.string(from: date)
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
