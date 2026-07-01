import Foundation
#if canImport(os)
import os
#endif

/// One model's prediction for a single future instant, deposited right after
/// a forecast fetch/fuse and later compared against a METAR observation once
/// real time reaches `validAt`. Foundation-only, `Sendable` so it can cross
/// into `SkillTracker`'s actor isolation freely.
struct ForecastReceipt: Codable, Sendable, Equatable {
    /// `WeatherModel.apiValue` (e.g. "ecmwf_ifs025", "icon_global").
    let model: String
    /// When this prediction was produced (the fetch/fuse timestamp).
    let issuedAt: Date
    /// The future instant this prediction is *for* — compared against a
    /// METAR reading taken near this time.
    let validAt: Date
    let temperatureC: Double?
    let windSpeedKmh: Double?
    let pressureHPa: Double?
}

/// Which physical variable a skill score tracks.
enum SkillVariable: String, Codable, Sendable, CaseIterable {
    case temperature, wind, pressure
}

/// Forecast-horizon bucket a receipt's lead time falls into — mirrors the
/// bands `WeatherFusion`'s `horizonDecay` already uses (0–6h / 6–24h / 24h+),
/// so Phase-B weighting can reuse the same buckets without redefinition.
enum SkillLeadBucket: String, Codable, Sendable, CaseIterable {
    case shortRange, midRange, longRange

    init(leadHours: Double) {
        switch leadHours {
        case ..<6:     self = .shortRange
        case 6 ..< 24: self = .midRange
        default:       self = .longRange
        }
    }

    /// Display order for the Lab's scorecard (short → long).
    var sortIndex: Int {
        switch self {
        case .shortRange: return 0
        case .midRange:   return 1
        case .longRange:  return 2
        }
    }

    var displayLabel: String {
        switch self {
        case .shortRange: return "0-6h"
        case .midRange:   return "6-24h"
        case .longRange:  return "24h+"
        }
    }
}

/// Identifies one (model, variable, horizon) skill track.
struct SkillKey: Hashable, Codable, Sendable {
    let model: String
    let variable: SkillVariable
    let leadBucket: SkillLeadBucket
}

/// One model/variable/horizon's running accuracy, surfaced in the Lab's
/// "Model Karnesi" panel for observability.
///
/// **Phase A: read-only.** Nothing in the app yet consumes these scores to
/// re-weight `WeatherFusion` — that's Phase B. This struct exists purely so
/// we can see, over time, whether the EWMA actually separates model skill
/// before wiring anything to it (β = 0, hard-coded for this phase).
struct SkillRecord: Codable, Sendable, Equatable {
    /// EWMA of absolute error in the variable's native unit (°C / km/h / hPa).
    /// Lower is better.
    var ewmaError: Double
    /// How many METAR verifications have contributed to this score.
    var verificationCount: Int
}

/// Persisted receipts + skill table, written to disk as one JSON blob.
private struct SkillTrackerState: Codable {
    var receipts: [ForecastReceipt]
    var skill: [SkillKey: SkillRecord]
}

