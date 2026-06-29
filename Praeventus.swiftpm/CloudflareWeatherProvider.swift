import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking // Linux: URLSession async lives here
#endif

/// Networking layer that fetches pre-blended forecast data from the Cloudflare
/// Worker endpoint in one round-trip instead of querying Open-Meteo's three
/// model URLs separately. The Worker returns all NWP model responses inside a
/// single JSON envelope, which maps directly into the shape `WeatherFusion`
/// already expects — no changes needed there.
///
/// The search path proxies Open-Meteo Geocoding through the same Worker so the
/// device IP is never exposed to the upstream service.
struct CloudflareWeatherProvider {

    let baseURL: String

    private static let sharedDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return d
    }()

    // MARK: - Forecast

    /// Fetches all three NWP model forecasts from the Worker in one request and
    /// returns them keyed by `WeatherModel` — the same shape `WeatherFusion` expects.
    ///
    /// Worker JSON shape:
    /// ```json
    /// {
    ///   "models": {
    ///     "ecmwf_ifs025": <ForecastResponse>,
    ///     "gfs_global":   <ForecastResponse>,
    ///     "icon_global":  <ForecastResponse>
    ///   },
    ///   "metar_station": "LTAC",
    ///   "generated_at": "2026-06-29T..."
    /// }
    /// ```
    func forecast(latitude: Double, longitude: Double) async throws -> [WeatherModel: ForecastResponse] {
        let url = try buildURL(path: "/forecast", queryItems: [
            URLQueryItem(name: "lat", value: trimmed(latitude)),
            URLQueryItem(name: "lon", value: trimmed(longitude))
        ])

        let envelope = try await get(url, as: WorkerEnvelope.self)

        var result: [WeatherModel: ForecastResponse] = [:]
        if let r = envelope.models["ecmwf_ifs025"] { result[.ecmwf] = r }
        if let r = envelope.models["gfs_global"]   { result[.gfs]   = r }
        if let r = envelope.models["icon_global"]  { result[.icon]  = r }

        if result.isEmpty { throw WeatherClientError.noResults }
        return result
    }

    // MARK: - Narrative

    /// Fetches a short AI-generated weather commentary from the Worker's `/narrative`
    /// endpoint. No coordinates are ever sent — only anonymous weather values.
    /// Returns an empty string on any error so the UI can hide the card gracefully.
    func narrative(
        temp: Double,
        feelsLike: Double,
        humidity: Double,
        windSpeed: Double,
        windDir: Double,
        weatherCode: Int,
        tempMax: Double,
        tempMin: Double,
        precipProb: Double,
        uvIndex: Double,
        visibility: Double,
        pressure: Double,
        lang: String
    ) async -> String {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "lang",         value: lang),
            URLQueryItem(name: "temp",         value: String(format: "%.0f", temp)),
            URLQueryItem(name: "feels",        value: String(format: "%.0f", feelsLike)),
            URLQueryItem(name: "humidity",     value: String(format: "%.0f", humidity)),
            URLQueryItem(name: "wind",         value: String(format: "%.0f", windSpeed)),
            URLQueryItem(name: "wind_dir",     value: String(format: "%.0f", windDir)),
            URLQueryItem(name: "weather_code", value: String(weatherCode)),
            URLQueryItem(name: "temp_max",     value: String(format: "%.0f", tempMax)),
            URLQueryItem(name: "temp_min",     value: String(format: "%.0f", tempMin)),
            URLQueryItem(name: "precip_prob",  value: String(format: "%.0f", precipProb)),
            URLQueryItem(name: "uv",           value: String(format: "%.0f", uvIndex)),
            URLQueryItem(name: "visibility",   value: String(format: "%.1f", visibility / 1000)),
            URLQueryItem(name: "pressure",     value: String(format: "%.0f", pressure)),
        ]
        guard let url = try? buildURL(path: "/narrative", queryItems: queryItems) else { return "" }
        guard let result = try? await get(url, as: NarrativeResponse.self) else { return "" }
        return result.narrative
    }

    // MARK: - Search

    /// Forwards a geocoding query to the Worker's `/search` endpoint.
    func search(_ query: String, count: Int = 10) async throws -> [GeocodingResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let url = try buildURL(path: "/search", queryItems: [
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "lang", value: Locale.current.language.languageCode?.identifier ?? "en")
        ])

        let response = try await get(url, as: GeocodingResponse.self)
        return response.results ?? []
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Praeventus/1.0 (privacy-weather)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
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

    private func buildURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw WeatherClientError.badURL
        }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = basePath + path
        components.queryItems = queryItems
        guard let url = components.url else {
            throw WeatherClientError.badURL
        }
        return url
    }

    private func trimmed(_ value: Double) -> String {
        // 4 decimals ≈ 11 m precision — coarse on purpose; we never need more.
        String(format: "%.4f", value)
    }
}

// MARK: - Worker response types

private struct NarrativeResponse: Decodable {
    let narrative: String
}

private struct WorkerEnvelope: Decodable {
    let models: [String: ForecastResponse]
    let metar_station: String?
    let generated_at: String?
}

// MARK: - Client errors

enum WeatherClientError: Error {
    case badURL
    case badResponse(Int)
    case noResults
    case transport(String)
}

