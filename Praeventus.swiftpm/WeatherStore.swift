
import Foundation
import Combine

/// A place the user has chosen (via search or "use my location"). Persisted so
/// the app reopens on the last location. Coordinates are coarse on purpose.
struct SavedLocation: Codable, Equatable {
    var name: String
    var country: String
    var latitude: Double
    var longitude: Double
    /// True when this location came from the device GPS ("use my location"),
    /// not a manual search. Persisted so `isGPSLocation` — and therefore the
    /// storm banner — survives an app relaunch instead of resetting to hidden
    /// every time `restoreOrPrompt()` reloads the last saved location.
    var isCurrentLocation: Bool = false

    private enum CodingKeys: String, CodingKey {
        case name, country, latitude, longitude, isCurrentLocation
    }

    init(name: String, country: String, latitude: Double, longitude: Double, isCurrentLocation: Bool = false) {
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.isCurrentLocation = isCurrentLocation
    }

    // Custom decoder so locations saved before this flag existed decode with
    // `isCurrentLocation = false` instead of failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        country = try c.decode(String.self, forKey: .country)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        isCurrentLocation = try c.decodeIfPresent(Bool.self, forKey: .isCurrentLocation) ?? false
    }
}

/// Loading lifecycle for the live forecast.
enum LoadPhase: Equatable {
    case idle           // no location chosen yet — prompt to locate/search
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var weather: WeatherData
    @Published private(set) var atmosphere: AtmosphericState
    @Published private(set) var hourly: [HourlyPoint] = []
    @Published private(set) var daily: [DailyRange] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published private(set) var location: SavedLocation?
    /// True while showing the manually-driven Lab snapshot instead of live data.
    @Published private(set) var isSimulating = false
    /// How well the blended models agreed on the current snapshot, if fused.
    @Published private(set) var fusionConfidence: FusionConfidence?
    /// True when the on-screen forecast came from cache and could not be refreshed.
    @Published private(set) var isStale = false
    /// Changes on every applyForecast call (cache or network). Observe this in
    /// HomeView to trigger narrative fetches: phase may stay .loaded and city
    /// may be empty for GPS, so neither is a reliable trigger.
    @Published private(set) var forecastID: UUID = UUID()
    /// Set when the device barometer detects a rapid pressure drop.
    /// Cleared to nil after 30 minutes so the UI doesn't show a stale alarm.
    @Published private(set) var stormAlert: StormAlert?
    /// True when the currently-displayed forecast was loaded via the device GPS
    /// (Current Location), not from a manually-searched remote city.
    /// StormSensorEngine data is only meaningful for the user's physical location,
    /// so the storm banner must be hidden whenever this is false.
    @Published private(set) var isGPSLocation: Bool = false

    // MARK: - Developer sandbox overrides

    /// Playback multiplier (0.1…2.0) for the atmosphere's particle layers.
    @Published var animationSpeed: Double = 1.0
    /// Drops blurs / ultra-thin materials to test layout performance.
    @Published var performanceMode = false
    /// Outlines major render layers in red for clipping/tiling debug.
    @Published var showLayoutBounds = false
    /// Overrides the live moon phase in the astronomical readouts, if set.
    @Published var moonPhaseOverride: MoonPhase?
    /// Forces the health card into a specific medical state, if set.
    @Published private(set) var forcedHealthInsights: HealthInsights?

    private let calibration   = SensorCalibration()
    private let stormSensor   = StormSensorEngine()
    private var stormTask: Task<Void, Never>?
    private static let locationKey = "praeventus.savedLocation"

    /// Seed snapshot used purely so the UI/background have something to render
    /// before the first load. Not a real location — `phase` stays `.idle`.
    init() {
        let seed = WeatherData(
            city: "",
            country: "",
            temperature: 18,
            feelsLike: 18,
            condition: .partlyCloudy,
            humidity: 60,
            pressure: 1013,
            windSpeed: 8,
            windDirection: 0,
            windGustSpeed: 0,
            uvIndex: 0,
            dewPoint: 0,
            visibility: 10,
            rainProbability: 10,
            hour: Double(Calendar.current.component(.hour, from: Date()))
        )
        self.weather = seed
        self.atmosphere = AtmosphericEngine.calculate(from: seed)
        self.location = Self.loadSavedLocation()
    }

