import Foundation

/// How confidence in a blended forecast decays as the prediction horizon grows.
/// Near-term hours are trustworthy; multi-day hours much less so. Coefficients
/// are modulated by model agreement (low agreement decays faster) and, when a
/// radar nowcast is present, the first band is pinned high.
struct HorizonConfidence: Codable, Equatable {
    /// 0…1 multiplier for the first 6 forecast hours.
    let shortRange: Double
    /// 0…1 multiplier for the 6–24 h band.
    let midRange: Double
    /// 0…1 multiplier for the 24 h+ band.
    let longRange: Double

    /// Confidence multiplier for a given number of hours ahead of "now".
    func multiplier(atHoursAhead hours: Double) -> Double {
        switch hours {
        case ..<6:    return shortRange
        case 6 ..< 24: return midRange
        default:      return longRange
        }
    }

    /// A copy with the short-range band pinned to full confidence — used when a
    /// radar nowcast covers the location (short-term radar beats model output).
    func boostingShortRange() -> HorizonConfidence {
        HorizonConfidence(shortRange: 1, midRange: midRange, longRange: longRange)
    }
}

/// How well the blended models agreed, surfaced in the Lab as an honest
/// uncertainty signal. This is the on-device, training-free substitute for a
/// server-side ML bias-correction confidence score.
struct FusionConfidence: Codable, Equatable {
    /// 0…1 — high when the models cluster, low when they disagree.
    let agreement: Double
    /// Current-temperature spread (°C) across the blended models.
    let temperatureSpreadC: Double
    /// Display names of the models that contributed.
    let models: [String]
    /// How confidence tapers off with forecast horizon. Optional so forecasts
    /// cached before this field existed still decode (missing → nil).
    let horizonDecay: HorizonConfidence?
    /// True when a cross-source pressure outlier was detected and down-weighted.
    /// Optional/additive for cache backward-compatibility.
    let anomalyDetected: Bool?
    /// Human-readable name of the suspect source, if any (e.g. "ICON", "METAR").
    let anomalySource: String?

    var modelCount: Int { models.count }

    /// Percentage label for the UI (e.g. "87%").
    var agreementPercent: Int { Int((agreement * 100).rounded()) }

    /// Convenience: whether an anomaly was flagged (nil decodes as false).
    var hasAnomaly: Bool { anomalyDetected ?? false }

    init(
        agreement: Double,
        temperatureSpreadC: Double,
        models: [String],
        horizonDecay: HorizonConfidence? = nil,
        anomalyDetected: Bool? = nil,
        anomalySource: String? = nil
    ) {
        self.agreement = agreement
        self.temperatureSpreadC = temperatureSpreadC
        self.models = models
        self.horizonDecay = horizonDecay
        self.anomalyDetected = anomalyDetected
        self.anomalySource = anomalySource
    }

    /// Returns a copy with the short-horizon band pinned high because a radar
    /// nowcast covers the location. Leaves everything else untouched.
    func withNowcastShortRangeBoost() -> FusionConfidence {
        guard let horizonDecay else { return self }
        return FusionConfidence(
            agreement: agreement,
            temperatureSpreadC: temperatureSpreadC,
            models: models,
            horizonDecay: horizonDecay.boostingShortRange(),
            anomalyDetected: anomalyDetected,
            anomalySource: anomalySource
        )
    }

    static let unknown = FusionConfidence(agreement: 1, temperatureSpreadC: 0, models: [])
}

/// A real-time ground-truth observation (from the nearest METAR station) used to
/// anchor and re-weight the numerical models. All values are converted to the
/// app's working units (°C, km/h, degrees true, hPa). `ageMinutes` drives how
/// much trust the anchor receives — a fresh report is authoritative, a stale one
/// fades back toward neutral.
struct FusionGroundTruth: Equatable {
    let temperatureC: Double?
    let windSpeedKmh: Double?
    let windDirectionDeg: Double?
    let pressureHPa: Double?
    /// Minutes elapsed since the observation. Negative/NaN treated as fresh.
    let ageMinutes: Double

