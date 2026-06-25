import Foundation

// MARK: - Forecast

/// Decoded shape of an Open-Meteo `/v1/forecast` response.
///
/// Only the fields the app requests are modelled. Open-Meteo returns parallel
/// arrays under `hourly` / `daily` (a `time` array plus one array per variable),
/// which `WeatherMapping` zips into point structs.
struct ForecastResponse: Decodable, Equatable {
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let elevation: Double?
    let current: Current
    let hourly: Hourly?
    let daily: Daily?

    struct Current: Decodable, Equatable {
        let time: String?
        let temperature2m: Double?
        let apparentTemperature: Double?
        let relativeHumidity2m: Double?
        let surfacePressure: Double?
        let pressureMsl: Double?
        let windSpeed10m: Double?
        let precipitationProbability: Double?
        let weatherCode: Int?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case surfacePressure = "surface_pressure"
            case pressureMsl = "pressure_msl"
            case windSpeed10m = "wind_speed_10m"
            case precipitationProbability = "precipitation_probability"
            case weatherCode = "weather_code"
        }
    }

    struct Hourly: Decodable, Equatable {
        let time: [String]
        let temperature2m: [Double?]?
        let precipitationProbability: [Double?]?
        let weatherCode: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case weatherCode = "weather_code"
        }
    }

    struct Daily: Decodable, Equatable {
        let time: [String]
        let temperature2mMax: [Double?]?
        let temperature2mMin: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, elevation, current, hourly, daily
    }
}

// MARK: - Geocoding (city search)

struct GeocodingResponse: Decodable, Equatable {
    let results: [GeocodingResult]?
}

struct GeocodingResult: Decodable, Equatable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let countryCode: String?
    let admin1: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, country, admin1, timezone
        case countryCode = "country_code"
    }

    /// "Adana, Türkiye" style subtitle for search rows.
    var subtitle: String {
        [admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}
