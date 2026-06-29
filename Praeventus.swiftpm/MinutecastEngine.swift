import Foundation

// MARK: - Domain Models

/// A single weather point at one-minute resolution, computed entirely on-device.
struct MinutePoint: Equatable, Sendable {
    /// Minutes elapsed from the first hourly anchor (e.g. 0 = 14:00, 17 = 14:17).
    let minuteOffset: Int
    /// Wall-clock date for this point.
    let date: Date
    /// Catmull-Rom–interpolated air temperature (°C).
    let temperature: Double
    /// Catmull-Rom–interpolated relative humidity (%).
    let humidity: Double
    /// Catmull-Rom–interpolated wind speed (km/h).
    let windSpeed: Double
    /// Astronomically-derived UV index for this exact minute (0–UV_max).
    let uvIndex: Double
}

// MARK: - Nowcast API Types

/// One 5-minute radar data point returned by the Worker's /nowcast endpoint.
struct NowcastPoint: Equatable, Codable, Sendable {
    let time: String
    /// Instantaneous radar-derived rain rate (mm/h).
    let precipitationRate: Double
    /// Expected accumulation in the next hour (mm).
    let precipitationAmount: Double
    /// May be nil if the radar grid cell has no temperature sensor nearby.
    let temperature: Double?
    let humidity: Double?
    let windSpeed: Double      // km/h
    let windDirection: Double  // degrees
    let windGust: Double       // km/h
    let symbolCode: String
}

struct NowcastResponse: Decodable, Sendable {
    let minutecast: [NowcastPoint]
    let radarCoverage: Bool
    let generated_at: String?
}

// MARK: - Engine

/// On-device minute-resolution atmospheric engine.
///
/// ## Catmull-Rom Spline (FAZ 2)
/// Hourly forecast arrays (temperature, humidity, wind) are continuously
/// interpolated to 1-minute granularity using a clamped Catmull-Rom cubic
/// spline. This guarantees C¹ continuity at every hour boundary — no kinks —
/// while passing *through* every hourly observation (unlike Bezier curves).
///
/// ## UV Minute Model (FAZ 4)
/// The per-minute UV index is derived from the daily peak UV and the
/// instantaneous solar altitude computed by `AstronomicalEngine`.
///
/// **Formula (WMO simplified transfer model):**
/// ```
/// UV(t)  = UV_max · [sin(α(t)) / sin(α_noon)]^0.7 · cloudAttenuation
/// cloudAttenuation = 1 − 0.75 · (cloudCover/100)^3.4
/// ```
/// where α(t) is the solar altitude at time t and α_noon is the solar
/// altitude at local solar noon (the normalization ensures UV(noon) ≈ UV_max).
///
/// - Note: Domain layer — no UIKit / SwiftUI imports.
/// - Complexity: O(n · 60) where n = number of hourly segments.
enum MinutecastEngine {

    // MARK: - Public: Interpolation

    /// Interpolates parallel hourly arrays into per-minute `MinutePoint` values.
    ///
    /// - Parameters:
    ///   - temperatures:       Hourly temperature array (°C), ≥ 2 elements.
    ///   - humidities:         Hourly relative-humidity array (%), parallel to temperatures.
    ///   - windSpeeds:         Hourly wind-speed array (km/h), parallel to temperatures.
    ///   - anchorDate:         Wall-clock date that corresponds to `temperatures[0]`.
    ///   - latitude:           Observer latitude (degrees, WGS-84).
    ///   - longitude:          Observer longitude (degrees, WGS-84).
    ///   - dailyMaxUV:         Forecast daily-peak UV index (from the NWP model).
    ///   - cloudCoverPercent:  Current cloud cover (0–100). Used for UV attenuation.
    /// - Returns: Flat array of `MinutePoint` starting at `anchorDate`, one per minute.
    static func interpolate(
        temperatures: [Double],
        humidities: [Double],
        windSpeeds: [Double],
        anchorDate: Date,
        latitude: Double,
        longitude: Double,
        dailyMaxUV: Double,
        cloudCoverPercent: Double
    ) -> [MinutePoint] {
        let count = min(temperatures.count, humidities.count, windSpeeds.count)
        guard count >= 2 else { return [] }

        // Pre-compute the solar-noon normalization factor once for the day
        // so we don't call AstronomicalEngine twice per minute inside the loop.
        let noonSinPow = solarNoonSinPow(anchorDate: anchorDate,
                                         latitude: latitude,
                                         longitude: longitude)

        var points = [MinutePoint]()
        points.reserveCapacity((count - 1) * 60)

        for seg in 0 ..< (count - 1) {
            for min in 0 ..< 60 {
                let t    = Double(min) / 60.0
                let temp = catmullRom(values: temperatures, segment: seg, t: t)
                let hum  = catmullRom(values: humidities,  segment: seg, t: t).clamped(0, 100)
                let wind = catmullRom(values: windSpeeds,  segment: seg, t: t).clamped(0, .infinity)

                let minuteDate = anchorDate.addingTimeInterval(Double(seg * 60 + min) * 60)
                let uv = computeUV(
                    at: minuteDate,
                    latitude: latitude,
                    longitude: longitude,
                    dailyMaxUV: dailyMaxUV,
                    cloudCoverPercent: cloudCoverPercent,
                    noonSinPow: noonSinPow
                )

                points.append(MinutePoint(
                    minuteOffset: seg * 60 + min,
                    date: minuteDate,
                    temperature: temp,
                    humidity: hum,
                    windSpeed: wind,
                    uvIndex: uv
                ))
            }
        }
        return points
    }