    /// Trust in the observation, 1 at issue time decaying with a ~30 min
    /// e-folding time (≈ 0.85 at 5 min, ≈ 0.19 at 50 min).
    var freshness: Double {
        guard ageMinutes.isFinite, ageMinutes > 0 else { return 1 }
        return exp(-ageMinutes / 30.0)
    }

    /// True when the observation carries at least one usable comparison value.
    var hasUsableValue: Bool {
        temperatureC != nil || windSpeedKmh != nil || pressureHPa != nil
    }

    /// Builds a ground-truth anchor from a raw METAR observation, converting
    /// aviation units (knots, inHg) into the app's working units (km/h, hPa).
    init?(metar raw: MetarRaw, now: Date = Date()) {
        let temp = raw.temp
        let windKmh = raw.wspd.map { $0 * 1.852 }
        // wdir == 0 encodes calm / variable, not a true northerly bearing.
        let windDir = raw.wdir.flatMap { $0 > 0 ? $0 : nil }
        let pressure = raw.altim.map { $0 * 33.8639 }

        guard temp != nil || windKmh != nil || pressure != nil else { return nil }

        self.temperatureC = temp
        self.windSpeedKmh = windKmh
        self.windDirectionDeg = windDir
        self.pressureHPa = pressure

        if let iso = raw.reportTime,
           let observed = Self.parseISO(iso) {
            ageMinutes = max(0, now.timeIntervalSince(observed) / 60.0)
        } else {
            ageMinutes = 0
        }
    }

    /// Memberwise convenience init for synthetic ground truth (Lab overrides,
    /// tests) that bypasses METAR unit conversion. The primary
    /// `init?(metar:now:)` above is unaffected.
    init(temperatureC: Double?, windSpeedKmh: Double?, windDirectionDeg: Double?, pressureHPa: Double?, ageMinutes: Double) {
        self.temperatureC = temperatureC
        self.windSpeedKmh = windSpeedKmh
        self.windDirectionDeg = windDirectionDeg
        self.pressureHPa = pressureHPa
        self.ageMinutes = ageMinutes
    }

    private static func parseISO(_ iso: String) -> Date? {
        if let d = isoFull.date(from: iso) { return d }
        return isoNoSeconds.date(from: iso)
    }

    private nonisolated(unsafe) static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoNoSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()
}

/// Blends several NWP model responses into one synthetic response using
/// inverse-spread weighting (outliers are down-weighted) so the rest of the app
/// keeps consuming a single `ForecastResponse` unchanged.
///
/// When a `FusionGroundTruth` (METAR) anchor is supplied the blend becomes an
/// *adaptive multi-source ensemble*: models that match the live observation are
/// up-weighted (exponential decay on deviation), the observation itself joins
/// the current blend as a freshness-weighted anchor, and a cross-source pressure
/// outlier is flagged and down-weighted.
enum WeatherFusion {

    // MARK: - Tunable constants

    /// Exponential decay rate on a model's deviation from ground truth. Higher
    /// values punish disagreement with the observation more aggressively.
    private static let deviationDecayK = 0.35
    /// Weight a perfectly fresh METAR anchor carries relative to a model (≈2×).
    private static let metarAnchorWeight = 2.0
    /// Multiplicative penalty applied to a source flagged as a pressure outlier.
    private static let anomalyPenalty = 0.15
    /// Modified z-score (MAD-based) above which a pressure source is suspect.
    private static let anomalyZThreshold = 3.5
    /// A source must also differ from the median by at least this many hPa, so
    /// tiny spreads are never flagged as anomalies.
    private static let anomalyAbsoluteFloorHPa = 3.0

