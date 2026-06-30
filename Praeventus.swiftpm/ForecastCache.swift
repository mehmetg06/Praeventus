import Foundation
#if canImport(os)
import os
#endif

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
        let data: Data
        do {
            data = try encoder.encode(entry)
        } catch {
            log("encode failed during save: \(error)")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            log("disk write failed: \(error)")
        }
    }

    static func load(latitude: Double, longitude: Double) -> CachedForecast? {
        guard let url = fileURL(latitude: latitude, longitude: longitude) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // File doesn't exist yet — normal on first launch.
            return nil
        }
        do {
            return try decoder.decode(CachedForecast.self, from: data)
        } catch {
            log("decode failed (corrupt cache will be overwritten on next save): \(error)")
            return nil
        }
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

    private static func log(_ message: String) {
        #if canImport(os)
        logger.warning("\(message)")
        #else
        print("[ForecastCache] \(message)")
        #endif
    }

    #if canImport(os)
    private static let logger = Logger(subsystem: "com.mehmetg06.praeventus", category: "ForecastCache")
    #endif

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
