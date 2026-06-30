import Foundation

/// A short-term precipitation transition derived from `/nowcast` radar data,
/// relative to `referenceDate`. Foundation-only — no SwiftUI import.
enum NowcastEvent: Equatable {
    /// Not currently raining; rain begins in `minutesUntil` minutes and is
    /// expected to last `durationMinutes` (nil if it outlasts the data window).
    case startingSoon(minutesUntil: Int, durationMinutes: Int?)
    /// Currently raining; expected to stop in `minutesUntil` minutes.
    case stoppingSoon(minutesUntil: Int)
    /// Currently raining with no stop visible inside the data window.
    /// `remainingMinutes` is how far the radar data currently extends.
    case ongoing(remainingMinutes: Int?)
}

/// Derives a human-narratable rain transition from MET Norway nowcast radar
/// points. Used to enrich the hourly strip with "rain starts/stops in N min"
/// without requiring the UI to understand raw precipitation rates.
enum NowcastSummaryEngine {

    /// Precipitation rate (mm/h) above which a point counts as "raining".
    static let rainThresholdMmh = 0.1

    /// - Parameters:
    ///   - points: Raw `/nowcast` minutecast points, any order.
    ///   - referenceDate: "Now" — injectable for testing.
    /// - Returns: `nil` when there's no notable transition to narrate (e.g.
    ///   dry now and staying dry for the whole window).
    static func summarize(points: [NowcastPoint], referenceDate: Date = Date()) -> NowcastEvent? {
        let parsed = points
            .compactMap { point -> (date: Date, rate: Double)? in
                guard let date = isoDate(point.time) else { return nil }
                return (date, point.precipitationRate)
            }
            .sorted { $0.date < $1.date }

        guard !parsed.isEmpty else { return nil }

        // "Now" is the first sample at or after referenceDate, else the last
        // available sample (data window has already elapsed).
        let nowIndex = parsed.firstIndex { $0.date >= referenceDate } ?? parsed.count - 1
        let isRainingNow = parsed[nowIndex].rate > rainThresholdMmh

        if isRainingNow {
            guard let stopIndex = parsed[(nowIndex + 1)...].firstIndex(where: { $0.rate <= rainThresholdMmh }) else {
                let remaining = minutes(from: referenceDate, to: parsed[parsed.count - 1].date)
                return .ongoing(remainingMinutes: remaining > 0 ? remaining : nil)
            }
            let minutesUntilStop = minutes(from: referenceDate, to: parsed[stopIndex].date)
            return .stoppingSoon(minutesUntil: max(0, minutesUntilStop))
        }

        guard let startIndex = parsed[(nowIndex + 1)...].firstIndex(where: { $0.rate > rainThresholdMmh }) else {
            return nil
        }
        let minutesUntilStart = minutes(from: referenceDate, to: parsed[startIndex].date)

        let duration: Int?
        if let stopIndex = parsed[(startIndex + 1)...].firstIndex(where: { $0.rate <= rainThresholdMmh }) {
            duration = minutes(from: parsed[startIndex].date, to: parsed[stopIndex].date)
        } else {
            duration = nil
        }

        return .startingSoon(minutesUntil: max(0, minutesUntilStart), durationMinutes: duration)
    }

    // MARK: - Parsing

    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func isoDate(_ string: String) -> Date? {
        formatter.date(from: string)
    }

    private static func minutes(from: Date, to: Date) -> Int {
        Int((to.timeIntervalSince(from) / 60).rounded())
    }
}
