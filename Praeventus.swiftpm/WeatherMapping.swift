import Foundation

/// A single hourly sample for the charts / hourly strip.
struct HourlyPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let hour: Int            // 0...23 local
    let temperature: Double
    let precipitationProbability: Double
    let condition: WeatherCondition
    let uvIndex: Int
    let windSpeed: Double
    let windDirection: Int
    let windGustSpeed: Double
    let humidity: Double
    let dewPoint: Double
    let visibility: Double

    static func == (lhs: HourlyPoint, rhs: HourlyPoint) -> Bool {
        lhs.date == rhs.date &&
        lhs.temperature == rhs.temperature &&
        lhs.precipitationProbability == rhs.precipitationProbability &&
        lhs.condition == rhs.condition &&
        lhs.uvIndex == rhs.uvIndex &&
        lhs.windSpeed == rhs.windSpeed &&
        lhs.windDirection == rhs.windDirection &&
        lhs.windGustSpeed == rhs.windGustSpeed &&
        lhs.humidity == rhs.humidity &&
        lhs.dewPoint == rhs.dewPoint &&
        lhs.visibility == rhs.visibility
    }
}

/// A daily min/max band — the honest "spread/uncertainty" range for the charts.
struct DailyRange: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let min: Double
    let max: Double
    let feelsLikeMin: Double
    let feelsLikeMax: Double
    let uvIndexMax: Int
    let windSpeedMax: Double
    let windDirection: Int
    let windGustMax: Double
    let precipitationAmount: Double
    let condition: WeatherCondition
    let sunrise: Date?
    let sunset: Date?

    var mean: Double { (min + max) / 2 }

    static func == (lhs: DailyRange, rhs: DailyRange) -> Bool {
        lhs.date == rhs.date && lhs.min == rhs.min && lhs.max == rhs.max &&
        lhs.feelsLikeMin == rhs.feelsLikeMin && lhs.feelsLikeMax == rhs.feelsLikeMax &&
        lhs.uvIndexMax == rhs.uvIndexMax && lhs.windSpeedMax == rhs.windSpeedMax &&
        lhs.windGustMax == rhs.windGustMax && lhs.precipitationAmount == rhs.precipitationAmount &&
        lhs.condition == rhs.condition && lhs.sunrise == rhs.sunrise && lhs.sunset == rhs.sunset
    }
}

/// Fully mapped result of a forecast fetch: the headline snapshot plus the
/// series needed by the charts.
struct MappedForecast: Equatable {
    var weather: WeatherData
    var hourly: [HourlyPoint]
    var daily: [DailyRange]
}

enum WeatherMapping {

    /// WMO weather interpretation code → app `WeatherCondition`.
    static func condition(forWMOCode code: Int?) -> WeatherCondition {
        guard let code else { return .partlyCloudy }
        switch code {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51...67: return .rain      // drizzle + rain + freezing rain
        case 80...82: return .rain      // rain showers
        case 71...77: return .snow      // snow fall + grains
        case 85, 86: return .snow       // snow showers
        case 95...99: return .storm     // thunderstorm
        default: return .partlyCloudy
        }
    }

    /// Maps a forecast response + a chosen place name into the app model.
    static func map(_ response: ForecastResponse, city: String, country: String) -> MappedForecast {
        let current = response.current

        let pressure = current.surfacePressure ?? current.pressureMsl ?? 1013
        let temperature = current.temperature2m ?? 0
        let humidity = current.relativeHumidity2m ?? 0
        let condition = condition(forWMOCode: current.weatherCode)
        let hour = Double(hour(fromISO: current.time) ?? Calendar.current.component(.hour, from: Date()))

        let weather = WeatherData(
            city: city,
            country: country,
            temperature: temperature,
            feelsLike: current.apparentTemperature ?? temperature,
            condition: condition,
            humidity: humidity,
            pressure: pressure,
            windSpeed: current.windSpeed10m ?? 0,
            windDirection: Int((current.windDirection10m ?? 0).rounded()),
            windGustSpeed: current.windGusts10m ?? 0,
            uvIndex: Int((current.uvIndex ?? 0).rounded()),
            dewPoint: current.dewPoint2m ?? 0,
            visibility: current.visibility ?? 10,
            rainProbability: current.precipitationProbability ?? 0,
            hour: hour
        )

        return MappedForecast(
            weather: weather,
            hourly: hourlyPoints(from: response.hourly, currentTime: current.time),
            daily: dailyRanges(from: response.daily)
        )
    }