    // MARK: - Public: UV Minute Model (FAZ 4)

    /// Returns the UV index for any single minute, using `AstronomicalEngine`
    /// for the solar altitude and a cloud-cover attenuation factor.
    ///
    /// Use `interpolate(...)` for bulk computation — it amortises the
    /// solar-noon normalisation across all minutes.
    ///
    /// - Parameters:
    ///   - date:               The exact minute to evaluate.
    ///   - latitude:           Observer latitude.
    ///   - longitude:          Observer longitude.
    ///   - dailyMaxUV:         Forecast daily-peak UV index.
    ///   - cloudCoverPercent:  Current cloud cover (0–100).
    /// - Returns: UV index ∈ [0, dailyMaxUV]. Returns 0 when the sun is below
    ///            the horizon.
    static func minuteUVIndex(
        at date: Date,
        latitude: Double,
        longitude: Double,
        dailyMaxUV: Double,
        cloudCoverPercent: Double
    ) -> Double {
        let noonSinPow = solarNoonSinPow(anchorDate: date,
                                         latitude: latitude,
                                         longitude: longitude)
        return computeUV(
            at: date,
            latitude: latitude,
            longitude: longitude,
            dailyMaxUV: dailyMaxUV,
            cloudCoverPercent: cloudCoverPercent,
            noonSinPow: noonSinPow
        )
    }

    // MARK: - Private: UV computation

    /// sin(α_noon)^0.7 — the denominator of the UV normalisation formula.
    /// Computed once per batch to avoid repeated AstronomicalEngine calls.
    private static func solarNoonSinPow(anchorDate: Date,
                                        latitude: Double,
                                        longitude: Double) -> Double {
        guard latitude.isFinite, longitude.isFinite else { return 1 }
        let timing   = AstronomicalEngine.sunTiming(at: anchorDate,
                                                    latitude: latitude,
                                                    longitude: longitude)
        // Solar noon ≈ midpoint between sunrise and sunset.
        let noonDate = timing.sunrise.addingTimeInterval(timing.duration / 2)
        let noonAlt  = AstronomicalEngine.sunAltitude(at: noonDate,
                                                      latitude: latitude,
                                                      longitude: longitude)
        return pow(sin(max(0, noonAlt) * .pi / 180.0), 0.7)
            .clamped(1e-6, 1)   // avoid ÷0 at polar night
    }

    /// Core UV computation.
    ///
    /// UV(t) = UV_max · [sin(α(t)) / sin(α_noon)]^0.7 · cloudAttenuation
    private static func computeUV(
        at date: Date,
        latitude: Double,
        longitude: Double,
        dailyMaxUV: Double,
        cloudCoverPercent: Double,
        noonSinPow: Double
    ) -> Double {
        guard dailyMaxUV > 0 else { return 0 }

        let altitude = AstronomicalEngine.sunAltitude(at: date,
                                                      latitude: latitude,
                                                      longitude: longitude)
        guard altitude > 0 else { return 0 }   // sun below horizon

        let sinPow      = pow(sin(altitude * .pi / 180.0), 0.7)
        let solarFactor = (sinPow / noonSinPow).clamped(0, 1)

        // WMO cloud-attenuation model (Green et al., 1994):
        // reduces UV by up to 75 % at overcast (100 % cloud cover).
        let cover            = (cloudCoverPercent / 100.0).clamped(0, 1)
        let cloudAttenuation = 1.0 - 0.75 * pow(cover, 3.4)

        return (dailyMaxUV * solarFactor * cloudAttenuation).clamped(0, dailyMaxUV)
    }

    // MARK: - Private: Catmull-Rom Spline

    /// Evaluates one Catmull-Rom segment at normalised parameter t ∈ [0, 1].
    ///
    /// Uses clamped-endpoint ghost points at the array edges so the spline
    /// passes through the first and last real knot without overshoot artifacts.
    ///
    /// Standard uniform Catmull-Rom recurrence:
    /// ```
    /// q(t) = ½ · ( 2P₁
    ///            + (−P₀ + P₂)·t
    ///            + (2P₀ − 5P₁ + 4P₂ − P₃)·t²
    ///            + (−P₀ + 3P₁ − 3P₂ + P₃)·t³ )
    /// ```
    private static func catmullRom(values: [Double], segment: Int, t: Double) -> Double {
        let n  = values.count
        let p0 = values[max(0,     segment - 1)]
        let p1 = values[segment]
        let p2 = values[min(n - 1, segment + 1)]
        let p3 = values[min(n - 1, segment + 2)]

        let t2 = t * t
        let t3 = t2 * t

        return 0.5 * (
              (2 * p1)
            + (-p0 + p2)                    * t
            + (2*p0 - 5*p1 + 4*p2 - p3)    * t2
            + (-p0 + 3*p1 - 3*p2 + p3)     * t3
        )
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max(self, lo), hi)
    }
}
