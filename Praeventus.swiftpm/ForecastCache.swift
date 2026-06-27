import Foundation

/// A persisted forecast snapshot, written after each successful (optionally
/// fused) fetch so the app can paint instantly on launch and survive being
/// offline.
struct CachedForecast: Codable, Equatable {
    let response: ForecastResponse
    let confidence: FusionConfidence
    let city: String
    let country: String
    let timestamp: Date
}

/// Best-effort, on-device forecast cache. Pure Foundation (works on Linux CI).
/// Keyed by coarse coordinates so nearby launches reuse the same entry; never
/// throws into the UI — a cache miss simply returns `nil`.
enum ForecastCache {

    /// Considered stale after an hour; older entries are still shown offline but
    /// flagged so the UI can mark them.
    static let ttl: TimeInterval = 60 * 60

    static func isFresh(_ entry: CachedForecast, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.timestamp) < ttl
    }

    static func save(_ entry: CachedForecast, latitude: Double, longitude: Double) {
        guard let url = fileURL(latitude: latitude, longitude: longitude) else { return }
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(latitude: Double, longitude: Double) -> CachedForecast? {
        guard let url = fileURL(latitude: latitude, longitude: longitude),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedForecast.self, from: data)
    }

    // MARK: - Storage

    private static func fileURL(latitude: Double, longitude: Double) -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        // 2 decimals ≈ 1 km — coarse on purpose, matching the app's privacy stance.
        let key = String(format: "forecast_%.2f_%.2f.json", latitude, longitude)
        return dir.appendingPathComponent(key)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return d
    }()
}