    /// Fuses the keyed model responses. Requires a non-empty input; a single
    /// response is returned untouched with full agreement.
    ///
    /// - Parameters:
    ///   - groundTruth: Optional live observation used as a ground-truth anchor.
    ///   - devicePressureHPa: Optional on-device barometer reading, included only
    ///     in the cross-source pressure anomaly check (never blended).
    static func fuse(
        _ keyed: [WeatherModel: ForecastResponse],
        groundTruth: FusionGroundTruth? = nil,
        devicePressureHPa: Double? = nil
    ) -> (response: ForecastResponse, confidence: FusionConfidence) {
        // Stable, name-aligned ordering so per-model weights line up with names.
        let ordered = keyed.sorted { $0.key.displayName < $1.key.displayName }
        let modelNames = ordered.map(\.key.displayName)
        let responses = ordered.map(\.value)

        guard let first = responses.first else {
            return (emptyResponse, .unknown)
        }
        if responses.count == 1 {
            let agreement = 1.0
            return (first, FusionConfidence(
                agreement: agreement,
                temperatureSpreadC: 0,
                models: modelNames,
                horizonDecay: horizonDecay(agreement: agreement)
            ))
        }

        let currents = responses.map(\.current)
        let gt = (groundTruth?.hasUsableValue == true) ? groundTruth : nil

        // 1. Ground-truth correction: weight each model by how closely its
        //    current snapshot matches the live observation.
        var modelWeights = deviationWeights(currents, groundTruth: gt)

        // 3. Cross-source anomaly: flag and down-weight a pressure outlier.
        let anomaly = detectPressureAnomaly(
            modelNames: modelNames,
            currents: currents,
            groundTruth: gt,
            devicePressureHPa: devicePressureHPa
        )
        var metarAnchorScale = 1.0
        if let anomaly {
            switch anomaly.kind {
            case .model(let index):
                var w = modelWeights ?? Array(repeating: 1.0, count: responses.count)
                if index < w.count { w[index] *= anomalyPenalty }
                modelWeights = w
            case .metar:
                metarAnchorScale = 0  // exclude the observation if it is the outlier
            case .device:
                break               // device barometer never enters the blend
            }
        }

        let fusedCurrent = fuseCurrent(currents, modelWeights: modelWeights, groundTruth: gt, anchorScale: metarAnchorScale)

        // Only thread per-model weights into hourly/daily when every model
        // supplied that series, so weight indices stay aligned with model order.
        let hourlies = responses.compactMap(\.hourly)
        let dailies = responses.compactMap(\.daily)
        let hourlyWeights = hourlies.count == responses.count ? modelWeights : nil
        let dailyWeights = dailies.count == responses.count ? modelWeights : nil

        let fusedHourly = fuseHourly(hourlies, modelWeights: hourlyWeights)
        let fusedDaily = fuseDaily(dailies, modelWeights: dailyWeights)

        let fused = ForecastResponse(
            latitude: first.latitude,
            longitude: first.longitude,
            timezone: first.timezone,
            elevation: fusedDouble(responses.map(\.elevation)) ?? first.elevation,
            current: fusedCurrent,
            hourly: fusedHourly,
            daily: fusedDaily
        )

        return (fused, confidence(from: currents, models: modelNames, anomaly: anomaly))
    }

    // MARK: - Current

