import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking // Linux: URLSession async lives here
#endif

/// Networking layer that fetches pre-blended forecast data from the backend
/// (Deno Deploy) in one round-trip instead of querying each NWP model source
/// separately. The backend returns the genuine NWP model responses (ECMWF/GFS
/// via MET Norway, ICON via Bright Sky) inside a single JSON envelope, which
/// maps directly into the shape `WeatherFusion` already expects.
///
/// The search path proxies Nominatim geocoding through the same backend so the
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

    /// Fetches the two genuine NWP model forecasts plus the nearest-airport METAR
    /// from the Worker in one request and returns a `ForecastBundle`.
    ///
    /// Worker JSON shape:
    /// ```json
    /// {
    ///   "models": {
    ///     "ecmwf_ifs025": <ForecastResponse>,
    ///     "icon_global":  <ForecastResponse>
    ///   },
    ///   "metar_station": "LTAC",
    ///   "metar_raw": { ... },
    ///   "utc_offset_seconds": 10800,
    ///   "generated_at": "2026-06-29T..."
    /// }
    /// ```
    func forecast(latitude: Double, longitude: Double) async throws -> ForecastBundle {
        let url = try buildURL(path: "/forecast", queryItems: [
            URLQueryItem(name: "lat", value: trimmed(latitude)),
            URLQueryItem(name: "lon", value: trimmed(longitude))
        ])

        let envelope = try await get(url, as: WorkerEnvelope.self)

        var models: [WeatherModel: ForecastResponse] = [:]
        if let r = envelope.models["ecmwf_ifs025"] { models[.ecmwf] = r }
        if let r = envelope.models["icon_global"]  { models[.icon]  = r }

        if models.isEmpty { throw WeatherClientError.noResults }

        return ForecastBundle(
            models: models,
            metarStation: envelope.metar_station,
            metarRaw: envelope.metar_raw,
            utcOffsetSeconds: envelope.utc_offset_seconds
        )
    }

    // MARK: - Nowcast

    /// Fetches radar-based minute-precipitation data from the Worker's `/nowcast`
    /// endpoint. Returns `nil` when the device coordinate is outside MET Norway's
    /// radar coverage area (e.g. outside Scandinavia and surrounding regions).
    func nowcast(latitude: Double, longitude: Double) async -> NowcastResponse? {
        guard let url = try? buildURL(path: "/nowcast", queryItems: [
            URLQueryItem(name: "lat", value: trimmed(latitude)),
            URLQueryItem(name: "lon", value: trimmed(longitude))
        ]) else { return nil }
        return try? await get(url, as: NowcastResponse.self)
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
        lang: String,
        agreementPercent: Int? = nil,
        anomalyDetected: Bool? = nil,
        anomalySource: String? = nil,
        metarAgeMinutes: Int? = nil
    ) async -> String {
        var queryItems: [URLQueryItem] = [
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
        // Anonymous confidence signals only — never any identity or location.
        if let agreementPercent {
            queryItems.append(URLQueryItem(name: "agreement", value: String(agreementPercent)))
        }
        if let anomalyDetected {
            queryItems.append(URLQueryItem(name: "anomaly_detected", value: anomalyDetected ? "1" : "0"))
        }
        if let anomalySource, !anomalySource.isEmpty {
            queryItems.append(URLQueryItem(name: "anomaly_source", value: anomalySource))
        }
        if let metarAgeMinutes {
            queryItems.append(URLQueryItem(name: "metar_age_minutes", value: String(metarAgeMinutes)))
        }
        guard let url = try? buildURL(path: "/narrative", queryItems: queryItems) else { return "" }
        guard let result = try? await get(url, as: NarrativeResponse.self) else { return "" }
        return result.narrative
    }

    // MARK: - Alerts

    /// Fetches the combined NWS + MeteoAlarm + GDACS coordinate-bearing alert
    /// feed from the Worker's `/alerts` endpoint. This payload is a single
    /// global cache entry on the backend (not keyed by coordinate), so every
    /// client shares one cached fetch regardless of how many devices call it.
    func alerts() async throws -> [WeatherAlert] {
        let url = try buildURL(path: "/alerts", queryItems: [])
        return try await get(url, as: WeatherAlertsResponse.self).alerts
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
        request.timeoutInterval = 25

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
            throw WeatherClientError.decodingFailed(
                type: String(describing: T.self),
                detail: error.localizedDescription
            )
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

/// All data returned by a single `/forecast` call.
struct ForecastBundle {
    let models: [WeatherModel: ForecastResponse]
    let metarStation: String?
    let metarRaw: MetarRaw?
    /// DST-aware UTC offset (seconds) for the location's real IANA timezone,
    /// computed server-side. Used instead of a longitude-only approximation
    /// so the header clock and Astronomik card agree with the actual local time.
    let utcOffsetSeconds: Int?
}

private struct NarrativeResponse: Decodable {
    let narrative: String
}

/// A single coordinate-bearing official alert normalized by the backend from
/// NWS, MeteoAlarm or GDACS. `area` doubles as the display name for the
/// location a tap should load (backend's normalized schema has no separate
/// "city" field — `area` already carries the region/city description).
struct WeatherAlert: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    /// "extreme" | "severe" | "moderate" | "minor" | "unknown"
    let severity: String
    let area: String
    let country: String?
    let latitude: Double
    let longitude: Double
    /// "NWS" | "MeteoAlarm" | "GDACS"
    let source: String
    let onset: String?
    let expires: String?
}

private struct WeatherAlertsResponse: Decodable {
    let alerts: [WeatherAlert]
}

private struct WorkerEnvelope: Decodable {
    let models: [String: ForecastResponse]
    let metar_station: String?
    let metar_raw: MetarRaw?
    let utc_offset_seconds: Int?
    let generated_at: String?
}

// MARK: - Client errors

enum WeatherClientError: Error {
    case badURL
    case badResponse(Int)
    case noResults
    case transport(String)
    case decodingFailed(type: String, detail: String)
}

