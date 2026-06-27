import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking // Linux: URLSession async lives here
#endif

/// Errors surfaced by `OpenMeteoClient`. Messages are localized at the UI layer.
enum WeatherClientError: Error, Equatable {
    case badURL
    case badResponse(Int)
    case noResults
    case transport(String)
}

/// Pure-Foundation networking against Open-Meteo (optionally via the Cloudflare
/// Worker proxy). No API key, no account, no third-party SDK — and no UI
/// dependency, so it compiles and runs on Linux for verification.
struct OpenMeteoClient {

    private let session: URLSession

    private static let sharedDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return d
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Hourly steps to keep for the charts (next ~24h from "now").
    static let hourlyWindow = 24

    func forecast(latitude: Double, longitude: Double, model: WeatherModel = .bestMatch) async throws -> ForecastResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: trimmed(latitude)),
            URLQueryItem(name: "longitude", value: trimmed(longitude)),
            URLQueryItem(name: "current", value: [
                "temperature_2m", "apparent_temperature", "relative_humidity_2m",
                "surface_pressure", "pressure_msl", "wind_speed_10m", "wind_direction_10m",
                "wind_gusts_10m", "uv_index", "dew_point_2m", "visibility",
                "precipitation_probability", "weather_code"
            ].joined(separator: ",")),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m", "precipitation_probability", "weather_code",
                "uv_index", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
                "relative_humidity_2m", "dew_point_2m", "visibility"
            ].joined(separator: ",")),
            URLQueryItem(name: "daily", value: [
                "temperature_2m_max", "temperature_2m_min", "apparent_temperature_max",
                "apparent_temperature_min", "uv_index_max", "wind_speed_10m_max",
                "wind_direction_10m_dominant", "wind_gusts_10m_max", "precipitation_sum",
                "weather_code", "sunrise", "sunset"
            ].joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh")
        ]

        // A single model id keeps the JSON keys un-suffixed, so the existing
        // decoder works as-is. Omit for the server's blended default.
        if model != .bestMatch {
            items.append(URLQueryItem(name: "models", value: model.apiValue))
        }

        guard let url = WeatherEndpoint.forecastURL(queryItems: items) else {
            throw WeatherClientError.badURL
        }
        return try await get(url, as: ForecastResponse.self)
    }

    /// Fetches several models concurrently for on-device fusion. Tolerates
    /// partial failure: a model that errors is dropped; only throws when every
    /// model fails (so the caller can fall back to cache or surface an error).
    func forecast(latitude: Double, longitude: Double, models: [WeatherModel]) async throws -> [WeatherModel: ForecastResponse] {
        guard !models.isEmpty else {
            return [.bestMatch: try await forecast(latitude: latitude, longitude: longitude)]
        }

        let results = await withTaskGroup(of: (WeatherModel, ForecastResponse?).self) { group in
            for model in models {
                group.addTask {
                    let response = try? await self.forecast(latitude: latitude, longitude: longitude, model: model)
                    return (model, response)
                }
            }
            var collected: [WeatherModel: ForecastResponse] = [:]
            for await (model, response) in group {
                if let response { collected[model] = response }
            }
            return collected
        }

        if results.isEmpty { throw WeatherClientError.noResults }
        return results
    }

    func search(_ query: String, count: Int = 10) async throws -> [GeocodingResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let items: [URLQueryItem] = [
            URLQueryItem(name: "name", value: trimmedQuery),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")
        ]

        guard let url = WeatherEndpoint.geocodingURL(queryItems: items) else {
            throw WeatherClientError.badURL
        }
        let response = try await get(url, as: GeocodingResponse.self)
        return response.results ?? []
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Generic UA; the proxy overwrites it anyway, but be polite when direct.
        request.setValue("Praeventus/1.0 (privacy-weather)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .useProtocolCachePolicy

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WeatherClientError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WeatherClientError.badResponse(http.statusCode)
        }

        do {
            return try Self.sharedDecoder.decode(T.self, from: data)
        } catch {
            throw WeatherClientError.transport("decode: \(error.localizedDescription)")
        }
    }

    private func trimmed(_ value: Double) -> String {
        // 4 decimals ≈ 11m precision — coarse on purpose; we never need more.
        String(format: "%.4f", value)
    }
}
