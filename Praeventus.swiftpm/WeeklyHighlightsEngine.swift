import Foundation

/// A single actionable event distilled from the 7-day hourly forecast — a
/// contiguous block of hours that share a notable condition (rain or heat).
/// Carries raw `Date`s and the peak value so the UI can localise day names,
/// time formats and units; the engine itself emits no user-facing strings.
struct WeatherHighlight: Identifiable, Equatable {
    enum Kind: String, Equatable {
        /// A run of hours with a high precipitation probability.
        case rain
        /// A run of hours above the heat threshold.
        case heat
    }

    let id = UUID()
    let kind: Kind
    /// Start of the first qualifying hour.
    let start: Date
    /// End of the last qualifying hour (last hour's start + 1 h).
    let end: Date
    /// Peak value within the window — max precipitation probability (%) for
    /// `.rain`, max temperature (°C) for `.heat`.
    let peakValue: Double

    static func == (lhs: WeatherHighlight, rhs: WeatherHighlight) -> Bool {
        lhs.kind == rhs.kind && lhs.start == rhs.start &&
            lhs.end == rhs.end && lhs.peakValue == rhs.peakValue
    }
}

/// Scans the 7-day hourly arrays (`precipitation_probability`, `temperature_2m`)
/// and surfaces the few most actionable events, so users see "when will it rain,
/// when will it be too hot" without reading the raw hourly strip.
///
/// Foundation-only and `O(n)` in the number of hourly samples (single pass per
/// variable), so it never adds to `MinutecastEngine`'s budget.
enum WeeklyHighlightsEngine {

    /// Precipitation probability (%) at or above which an hour counts as rainy.
    static let rainProbabilityThreshold = 50.0
    /// Absolute floor (°C) for the "too hot" classification.
    static let absoluteHeatThresholdC = 32.0
    /// A heat window also qualifies if it exceeds the week's mean by this much.
    static let heatAboveAverageDeltaC = 5.0
    /// Largest gap (seconds) still treated as contiguous between two samples.
    private static let contiguityToleranceSeconds: TimeInterval = 3700

    /// Extracts rain and heat highlights from the hourly forecast, sorted by
    /// start time and capped at `maxHighlights`. Past hours are skipped.
    static func highlights(
        from hourly: ForecastResponse.Hourly?,
        now: Date = Date(),
        maxHighlights: Int = 6
    ) -> [WeatherHighlight] {
        guard let hourly else { return [] }
        let times = hourly.time.map(parseDate)
        let temps = hourly.temperature2m ?? []
        let probs = hourly.precipitationProbability ?? []

        let validTemps = temps.compactMap { $0 }.filter(\.isFinite)
        let mean = validTemps.isEmpty
            ? nil
            : validTemps.reduce(0, +) / Double(validTemps.count)
        let heatThreshold = max(absoluteHeatThresholdC, (mean ?? absoluteHeatThresholdC) + heatAboveAverageDeltaC)

        let rain = windows(times: times, values: probs, now: now) { $0 >= rainProbabilityThreshold }
            .map { WeatherHighlight(kind: .rain, start: $0.start, end: $0.end, peakValue: $0.peak) }
        let heat = windows(times: times, values: temps, now: now) { $0 >= heatThreshold }
            .map { WeatherHighlight(kind: .heat, start: $0.start, end: $0.end, peakValue: $0.peak) }

        return Array((rain + heat).sorted { $0.start < $1.start }.prefix(maxHighlights))
    }

    // MARK: - Contiguous-run extraction

    private struct Run {
        let start: Date
        let end: Date
        let peak: Double
    }

    /// Single linear pass that groups consecutive qualifying hours into runs,
    /// breaking on a non-qualifying hour, a missing value, or a time gap.
    private static func windows(
        times: [Date?],
        values: [Double?],
        now: Date,
        predicate: (Double) -> Bool
    ) -> [Run] {
        var result: [Run] = []
        var current: (start: Date, end: Date, peak: Double, last: Date)?

        func close() {
            if let c = current { result.append(Run(start: c.start, end: c.end, peak: c.peak)) }
            current = nil
        }

        let count = min(times.count, values.count)
        for i in 0 ..< count {
            guard let date = times[i], let value = values[i], value.isFinite,
                  predicate(value), date.addingTimeInterval(3600) > now else {
                close()
                continue
            }
            if var c = current, date.timeIntervalSince(c.last) <= contiguityToleranceSeconds {
                c.end = date.addingTimeInterval(3600)
                c.peak = max(c.peak, value)
                c.last = date
                current = c
            } else {
                close()
                current = (date, date.addingTimeInterval(3600), value, date)
            }
        }
        close()
        return result
    }

    // MARK: - Time parsing

    private static func parseDate(_ iso: String) -> Date? {
        if let d = isoNoSeconds.date(from: iso) { return d }
        return isoFull.date(from: iso)
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