    private static func fuseCurrent(
        _ currents: [ForecastResponse.Current],
        modelWeights: [Double]?,
        groundTruth gt: FusionGroundTruth?,
        anchorScale: Double
    ) -> ForecastResponse.Current {
        // The freshness-scaled weight a usable METAR anchor receives.
        let anchorWeight = (gt?.freshness ?? 0) * metarAnchorWeight * anchorScale

        func anchoredDouble(_ values: [Double?], anchor: Double?) -> Double? {
            guard let anchor, anchorWeight > 0 else {
                return fusedDouble(values, modelWeights: modelWeights)
            }
            let base = modelWeights ?? Array(repeating: 1.0, count: values.count)
            return fusedDouble(values + [anchor], modelWeights: base + [anchorWeight])
        }

        return ForecastResponse.Current(
            time: currents.first?.time,
            temperature2m: anchoredDouble(currents.map(\.temperature2m), anchor: gt?.temperatureC),
            apparentTemperature: fusedDouble(currents.map(\.apparentTemperature), modelWeights: modelWeights),
            relativeHumidity2m: fusedDouble(currents.map(\.relativeHumidity2m), modelWeights: modelWeights),
            surfacePressure: anchoredDouble(currents.map(\.surfacePressure), anchor: gt?.pressureHPa),
            pressureMsl: anchoredDouble(currents.map(\.pressureMsl), anchor: gt?.pressureHPa),
            windSpeed10m: anchoredDouble(currents.map(\.windSpeed10m), anchor: gt?.windSpeedKmh),
            windDirection10m: fusedDirection(currents.map(\.windDirection10m)),
            windGusts10m: fusedDouble(currents.map(\.windGusts10m), modelWeights: modelWeights),
            precipitationProbability: fusedDouble(currents.map(\.precipitationProbability), modelWeights: modelWeights),
            weatherCode: fusedCode(currents.map(\.weatherCode)),
            uvIndex: fusedDouble(currents.map(\.uvIndex), modelWeights: modelWeights),
            dewPoint2m: fusedDouble(currents.map(\.dewPoint2m), modelWeights: modelWeights),
            visibility: fusedDouble(currents.map(\.visibility), modelWeights: modelWeights)
        )
    }

    // MARK: - Hourly

    private static func fuseHourly(_ hourlies: [ForecastResponse.Hourly], modelWeights: [Double]?) -> ForecastResponse.Hourly? {
        // Use the longest series as the timeline; align other models by timestamp.
        guard let reference = hourlies.max(by: { $0.time.count < $1.time.count }) else { return nil }
        let indexMaps = hourlies.map { h -> [String: Int] in
            var map: [String: Int] = [:]
            for (i, t) in h.time.enumerated() { map[t] = i }
            return map
        }
        let times = reference.time

        func doubleCol(_ get: (ForecastResponse.Hourly) -> [Double?]?) -> [Double?] {
            times.map { t in
                fusedDouble(gather(t, hourlies, indexMaps, get), modelWeights: modelWeights)
            }
        }
        return ForecastResponse.Hourly(
            time: times,
            temperature2m: doubleCol(\.temperature2m),
            precipitationProbability: doubleCol(\.precipitationProbability),
            weatherCode: times.map { t in fusedCode(gather(t, hourlies, indexMaps) { $0.weatherCode }) },
            uvIndex: doubleCol(\.uvIndex),
            windSpeed10m: doubleCol(\.windSpeed10m),
            windDirection10m: times.map { t in fusedDirection(gather(t, hourlies, indexMaps) { $0.windDirection10m }) },
            windGusts10m: doubleCol(\.windGusts10m),
            relativeHumidity2m: doubleCol(\.relativeHumidity2m),
            dewPoint2m: doubleCol(\.dewPoint2m),
            visibility: doubleCol(\.visibility)
        )
    }

    // MARK: - Daily

    private static func fuseDaily(_ dailies: [ForecastResponse.Daily], modelWeights: [Double]?) -> ForecastResponse.Daily? {
        guard let reference = dailies.max(by: { $0.time.count < $1.time.count }) else { return nil }
        let indexMaps = dailies.map { d -> [String: Int] in
            var map: [String: Int] = [:]
            for (i, t) in d.time.enumerated() { map[t] = i }
            return map
        }
        let times = reference.time

        func doubleCol(_ get: (ForecastResponse.Daily) -> [Double?]?) -> [Double?] {
            times.map { t in fusedDouble(gather(t, dailies, indexMaps, get), modelWeights: modelWeights) }
        }

        return ForecastResponse.Daily(
            time: times,
            temperature2mMax: doubleCol(\.temperature2mMax),
            temperature2mMin: doubleCol(\.temperature2mMin),
            apparentTemperatureMax: doubleCol(\.apparentTemperatureMax),
            apparentTemperatureMin: doubleCol(\.apparentTemperatureMin),
            uvIndexMax: doubleCol(\.uvIndexMax),
            windSpeed10mMax: doubleCol(\.windSpeed10mMax),
            windDirection10mDominant: times.map { t in fusedDirection(gather(t, dailies, indexMaps) { $0.windDirection10mDominant }) },
            windGusts10mMax: doubleCol(\.windGusts10mMax),
            precipitationSum: doubleCol(\.precipitationSum),
            weatherCode: times.map { t in fusedCode(gather(t, dailies, indexMaps) { $0.weatherCode }) },
            // Astronomical, model-independent — keep the reference timeline's values.
            sunrise: reference.sunrise,
            sunset: reference.sunset
        )
    }