/// Collects per-model forecast predictions (`deposit`) and, once a live METAR
/// observation arrives, scores how close each model actually was
/// (`verify`) — a running, on-device skill scorecard per (model, variable,
/// lead-time bucket). Pure observability: nothing here feeds back into
/// `WeatherFusion.fuse()` in this phase.
///
/// Actor-isolated so concurrent deposits/verifies from overlapping forecast
/// loads never race, and so the (best-effort) disk I/O never touches the
/// main thread.
actor SkillTracker {
    static let shared = SkillTracker()

    private(set) var receipts: [ForecastReceipt] = []
    private(set) var skill: [SkillKey: SkillRecord] = [:]

    /// Ring buffer cap — oldest un-verified receipts are dropped first.
    private static let maxReceipts = 200
    /// A receipt is eligible for verification when `now` lands within this
    /// many seconds of its `validAt`.
    private static let verifyWindowSeconds: TimeInterval = 30 * 60
    /// EWMA smoothing factor. α = 2/(N+1) with N = 29 gives a ~14-sample
    /// half-life, matching the spec's "~14 gün yarı ömür" (assuming roughly
    /// one verification per day for a given model/variable/bucket).
    private static let alpha = 2.0 / 29.0

    private var loaded: Bool
    private let persistToDisk: Bool
    private let fileURL: URL?

    /// - Parameters:
    ///   - persistToDisk: `false` keeps everything in memory only — used by
    ///     tests so synthetic scenarios never touch disk at all.
    ///   - fileURL: Overrides the persistence location. `nil` (the default)
    ///     uses the real per-device cache file; tests pass a private temp
    ///     file so `.shared`'s on-disk state is never read or clobbered.
    ///     Production code should always use `.shared`.
    init(persistToDisk: Bool = true, fileURL: URL? = nil) {
        self.persistToDisk = persistToDisk
        self.loaded = !persistToDisk
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    // MARK: - Deposit

    /// Adds newly-fetched predictions to the buffer, trimming the oldest
    /// entries once the ring buffer's cap is exceeded.
    func deposit(_ new: [ForecastReceipt]) {
        loadIfNeeded()
        guard !new.isEmpty else { return }
        receipts.append(contentsOf: new)
        if receipts.count > Self.maxReceipts {
            receipts.removeFirst(receipts.count - Self.maxReceipts)
        }
        persist()
    }

    // MARK: - Verify

    /// Compares every buffered receipt whose `validAt` lands near `now`
    /// against a fresh METAR observation, updates the EWMA skill table, and
    /// removes the verified receipts from the buffer.
    func verify(against truth: FusionGroundTruth, at now: Date = Date()) {
        loadIfNeeded()
        guard truth.hasUsableValue else { return }
        guard !receipts.isEmpty else { return }

        var remaining: [ForecastReceipt] = []
        remaining.reserveCapacity(receipts.count)

        for receipt in receipts {
            guard abs(now.timeIntervalSince(receipt.validAt)) <= Self.verifyWindowSeconds else {
                remaining.append(receipt)
                continue
            }
            score(receipt, against: truth)
        }
        receipts = remaining
        persist()
    }

    /// Read-only snapshot for the Lab's "Model Karnesi" panel.
    func snapshot() -> [SkillKey: SkillRecord] {
        loadIfNeeded()
        return skill
    }

    // MARK: - Scoring

    private func score(_ receipt: ForecastReceipt, against truth: FusionGroundTruth) {
        let leadHours = receipt.validAt.timeIntervalSince(receipt.issuedAt) / 3600
        let bucket = SkillLeadBucket(leadHours: max(0, leadHours))

        func update(_ variable: SkillVariable, error: Double?) {
            guard let error, error.isFinite else { return }
            let key = SkillKey(model: receipt.model, variable: variable, leadBucket: bucket)
            var record = skill[key] ?? SkillRecord(ewmaError: error, verificationCount: 0)
            if record.verificationCount > 0 {
                record.ewmaError = Self.alpha * error + (1 - Self.alpha) * record.ewmaError
            } else {
                record.ewmaError = error
            }
            record.verificationCount += 1
            skill[key] = record
        }

        if let t = receipt.temperatureC, let mt = truth.temperatureC {
            update(.temperature, error: abs(t - mt))
        }
        if let w = receipt.windSpeedKmh, let mw = truth.windSpeedKmh {
            update(.wind, error: abs(w - mw))
        }
        if let p = receipt.pressureHPa, let mp = truth.pressureHPa {
            update(.pressure, error: abs(p - mp))
        }
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard persistToDisk, !loaded else { return }
        loaded = true
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let state = try? Self.decoder.decode(SkillTrackerState.self, from: data)
        else { return }
        receipts = state.receipts
        skill = state.skill
    }

    private func persist() {
        guard persistToDisk, let url = fileURL else { return }
        let state = SkillTrackerState(receipts: receipts, skill: skill)
        guard let data = try? Self.encoder.encode(state) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            log("disk write failed: \(error)")
        }
    }

    private static var defaultFileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("skill_tracker.json")
    }

    private func log(_ message: String) {
        #if canImport(os)
        Self.logger.warning("\(message)")
        #else
        print("[SkillTracker] \(message)")
        #endif
    }

    #if canImport(os)
    private static let logger = Logger(subsystem: "com.mehmetg06.praeventus", category: "SkillTracker")
    #endif

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
