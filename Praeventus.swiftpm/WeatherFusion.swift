import Foundation

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

    var modelCount: Int { models.count }

    /// Percentage label for the UI (e.g. "87%").
    var agreementPercent: Int { Int((agreement * 100).rounded()) }

    static let unknown = FusionConfidence(agreement: 1, temperatureSpreadC: 0, models: [])
}

/// Blends several Open-Meteo model responses into one synthetic response using
/// inverse-spread weighting (outliers are down-weighted) so the rest of the app
/// keeps consuming a single `ForecastResponse` unchanged.
enum WeatherFusion {

    /// Fuses the keyed model responses. Requires a non-empty input; a single
    /// response is returned untouched with full agreement.
    static func fuse(_ keyed: [WeatherModel: ForecastResponse]) -> (response: ForecastResponse, confidence: FusionConfidence) {
        let modelNames = keyed.keys.map(\.displayName).sorted()
        let responses = Array(keyed.values)

        guard let first = responses.first else {
            return (emptyResponse, .unknown)
        }
        if responses.count == 1 {
            return (first, FusionConfidence(agreement: 1, temperatureSpreadC: 0, models: modelNames))
        }

        let fusedCurrent = fuseCurrent(responses.map(\.current))
        let fusedHourly = fuseHourly(responses.compactMap(\.hourly))
        let fusedDaily = fuseDaily(responses.compactMap(\.daily))

        let fused = ForecastResponse(
            latitude: first.latitude,
            longitude: first.longitude,
            timezone: first.timezone,
            elevation: fusedDouble(responses.map(\.elevation)) ?? first.elevation,
            current: fusedCurrent,
            hourly: fusedHourly,
            daily: fusedDaily
        )

        return (fused, confidence(from: responses.map(\.current), models: modelNames))
    }

    // MARK: - Current

    private static func fuseCurrent(_ currents: [ForecastResponse.Current]) -> ForecastResponse.Current {
        ForecastResponse.Current(
            time: currents.first?.time,
            temperature2m: fusedDouble(currents.map(\.temperature2m)),
            apparentTemperature: fusedDouble(currents.map(\.apparentTemperature)),
            relativeHumidity2m: fusedDouble(currents.map(\.relativeHumidity2m)),
            surfacePressure: fusedDouble(currents.map(\.surfacePressure)),
            pressureMsl: fusedDouble(currents.map(\.pressureMsl)),
            windSpeed10m: fusedDouble(currents.map(\.windSpeed10m)),
            windDirection10m: fusedDirection(currents.map(\.windDirection10m)),
            windGusts10m: fusedDouble(currents.map(\.windGusts10m)),
            precipitationProbability: fusedDouble(currents.map(\.precipitationProbability)),
            weatherCode: fusedCode(currents.map(\.weatherCode)),
            uvIndex: fusedDouble(currents.map(\.uvIndex)),
            dewPoint2m: fusedDouble(currents.map(\.dewPoint2m)),
            visibility: fusedDouble(currents.map(\.visibility))
        )
    }

    // MARK: - Hourly

    private static func fuseHourly(_ hourlies: [ForecastResponse.Hourly]) -> ForecastResponse.Hourly? {
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
                fusedDouble(gather(t, hourlies, indexMaps, get))
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

    private static func fuseDaily(_ dailies: [ForecastResponse.Daily]) -> ForecastResponse.Daily? {
        guard let reference = dailies.max(by: { $0.time.count < $1.time.count }) else { return nil }
        let indexMaps = dailies.map { d -> [String: Int] in
            var map: [String: Int] = [:]
            for (i, t) in d.time.enumerated() { map[t] = i }
            return map
        }
        let times = reference.time

        func doubleCol(_ get: (ForecastResponse.Daily) -> [Double?]?) -> [Double?] {
            times.map { t in fusedDouble(gather(t, dailies, indexMaps, get)) }
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
    /// fade — without needing any historical/ground-truth data.
    private static func fusedDouble(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }.filter { $0.isFinite }
        guard !present.isEmpty else { return nil }
        if present.count == 1 { return present[0] }

        let mean = present.reduce(0, +) / Double(present.count)
        let deviations = present.map { abs($0 - mean) }
        let eps = (deviations.max() ?? 0) * 0.25 + 1e-6
        let weights = deviations.map { 1.0 / ($0 + eps) }
        let weightSum = weights.reduce(0, +)
        let weighted = zip(present, weights).reduce(0) { $0 + $1.0 * $1.1 }
        return weighted / weightSum
    }

    /// Vector (circular) mean of compass bearings — correct across the 0°/360° seam.
    private static func fusedDirection(_ values: [Int?]) -> Int? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        let radians = present.map { Double($0) * .pi / 180 }
        let s = radians.reduce(0) { $0 + sin($1) }
        let c = radians.reduce(0) { $0 + cos($1) }
        if s == 0, c == 0 { return present[0] }
        var degrees = atan2(s, c) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return Int(degrees.rounded()) % 360
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

    // MARK: - Confidence

    private static func confidence(from currents: [ForecastResponse.Current], models: [String]) -> FusionConfidence {
        let temps = currents.compactMap(\.temperature2m).filter { $0.isFinite }
        guard let lo = temps.min(), let hi = temps.max() else {
            return FusionConfidence(agreement: 1, temperatureSpreadC: 0, models: models)
        }
        let spread = hi - lo
        // An 8 °C disagreement collapses agreement to 0; perfect overlap is 1.
        let agreement = max(0, min(1, 1 - spread / 8))
        return FusionConfidence(agreement: agreement, temperatureSpreadC: spread, models: models)
    }

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