    // MARK: - Alignment

    /// Gathers one variable's value at timestamp `t` from every model, in model order.
    private static func gather<S, V>(
        _ t: String,
        _ series: [S],
        _ indexMaps: [[String: Int]],
        _ get: (S) -> [V?]?
    ) -> [V?] {
        series.enumerated().map { (i, s) in
            guard let idx = indexMaps[i][t], let arr = get(s), idx < arr.count else { return nil }
            return arr[idx]
        }
    }

    // MARK: - Math

    /// Inverse-spread weighted mean: each value is weighted by `1/(deviation + ε)`
    /// where ε scales with the spread, so consensus values dominate and outliers
    /// fade. An optional `modelWeights` array (aligned to the input order) is
    /// multiplied in, letting callers up-weight ground-truth-matching sources or
    /// inject a freshness-weighted observation as an extra value.
    private static func fusedDouble(_ values: [Double?], modelWeights: [Double]? = nil) -> Double? {
        var pairs: [(value: Double, weight: Double)] = []
        for (i, v) in values.enumerated() {
            guard let v, v.isFinite else { continue }
            let external = modelWeights.flatMap { i < $0.count ? $0[i] : nil } ?? 1.0
            guard external > 0 else { continue }
            pairs.append((v, external))
        }
        guard !pairs.isEmpty else { return nil }
        if pairs.count == 1 { return pairs[0].value }

        let mean = pairs.reduce(0) { $0 + $1.value } / Double(pairs.count)
        let maxDev = pairs.map { abs($0.value - mean) }.max() ?? 0
        let eps = maxDev * 0.25 + 1e-6
        var num = 0.0
        var den = 0.0
        for p in pairs {
            let weight = (1.0 / (abs(p.value - mean) + eps)) * p.weight
            num += p.value * weight
            den += weight
        }
        return den > 0 ? num / den : mean
    }

    /// Vector (circular) mean of compass bearings — correct across the 0°/360° seam.
    private static func fusedDirection(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        let radians = present.map { $0 * .pi / 180 }
        let s = radians.reduce(0) { $0 + sin($1) }
        let c = radians.reduce(0) { $0 + cos($1) }
        if s == 0, c == 0 { return present[0] }
        var degrees = atan2(s, c) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees.truncatingRemainder(dividingBy: 360)
    }

