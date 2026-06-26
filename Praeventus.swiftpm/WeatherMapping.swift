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
        lhs.windGustSpeed == rhs.windGustSpeed
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
        lhs.uvIndexMax == rhs.uvIndexMax && lhs.windSpeedMax == rhs.windSpeedMax
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
    /// https://open-meteo.com/en/docs (WMO Weather interpretation codes)
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

    /// Maps an Open-Meteo response + a chosen place name into the app model.
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
            windDirection: current.windDirection10m ?? 0,
            windGustSpeed: current.windGusts10m ?? 0,
            uvIndex: current.uvIndex ?? 0,
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
        let endIndex = min(hourly.time.count, startIndex + OpenMeteoClient.hourlyWindow)
        guard startIndex < endIndex else { return [] }

        return (startIndex..<endIndex).compactMap { i in
            guard let date = date(fromISO: hourly.time[i]) else { return nil }
            let temp = temps.indices.contains(i) ? (temps[i] ?? 0) : 0
            let prob = probs.indices.contains(i) ? (probs[i] ?? 0) : 0
            let code = codes.indices.contains(i) ? codes[i] : nil
            let uv = uvs.indices.contains(i) ? (uvs[i] ?? 0) : 0
            let wind = windSpeeds.indices.contains(i) ? (windSpeeds[i] ?? 0) : 0
            let windDir = windDirs.indices.contains(i) ? (windDirs[i] ?? 0) : 0
            let gust = windGusts.indices.contains(i) ? (windGusts[i] ?? 0) : 0
            let humidity = humidities.indices.contains(i) ? Double(humidities[i] ?? 0) : 0
            let dew = dewPoints.indices.contains(i) ? (dewPoints[i] ?? 0) : 0
            let vis = visibilities.indices.contains(i) ? (visibilities[i] ?? 10) : 10

            return HourlyPoint(
                date: date,
                hour: hour(fromISO: hourly.time[i]) ?? 0,
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
            let lo = mins.indices.contains(i) ? (mins[i] ?? 0) : 0
            let hi = maxes.indices.contains(i) ? (maxes[i] ?? 0) : 0
            let feelsLoMin = feelsLikeMins.indices.contains(i) ? (feelsLikeMins[i] ?? lo) : lo
            let feelsLoMax = feelsLikeMaxes.indices.contains(i) ? (feelsLikeMaxes[i] ?? hi) : hi
            let uv = uvMaxes.indices.contains(i) ? (uvMaxes[i] ?? 0) : 0
            let windMax = windMaxes.indices.contains(i) ? (windMaxes[i] ?? 0) : 0
            let windDir = windDirs.indices.contains(i) ? (windDirs[i] ?? 0) : 0
            let gustMax = windGustMaxes.indices.contains(i) ? (windGustMaxes[i] ?? 0) : 0
            let precip = precips.indices.contains(i) ? (precips[i] ?? 0) : 0
            let code = codes.indices.contains(i) ? codes[i] : nil
            let sunriseTime = sunrises.indices.contains(i) ? date(fromISO: sunrises[i] ?? "") : nil
            let sunsetTime = sunsets.indices.contains(i) ? date(fromISO: sunsets[i] ?? "") : nil

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
        // Open-Meteo returns local wall-clock without a zone offset; parse as-is.
        let formatter = isoFormatter
        if let d = formatter.date(from: iso) { return d }
        // Daily entries are date-only ("yyyy-MM-dd").
        let dayFormatter = dayFormatter
        return dayFormatter.date(from: iso)
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
