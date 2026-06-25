import Foundation

/// Central configuration for every network request the app makes.
///
/// Privacy model: the app never talks to Open-Meteo directly when a Cloudflare
/// Worker proxy is configured. Point `proxyBaseURL` at your deployed Worker
/// (see `worker/README.md`) and all traffic is routed through it so the upstream
/// only ever sees the Worker's IP, not the user's device.
///
/// When `proxyBaseURL` is `nil`, requests fall back to Open-Meteo directly. This
/// keeps the app fully functional out of the box; the proxy is an opt-in
/// hardening step, not a requirement.
enum WeatherEndpoint {

    /// Set this to your deployed Cloudflare Worker, e.g.
    /// `"https://praeventus.<your-subdomain>.workers.dev"`.
    /// Leave `nil` to call Open-Meteo directly.
    ///
    /// This is also surfaced/overridable at runtime via `UserDefaults`
    /// (`SettingsView`), so the value here is just the compiled-in default.
    static let defaultProxyBaseURL: String? = nil

    private static let directForecastHost = "api.open-meteo.com"
    private static let directGeocodingHost = "geocoding-api.open-meteo.com"

    private static let userDefaultsProxyKey = "praeventus.proxyBaseURL"

    /// The effective proxy base URL: a runtime override (Settings) wins over the
    /// compiled-in default. An empty string is treated as "no proxy".
    static var proxyBaseURL: String? {
        if let override = UserDefaults.standard.string(forKey: userDefaultsProxyKey),
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }
        return defaultProxyBaseURL
    }

    static func setProxyBaseURL(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsProxyKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsProxyKey)
        }
    }

    /// Builds the URL for a forecast request.
    /// Proxy path: `<proxy>/v1/forecast?...`  Direct: `https://api.open-meteo.com/v1/forecast?...`
    static func forecastURL(queryItems: [URLQueryItem]) -> URL? {
        buildURL(path: "/v1/forecast", host: directForecastHost, queryItems: queryItems)
    }

    /// Builds the URL for a geocoding (city search) request.
    /// Proxy path: `<proxy>/v1/search?...`  Direct: `https://geocoding-api.open-meteo.com/v1/search?...`
    static func geocodingURL(queryItems: [URLQueryItem]) -> URL? {
        buildURL(path: "/v1/search", host: directGeocodingHost, queryItems: queryItems)
    }

    private static func buildURL(path: String, host: String, queryItems: [URLQueryItem]) -> URL? {
        if let proxy = proxyBaseURL, var components = URLComponents(string: proxy) {
            // Preserve any base path on the proxy URL, then append our route.
            let basePath = components.path.hasSuffix("/")
                ? String(components.path.dropLast())
                : components.path
            components.path = basePath + path
            components.queryItems = queryItems
            return components.url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems
        return components.url
    }
}