    /// Majority-vote weather code; ties break toward the more severe (higher) code.
    private static func fusedCode(_ values: [Int?]) -> Int? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for v in present { counts[v, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 0
        return counts.filter { $0.value == maxCount }.keys.max()
    }

    // MARK: - Ground-truth correction (Item 1)

    /// Per-model multiplicative weights derived from each model's deviation from
    /// the live observation, blended toward neutral by the observation's age.
    /// Returns `nil` when there is no usable ground truth (preserving the prior
    /// inverse-spread-only behaviour).
    private static func deviationWeights(
        _ currents: [ForecastResponse.Current],
        groundTruth gt: FusionGroundTruth?
    ) -> [Double]? {
        guard let gt, gt.hasUsableValue else { return nil }
        let f = gt.freshness

        return currents.map { c in
            var deviation = 0.0
            if let t = c.temperature2m, let m = gt.temperatureC {
                deviation += abs(t - m)              // °C, ~1 unit per °C
            }
            if let w = c.windSpeed10m, let mw = gt.windSpeedKmh {
                deviation += abs(w - mw) / 10.0       // normalise: ~1 unit per 10 km/h
            }
            if let p = c.pressureMsl ?? c.surfacePressure, let mp = gt.pressureHPa {
                deviation += abs(p - mp) / 3.0        // normalise: ~1 unit per 3 hPa
            }
            let matched = exp(-deviationDecayK * deviation)  // (0, 1]
            // Fade the correction toward uniform (1.0) as the observation ages.
            return (1 - f) + f * matched
        }
    }

    // MARK: - Cross-source anomaly (Item 3)

    private struct PressureAnomaly {
        enum Kind: Equatable {
            case model(index: Int)
            case metar
            case device
        }
        let kind: Kind
        let source: String
    }

    /// Robust outlier check over the independent mean-sea-level pressure sources
    /// (each model, the METAR altimeter, an optional device barometer). Uses a
    /// MAD-based modified z-score because a classic z-score cannot exceed ~1.2
    /// with only three samples. Returns the single worst qualifying outlier.
    private static func detectPressureAnomaly(
        modelNames: [String],
        currents: [ForecastResponse.Current],
        groundTruth gt: FusionGroundTruth?,
        devicePressureHPa: Double?
    ) -> PressureAnomaly? {
        var sources: [(kind: PressureAnomaly.Kind, name: String, hPa: Double)] = []
        for (i, c) in currents.enumerated() {
            if let p = c.pressureMsl ?? c.surfacePressure, p.isFinite {
                sources.append((.model(index: i), modelNames[i], p))
            }
        }
        if let mp = gt?.pressureHPa, mp.isFinite {
            sources.append((.metar, "METAR", mp))
        }
        if let dp = devicePressureHPa, dp.isFinite {
            sources.append((.device, "Device", dp))
        }

        guard sources.count >= 3 else { return nil }

        let values = sources.map(\.hPa).sorted()
        let median = self.median(of: values)
        let deviations = values.map { abs($0 - median) }
        let mad = self.median(of: deviations.sorted())

        // Scale factor 0.6745 makes MAD comparable to a standard deviation.
        let scale = mad > 1e-6 ? 0.6745 / mad : 0

        var worst: (anomaly: PressureAnomaly, score: Double)?
        for s in sources {
            let absDev = abs(s.hPa - median)
            guard absDev >= anomalyAbsoluteFloorHPa else { continue }
            let z = scale > 0 ? absDev * scale : .infinity  // zero MAD ⇒ a lone deviator is a clear outlier
            guard z >= anomalyZThreshold else { continue }
            if let current = worst, z <= current.score { continue }
            worst = (PressureAnomaly(kind: s.kind, source: s.name), z)
        }
        return worst?.anomaly
    }

    private static func median(of sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    // MARK: - Confidence

    private static func confidence(
        from currents: [ForecastResponse.Current],
        models: [String],
        anomaly: PressureAnomaly?
    ) -> FusionConfidence {
        let temps = currents.compactMap(\.temperature2m).filter { $0.isFinite }
        guard let lo = temps.min(), let hi = temps.max() else {
            return FusionConfidence(
                agreement: 1,
                temperatureSpreadC: 0,
                models: models,
                horizonDecay: horizonDecay(agreement: 1),
                anomalyDetected: anomaly != nil,
                anomalySource: anomaly?.source
            )
        }
        let spread = hi - lo
        // An 8 °C disagreement collapses agreement to 0; perfect overlap is 1.
        let agreement = max(0, min(1, 1 - spread / 8))
        return FusionConfidence(
            agreement: agreement,
            temperatureSpreadC: spread,
            models: models,
            horizonDecay: horizonDecay(agreement: agreement),
            anomalyDetected: anomaly != nil,
            anomalySource: anomaly?.source
        )
    }

    // MARK: - Temporal confidence decay (Item 2)

    /// Confidence multipliers per horizon band, modulated by model agreement:
    /// strong agreement decays slowly, weak agreement decays fast.
    private static func horizonDecay(agreement: Double) -> HorizonConfidence {
        let base = max(0, min(1, agreement))
        return HorizonConfidence(
            shortRange: 0.85 + 0.15 * base,   // first 6 h — always high
            midRange: 0.55 + 0.35 * base,     // 6–24 h — moderate
            longRange: 0.30 + 0.35 * base     // 24 h+ — low, agreement-sensitive
        )
    }

    // MARK: - Skill receipts (Phase A observability — no effect on fuse/weights)

    /// Lead-hour marks sampled from each model's hourly series (beyond the
    /// immediate "current" snapshot), one per `SkillLeadBucket`, so
    /// `SkillTracker`'s 200-slot ring buffer fills slowly instead of one
    /// receipt per hourly point per fetch.
    private static let receiptLeadHours: [Double] = [3, 12, 48]

    /// Converts this fetch's per-model predictions into `ForecastReceipt`s for
    /// `SkillTracker`. This is a pure read of `keyed` — it is never consulted
    /// by `fuse(_:groundTruth:devicePressureHPa:)` above, so depositing its
    /// output cannot change the blended forecast in any way.
    ///
    /// Only the "current" receipt carries a pressure value: the Open-Meteo-
    /// compatible `Hourly` series has no pressure column, so future-hour
    /// receipts score temperature/wind only.
    static func receipts(from keyed: [WeatherModel: ForecastResponse], issuedAt: Date = Date()) -> [ForecastReceipt] {
        var out: [ForecastReceipt] = []
        for (model, response) in keyed {
            let current = response.current
            out.append(ForecastReceipt(
                model: model.apiValue,
                issuedAt: issuedAt,
                validAt: issuedAt,
                temperatureC: current.temperature2m,
                windSpeedKmh: current.windSpeed10m,
                pressureHPa: current.pressureMsl ?? current.surfacePressure
            ))

            guard let hourly = response.hourly else { continue }
            let temps = hourly.temperature2m ?? []
            let winds = hourly.windSpeed10m ?? []
            for lead in receiptLeadHours {
                let target = issuedAt.addingTimeInterval(lead * 3600)
                guard let idx = nearestIndex(to: target, in: hourly.time),
                      let validAt = parseReceiptISO(hourly.time[idx])
                else { continue }
                out.append(ForecastReceipt(
                    model: model.apiValue,
                    issuedAt: issuedAt,
                    validAt: validAt,
                    temperatureC: idx < temps.count ? temps[idx] : nil,
                    windSpeedKmh: idx < winds.count ? winds[idx] : nil,
                    pressureHPa: nil
                ))
            }
        }
        return out
    }

    private static func nearestIndex(to target: Date, in times: [String]) -> Int? {
        var bestIndex: Int?
        var bestDelta = Double.greatestFiniteMagnitude
        for (i, t) in times.enumerated() {
            guard let date = parseReceiptISO(t) else { continue }
            let delta = abs(date.timeIntervalSince(target))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        return bestIndex
    }

    private static func parseReceiptISO(_ iso: String) -> Date? {
        // Same two shapes `WeatherMapping` handles: Open-Meteo's
        // "yyyy-MM-dd'T'HH:mm" and full ISO-8601 with an explicit timezone.
        if let d = receiptISOFormatter.date(from: iso) { return d }
        return receiptISO8601Formatter.date(from: iso)
    }

    private nonisolated(unsafe) static let receiptISO8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let receiptISOFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    /// Total fallback so `fuse` stays non-optional even on impossible empty input.
    private static var emptyResponse: ForecastResponse {
        ForecastResponse(
            latitude: 0, longitude: 0, timezone: nil, elevation: nil,
            current: ForecastResponse.Current(
                time: nil, temperature2m: nil, apparentTemperature: nil,
                relativeHumidity2m: nil, surfacePressure: nil, pressureMsl: nil,
                windSpeed10m: nil, windDirection10m: nil, windGusts10m: nil,
                precipitationProbability: nil, weatherCode: nil, uvIndex: nil,
                dewPoint2m: nil, visibility: nil
            ),
            hourly: nil, daily: nil
        )
    }
}