    // MARK: - Series

    private static func hourlyPoints(from hourly: ForecastResponse.Hourly?, currentTime: String?) -> [HourlyPoint] {
        guard let hourly else { return [] }
        let temps = hourly.temperature2m ?? []
        let probs = hourly.precipitationProbability ?? []
        let codes = hourly.weatherCode ?? []
        let uvs = hourly.uvIndex ?? []
        let windSpeeds = hourly.windSpeed10m ?? []
        let windDirs = hourly.windDirection10m ?? []
        let windGusts = hourly.windGusts10m ?? []
        let humidities = hourly.relativeHumidity2m ?? []
        let dewPoints = hourly.dewPoint2m ?? []
        let visibilities = hourly.visibility ?? []

        // Start from the hour closest to "now" so the strip reads forward.
        let startIndex = nowIndex(in: hourly.time, currentTime: currentTime)
        let endIndex = min(hourly.time.count, startIndex + 24)
        guard startIndex < endIndex else { return [] }

        return (startIndex..<endIndex).compactMap { i in
            guard let date = date(fromISO: hourly.time[i]) else { return nil }
            let temp = safe(temps, at: i, or: 0.0)
            let prob = safe(probs, at: i, or: 0.0)
            let code: Int? = i < codes.count ? codes[i] : nil
            let uv = safe(uvs, at: i, or: 0.0)
            let wind = safe(windSpeeds, at: i, or: 0.0)
            let windDir: Int = Int(safe(windDirs, at: i, or: 0.0).rounded())
            let gust = safe(windGusts, at: i, or: 0.0)
            let humidity = safe(humidities, at: i, or: 0.0)
            let dew = safe(dewPoints, at: i, or: 0.0)
            let vis = safe(visibilities, at: i, or: 10.0)

            return HourlyPoint(
                date: date,
                hour: Calendar.current.component(.hour, from: date),
                temperature: temp,
                precipitationProbability: prob,
                condition: condition(forWMOCode: code),
                uvIndex: Int(uv),
                windSpeed: wind,
                windDirection: windDir,
                windGustSpeed: gust,
                humidity: humidity,
                dewPoint: dew,
                visibility: vis
            )
        }
    }

    private static func dailyRanges(from daily: ForecastResponse.Daily?) -> [DailyRange] {
        guard let daily else { return [] }
        let maxes = daily.temperature2mMax ?? []
        let mins = daily.temperature2mMin ?? []
        let feelsLikeMaxes = daily.apparentTemperatureMax ?? []
        let feelsLikeMins = daily.apparentTemperatureMin ?? []
        let uvMaxes = daily.uvIndexMax ?? []
        let windMaxes = daily.windSpeed10mMax ?? []
        let windDirs = daily.windDirection10mDominant ?? []
        let windGustMaxes = daily.windGusts10mMax ?? []
        let precips = daily.precipitationSum ?? []
        let codes = daily.weatherCode ?? []
        let sunrises = daily.sunrise ?? []
        let sunsets = daily.sunset ?? []

        return daily.time.indices.compactMap { i in
            guard let date = date(fromISO: daily.time[i]) else { return nil }
            let lo = safe(mins, at: i, or: 0.0)
            let hi = safe(maxes, at: i, or: 0.0)
            let feelsLoMin = safe(feelsLikeMins, at: i, or: lo)
            let feelsLoMax = safe(feelsLikeMaxes, at: i, or: hi)
            let uv = safe(uvMaxes, at: i, or: 0.0)
            let windMax = safe(windMaxes, at: i, or: 0.0)
            let windDir: Int = Int(safe(windDirs, at: i, or: 0.0).rounded())
            let gustMax = safe(windGustMaxes, at: i, or: 0.0)
            let precip = safe(precips, at: i, or: 0.0)
            let code: Int? = i < codes.count ? codes[i] : nil
            let sunriseTime = i < sunrises.count ? sunrises[i].flatMap(Self.date(fromISO:)) : nil
            let sunsetTime = i < sunsets.count ? sunsets[i].flatMap(Self.date(fromISO:)) : nil

            return DailyRange(
                date: date,
                min: lo,
                max: hi,
                feelsLikeMin: feelsLoMin,
                feelsLikeMax: feelsLoMax,
                uvIndexMax: Int(uv),
                windSpeedMax: windMax,
                windDirection: windDir,
                windGustMax: gustMax,
                precipitationAmount: precip,
                condition: condition(forWMOCode: code),
                sunrise: sunriseTime,
                sunset: sunsetTime
            )
        }
    }