    /// Loads the most recent location on launch, if any.
    func restoreOrPrompt() async {
        guard let saved = location else { return }
        await load(saved)
    }

    func load(_ place: SavedLocation) async {
        isSimulating = false
        forcedHealthInsights = nil
        // Single source of truth for whether the storm banner is eligible to
        // show — restored from the persisted flag so a relaunch doesn't reset
        // a GPS-loaded location back to "remote city" and hide the banner.
        isGPSLocation = place.isCurrentLocation
        location = place
        Self.persist(place)

        if WeatherSettings.sensorCalibrationEnabled { calibration.start() }
        startStormMonitoring()

        // Paint cached data instantly (offline-friendly) before the network call.
        if let cached = ForecastCache.load(latitude: place.latitude, longitude: place.longitude) {
            applyForecast(cached.response, city: cached.city, country: cached.country)
            fusionConfidence = cached.confidence
            isStale = !ForecastCache.isFresh(cached)
            phase = .loaded
        } else {
            phase = .loading
        }

        do {
            let (response, confidence) = try await fetchForecast(place)
            applyForecast(response, city: place.name, country: place.country)
            fusionConfidence = confidence
            isStale = false
            phase = .loaded
            ForecastCache.save(
                CachedForecast(
                    response: response, confidence: confidence,
                    city: place.name, country: place.country, timestamp: Date()
                ),
                latitude: place.latitude, longitude: place.longitude
            )
        } catch {
            // Keep cached data on-screen if we have it; only fail when there's nothing.
            if case .loaded = phase {
                isStale = true
            } else {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    private func fetchForecast(_ place: SavedLocation) async throws -> (ForecastResponse, FusionConfidence) {
        let cf = CloudflareWeatherProvider(baseURL: WeatherSettings.cloudflareWorkerURL)
        let forecasts = try await cf.forecast(latitude: place.latitude, longitude: place.longitude)
        let fused = WeatherFusion.fuse(forecasts)
        return (fused.response, fused.confidence)
    }

    /// Maps a response into the app model, applies opt-in sensor calibration, and publishes.
    private func applyForecast(_ response: ForecastResponse, city: String, country: String) {
        let mapped = WeatherMapping.map(response, city: city, country: country)
        hourly = mapped.hourly
        daily = mapped.daily
        var snapshot = mapped.weather
        if WeatherSettings.sensorCalibrationEnabled {
            snapshot = calibration.calibrate(snapshot)
        }
        forecastID = UUID()
        publish(snapshot)
    }

    /// Loads forecast for a searched / saved remote city.
    /// Persists `isCurrentLocation = false` so the storm banner stays suppressed
    /// — the device barometer cannot reflect conditions at a distant location.
    func load(latitude: Double, longitude: Double, name: String, country: String) async {
        await load(SavedLocation(name: name, country: country, latitude: latitude, longitude: longitude, isCurrentLocation: false))
    }

    /// Loads forecast for the user's **current physical location** (GPS).
    /// Persists `isCurrentLocation = true` so the storm banner is permitted — the
    /// device barometer is physically co-located with the displayed forecast —
    /// and stays permitted across app relaunches.
    func loadCurrentLocation(latitude: Double, longitude: Double, name: String, country: String) async {
        await load(SavedLocation(name: name, country: country, latitude: latitude, longitude: longitude, isCurrentLocation: true))
    }

    func retry() async {
        if let location { await load(location) }
    }

    // MARK: - Health insights

    /// Medical-grade thermal/UV insights for the current snapshot, recomputed
    /// from live data on each access. Defaults to Fitzpatrick type 3 / SPF 1.
    /// Returns the sandbox-forced state instead when a medical test is active.
    var healthInsights: HealthInsights {
        if let forcedHealthInsights { return forcedHealthInsights }
        return HealthInsights.make(
            current: weather,
            hourly: hourly,
            dailyMaxTemperatures: daily.map(\.max)
        )
    }

    /// Astronomical analysis for the current location, with the moon phase
    /// replaced when the sandbox is overriding it.
    func astronomicalAnalysis(at date: Date) -> AstronomicalAnalysis {
        let base = AstronomicalEngine.analyze(
            at: date,
            latitude: location?.latitude ?? 0,
            longitude: location?.longitude ?? 0
        )
        guard let phase = moonPhaseOverride else { return base }
        return AstronomicalAnalysis(
            moonPhase: phase,
            moonBrightness: phase.cyclePosition,
            daylightHours: base.daylightHours,
            sunAltitude: base.sunAltitude,
            sunriseSunset: base.sunriseSunset,
            locationTimezone: base.locationTimezone
        )
    }

    // MARK: - Lab (manual simulation, unchanged behaviour)

    func update(
        condition: WeatherCondition? = nil,
        hour: Double? = nil,
        temperature: Double? = nil,
        humidity: Double? = nil,
        pressure: Double? = nil,
        windSpeed: Double? = nil,
        rainProbability: Double? = nil
    ) {
        isSimulating = true
        forcedHealthInsights = nil
        phase = .loaded
        var next = weather
        next.city = String(localized: "lab.city", defaultValue: "Mock City")
        next.country = String(localized: "lab.country", defaultValue: "Weather Lab")
        if let condition { next.condition = condition }
        if let hour { next.hour = hour }
        if let temperature { next.temperature = temperature }
        if let humidity { next.humidity = humidity }
        if let pressure { next.pressure = pressure }
        if let windSpeed { next.windSpeed = windSpeed }
        if let rainProbability { next.rainProbability = rainProbability }
        next.feelsLike = Self.feelsLike(temperature: next.temperature, humidity: next.humidity, windSpeed: next.windSpeed)
        // Seed once if nothing has ever been loaded, so dragging a slider before
        // touching a preset/biome still gives the Minutecast card data to render.
        // Guarded by isEmpty so repeated slider drags don't recompute every frame.
        if hourly.isEmpty { hourly = Self.syntheticHourly(from: next) }
        if daily.isEmpty { daily = Self.syntheticDaily(from: next) }
        publish(next)
    }

    func applyPreset(
        _ condition: WeatherCondition,
        temp: Double,
        humidity: Double,
        pressure: Double,
        wind: Double,
        rain: Double,
        hour: Double
    ) {
        isSimulating = true
        forcedHealthInsights = nil
        phase = .loaded
        let next = WeatherData(
            city: String(localized: "lab.city", defaultValue: "Mock City"),
            country: String(localized: "lab.country", defaultValue: "Weather Lab"),
            temperature: temp,
            feelsLike: Self.feelsLike(temperature: temp, humidity: humidity, windSpeed: wind),
            condition: condition,
            humidity: humidity,
            pressure: pressure,
            windSpeed: wind,
            windDirection: 0,
            windGustSpeed: 0,
            uvIndex: 0,
            dewPoint: 0,
            visibility: 10,
            rainProbability: rain,
            hour: hour
        )
        // Seed hourly/daily like applyBiome does — without this, HomeView's
        // Minutecast card (which requires >= 2 hourly points) stays empty for
        // every Quick Scenario preset.
        hourly = Self.syntheticHourly(from: next)
        daily = Self.syntheticDaily(from: next)
        publish(next)
    }

    // MARK: - Sandbox: biome quick-travel

    /// Overwrites the snapshot *and* the hourly/daily series with an extreme
    /// environmental preset, so the home tab's health card and charts reflect
    /// the biome (e.g. Death Valley triggers a heatwave; Antarctica triggers
    /// the cold-stress path organically).
    func applyBiome(
        condition: WeatherCondition,
        temperature: Double,
        humidity: Double,
        pressure: Double,
        windSpeed: Double,
        windGust: Double,
        uvIndex: Int,
        visibility: Double,
        rainProbability: Double,
        hour: Double
    ) {
        isSimulating = true
        forcedHealthInsights = nil
        phase = .loaded

        let snapshot = WeatherData(
            city: String(localized: "lab.city", defaultValue: "Mock City"),
            country: String(localized: "lab.country", defaultValue: "Weather Lab"),
            temperature: temperature,
            feelsLike: Self.feelsLike(temperature: temperature, humidity: humidity, windSpeed: windSpeed),
            condition: condition,
            humidity: humidity,
            pressure: pressure,
            windSpeed: windSpeed,
            windDirection: 0,
            windGustSpeed: windGust,
            uvIndex: uvIndex,
            dewPoint: Self.dewPoint(temperature: temperature, humidity: humidity),
            visibility: visibility,
            rainProbability: rainProbability,
            hour: hour
        )
        hourly = Self.syntheticHourly(from: snapshot)
        daily = Self.syntheticDaily(from: snapshot)
        publish(snapshot)
    }

    // MARK: - Sandbox: medical stress tests

    /// Pins the health card to a hand-built medical state for UI testing.
    func forceHealthState(_ insights: HealthInsights) {
        isSimulating = true
        phase = .loaded
        forcedHealthInsights = insights
    }

    /// Clears a forced medical state, returning to computed insights.
    func clearForcedHealthState() {
        forcedHealthInsights = nil
    }

    /// Drops all sandbox overrides and reloads the last real location.
    func resumeLiveData() {
        forcedHealthInsights = nil
        moonPhaseOverride = nil
        Task { await retry() }
    }

    // MARK: - Lifecycle

    func pauseSensors() {
        stormTask?.cancel()
        Task { await stormSensor.stopMonitoring() }
    }

    func resumeSensors() {
        startStormMonitoring()
    }

    // MARK: - Storm monitoring

    private func startStormMonitoring() {
        stormTask?.cancel()
        stormTask = Task { [weak self] in
            // Each call to startMonitoring() restarts the sensor and returns a
            // fresh stream; the previous stream is automatically finished.
            guard let self else { return }
            for await alert in await self.stormSensor.startMonitoring() {
                self.stormAlert = alert
                // Auto-clear after 30 minutes so a resolved storm doesn't
                // keep the UI in alarm state indefinitely.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1800 * 1_000_000_000)
                    guard let self else { return }
                    if self.stormAlert?.triggeredAt == alert.triggeredAt {
                        self.stormAlert = nil
                    }
                }
            }
        }
    }

    // MARK: - Lab: Storm banner preview

    /// Injects a synthetic `StormAlert` and marks the snapshot as GPS-sourced
    /// so the storm banner can be visually verified in the Weather Lab without
    /// waiting for a real barometric pressure drop — `StormSensorEngine` only
    /// fires from genuine CoreMotion readings, which Simulator never produces
    /// and a real device may not see for hours.
    func triggerStormAlertPreview(_ severity: StormSeverity = .warning) {
        isGPSLocation = true
        let (drop, windowMinutes): (Double, Int) = {
            switch severity {
            case .watch:   return (3.4, 180)
            case .warning: return (5.6, 120)
            case .extreme: return (8.5, 90)
            }
        }()
        stormAlert = StormAlert(
            severity: severity,
            pressureDropHPa: drop,
            windowMinutes: windowMinutes,
            triggeredAt: Date()
        )
    }

    /// Clears a previewed/real storm alert immediately, without waiting for
    /// the 30-minute auto-clear.
    func clearStormAlert() {
        stormAlert = nil
    }

    // MARK: - Internals

    private func publish(_ next: WeatherData) {
        weather = next
        var nextAtmosphere = AtmosphericEngine.calculate(from: next)
        nextAtmosphere.story = WeatherNarrativeEngine.story(
            weather: next,
            atmosphere: nextAtmosphere,
            hourly: hourly,
            daily: daily
        )
        atmosphere = nextAtmosphere
    }

    // MARK: - Sandbox synthesis helpers

    /// Apparent temperature: heat index when hot, wind chill when cold.
    private static func feelsLike(temperature: Double, humidity: Double, windSpeed: Double) -> Double {
        if temperature >= 27 {
            return ThermalPredictionEngine.heatIndex(temperatureC: temperature, humidity: humidity)
        }
        if temperature <= 10 {
            return ThermalPredictionEngine.windChillIndex(temperatureC: temperature, windSpeedKmh: windSpeed)
        }
        return temperature
    }

    /// Magnus-formula dew point (°C) from temperature and relative humidity.
    private static func dewPoint(temperature: Double, humidity: Double) -> Double {
        let h = max(1, min(100, humidity)) / 100
        let a = 17.27, b = 237.7
        let gamma = (a * temperature) / (b + temperature) + log(h)
        return (b * gamma) / (a - gamma)
    }

    /// 24 hourly points around the snapshot with a mild diurnal wobble so the
    /// charts and best-hours logic have texture; UV is zeroed overnight.
    private static func syntheticHourly(from w: WeatherData) -> [HourlyPoint] {
        let calendar = Calendar.current
        let now = Date()
        let startHour = Int(w.hour.rounded())
        return (0..<24).map { offset in
            let hour: Int = (startHour + offset) % 24
            let date: Date = calendar.date(byAdding: .hour, value: offset, to: now) ?? now
            let hourDouble: Double = Double(hour)
            let diurnal: Double = sin(hourDouble / 24.0 * 2 * .pi - .pi / 2)
            let daylight: Double = max(0, sin((hourDouble - 6) / 12.0 * .pi))
            let uvValue: Double = Double(w.uvIndex) * daylight
            let uv: Int = max(0, Int(uvValue.rounded()))
            let temp: Double = w.temperature + diurnal * 2.5
            return HourlyPoint(
                date: date,
                hour: hour,
                temperature: temp,
                precipitationProbability: w.rainProbability,
                condition: w.condition,
                uvIndex: uv,
                windSpeed: w.windSpeed,
                windDirection: w.windDirection,
                windGustSpeed: w.windGustSpeed,
                humidity: w.humidity,
                dewPoint: w.dewPoint,
                visibility: w.visibility
            )
        }
    }

    /// 7 daily ranges holding the snapshot's extreme, so multi-day detectors
    /// (e.g. the heatwave alert) fire for the chosen biome.
    private static func syntheticDaily(from w: WeatherData) -> [DailyRange] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return DailyRange(
                date: date,
                min: w.temperature - 8,
                max: w.temperature,
                feelsLikeMin: w.temperature - 8,
                feelsLikeMax: w.feelsLike,
                uvIndexMax: w.uvIndex,
                windSpeedMax: w.windSpeed,
                windDirection: w.windDirection,
                windGustMax: w.windGustSpeed,
                precipitationAmount: w.rainProbability > 50 ? 12 : 0,
                condition: w.condition,
                sunrise: nil,
                sunset: nil
            )
        }
    }

    private static func message(for error: Error) -> String {
        if let clientError = error as? WeatherClientError {
            switch clientError {
            case .badURL:
                return String(localized: "error.badURL", defaultValue: "Invalid request address.")
            case .badResponse(let code):
                return String(localized: "error.badResponse", defaultValue: "Server error (\(code)).")
            case .noResults:
                return String(localized: "error.noResults", defaultValue: "No results found.")
            case .transport(let detail):
                return String(format: String(localized: "error.transport", defaultValue: "Connection problem: %@"), detail)
            }
        }
        return error.localizedDescription
    }

    // MARK: - Persistence

    private static func persist(_ place: SavedLocation) {
        if let data = try? JSONEncoder().encode(place) {
            UserDefaults.standard.set(data, forKey: locationKey)
        }
    }

    private static func loadSavedLocation() -> SavedLocation? {
        guard let data = UserDefaults.standard.data(forKey: locationKey) else { return nil }
        return try? JSONDecoder().decode(SavedLocation.self, from: data)
    }
}