    // MARK: - Time parsing

    /// Index of the entry matching `currentTime`, else the first future entry, else 0.
    private static func nowIndex(in times: [String], currentTime: String?) -> Int {
        if let currentTime, let exact = times.firstIndex(of: currentTime) {
            return exact
        }
        // Open-Meteo current.time is rounded to the hour, so prefix-match too.
        if let currentTime {
            let hourKey = String(currentTime.prefix(13)) // yyyy-MM-ddTHH
            if let idx = times.firstIndex(where: { $0.hasPrefix(hourKey) }) {
                return idx
            }
        }
        let now = Date()
        if let idx = times.firstIndex(where: { (date(fromISO: $0) ?? .distantPast) >= now }) {
            return idx
        }
        return 0
    }

    private static func hour(fromISO iso: String?) -> Int? {
        guard let iso, iso.count >= 13 else { return nil }
        // "yyyy-MM-ddTHH:mm" → characters 11..12 are HH
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(start, offsetBy: 2)
        return Int(iso[start..<end])
    }

    private static func date(fromISO iso: String) -> Date? {
        // 1. Open-Meteo: "yyyy-MM-dd'T'HH:mm" (no seconds, no timezone)
        if let d = isoFormatter.date(from: iso) { return d }
        // 2. MET Norway: "2026-06-30T12:00:00Z"
        //    BrightSky:  "2026-06-30T14:00:00+02:00"
        if let d = iso8601Formatter.date(from: iso) { return d }
        // 3. Backend astro.ts sunrise/sunset: JS `Date.toISOString()` always
        //    emits milliseconds ("2026-06-30T05:12:34.000Z"), which
        //    `iso8601Formatter` above (.withInternetDateTime only) cannot
        //    parse — ISO8601DateFormatter's format options are an exact
        //    match, not a flexible parse. Without this, daily.sunrise/sunset
        //    silently decoded to nil on every forecast.
        if let d = iso8601FractionalFormatter.date(from: iso) { return d }
        // 4. Daily date-only: "yyyy-MM-dd"
        return dayFormatter.date(from: iso)
    }

    // MARK: - Array helpers

    /// Bounds-safe access for nullable arrays returned by Open-Meteo.
    private static func safe<T>(_ array: [T?], at index: Int, or fallback: T) -> T {
        index < array.count ? (array[index] ?? fallback) : fallback
    }

    // These four formatters are only ever read from inside
    // `date(fromISO:)`/`hour(fromISO:)`, which `WeatherStore` calls via its
    // `nonisolated mapForecast` — a single in-flight forecast load at a time
    // (`WeatherStore.isLoadInFlight` serializes it). Neither `DateFormatter`
    // nor `ISO8601DateFormatter` is `Sendable`, so `nonisolated(unsafe)`
    // documents that this invariant — not the compiler — guarantees safety.
    private nonisolated(unsafe) static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    // Handles full ISO 8601 with explicit timezone: "2026-06-30T12:00:00Z"
    // and "2026-06-30T14:00:00+02:00" (MET Norway / BrightSky formats).
    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // Handles the backend's astro.ts sunrise/sunset strings, which always
    // carry milliseconds via JS `toISOString()` ("...T05:12:34.000Z").
    private nonisolated(unsafe) static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
