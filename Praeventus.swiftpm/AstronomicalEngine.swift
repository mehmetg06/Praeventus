import Foundation

enum MoonPhase: Equatable, Hashable, CaseIterable {
    case newMoon, waxingCrescent, firstQuarter, waxingGibbous, fullMoon, waningGibbous, lastQuarter, waningCrescent

    /// Representative position in the 0…1 synodic cycle (new → full → new),
    /// used when the developer sandbox overrides the live phase.
    var cyclePosition: Double {
        switch self {
        case .newMoon:        return 0.0
        case .waxingCrescent: return 0.125
        case .firstQuarter:   return 0.25
        case .waxingGibbous:  return 0.375
        case .fullMoon:       return 0.5
        case .waningGibbous:  return 0.625
        case .lastQuarter:    return 0.75
        case .waningCrescent: return 0.875
        }
    }

    var displayName: String {
        switch self {
        case .newMoon: return String(localized: "moonPhase.new", defaultValue: "New Moon")
        case .waxingCrescent: return String(localized: "moonPhase.waxingCrescent", defaultValue: "Waxing Crescent")
        case .firstQuarter: return String(localized: "moonPhase.firstQuarter", defaultValue: "First Quarter")
        case .waxingGibbous: return String(localized: "moonPhase.waxingGibbous", defaultValue: "Waxing Gibbous")
        case .fullMoon: return String(localized: "moonPhase.full", defaultValue: "Full Moon")
        case .waningGibbous: return String(localized: "moonPhase.waningGibbous", defaultValue: "Waning Gibbous")
        case .lastQuarter: return String(localized: "moonPhase.lastQuarter", defaultValue: "Last Quarter")
        case .waningCrescent: return String(localized: "moonPhase.waningCrescent", defaultValue: "Waning Crescent")
        }
    }
}

struct AstronomicalAnalysis: Equatable {
    let moonPhase: MoonPhase
    let moonBrightness: Double
    let daylightHours: Double
    let sunAltitude: Double
    let sunriseSunset: SunTiming
    /// Timezone of the observed location. DST-aware when the backend's real
    /// IANA-derived UTC offset was supplied; otherwise a longitude-only
    /// approximation (used for Lab/simulated locations with no live offset).
    let locationTimezone: TimeZone

    static func == (lhs: AstronomicalAnalysis, rhs: AstronomicalAnalysis) -> Bool {
        lhs.moonPhase == rhs.moonPhase &&
        lhs.moonBrightness == rhs.moonBrightness &&
        lhs.daylightHours == rhs.daylightHours &&
        lhs.sunAltitude == rhs.sunAltitude &&
        lhs.sunriseSunset == rhs.sunriseSunset &&
        lhs.locationTimezone == rhs.locationTimezone
    }
}

struct SunTiming: Equatable {
    let sunrise: Date
    let sunset: Date

    var duration: TimeInterval {
        sunset.timeIntervalSince(sunrise)
    }
}

enum AstronomicalEngine {

    /// - Parameter utcOffsetSeconds: The location's real, DST-aware UTC offset
    ///   (from the backend's IANA timezone lookup), when available. Falls back
    ///   to a longitude/15° approximation — which ignores DST and political
    ///   timezone boundaries — only when no live offset has been loaded yet
    ///   (e.g. Lab/simulated locations).
    static func analyze(at date: Date, latitude: Double, longitude: Double, utcOffsetSeconds: Int? = nil) -> AstronomicalAnalysis {
        let phase = moonPhase(at: date)
        let brightness = moonBrightness(at: date)
        let altitude = sunAltitude(at: date, latitude: latitude, longitude: longitude)
        let timing = sunTiming(at: date, latitude: latitude, longitude: longitude)
        let daylight = timing.duration / 3600
        let tzOffset = utcOffsetSeconds ?? Int(round(longitude / 15.0)) * 3600
        let locationTimezone = TimeZone(secondsFromGMT: tzOffset) ?? .current

        return AstronomicalAnalysis(
            moonPhase: phase,
            moonBrightness: brightness,
            daylightHours: daylight,
            sunAltitude: altitude,
            sunriseSunset: timing,
            locationTimezone: locationTimezone
        )
    }

    // MARK: - Moon Phase Calculation

    static func moonPhase(at date: Date) -> MoonPhase {
        let illumination = moonIllumination(at: date)

        switch illumination {
        case 0..<0.0625: return .newMoon
        case 0.0625..<0.1875: return .waxingCrescent
        case 0.1875..<0.3125: return .firstQuarter
        case 0.3125..<0.4375: return .waxingGibbous
        case 0.4375..<0.5625: return .fullMoon
        case 0.5625..<0.6875: return .waningGibbous
        case 0.6875..<0.8125: return .lastQuarter
        case 0.8125...: return .waningCrescent
        default: return .newMoon
        }
    }

    static func moonBrightness(at date: Date) -> Double {
        moonIllumination(at: date)
    }

    private static func moonIllumination(at date: Date) -> Double {
        let knownNewMoon = Date(timeIntervalSince1970: 947182800)

        let timeSinceNewMoon = date.timeIntervalSince(knownNewMoon)
        let daysSinceNewMoon = timeSinceNewMoon / (24 * 3600)
        let cyclePosition = daysSinceNewMoon.truncatingRemainder(dividingBy: 29.530588)

        return cyclePosition / 29.530588
    }

    // MARK: - Sun Calculations

    static func sunAltitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        // Number of days since J2000 (2000-01-01 12:00:00 UTC)
        let d = (date.timeIntervalSince1970 - 946728000.0) / 86400.0

        let phi = latitude.toRadians()

        // Solar Mean Anomaly
        let M = (357.5291 + 0.98560028 * d).toRadians()

        // Equation of Center
        let C = (1.9148 * sin(M) + 0.02 * sin(2 * M) + 0.0003 * sin(3 * M)).toRadians()

        // Perihelion of the Earth and Ecliptic Longitude
        let P = 102.9372.toRadians()
        let L = M + C + P + .pi

        // Obliquity of the Earth
        let e = 23.4397.toRadians()

        // Sun Declination & Right Ascension
        let dec = asin(sin(e) * sin(L))
        let ra = atan2(sin(L) * cos(e), cos(L))

        // Sidereal Time
        let lw = -longitude.toRadians()
        let H = (280.16 + 360.9856235 * d).toRadians() - lw - ra

        // Altitude
        let altitude = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H))

        return max(-90, min(90, altitude.toDegrees()))
    }

    static func sunTiming(at date: Date, latitude: Double, longitude: Double) -> SunTiming {
        let sunrise = calculateSunriseTime(date: date, latitude: latitude, longitude: longitude, isRise: true)
        let sunset = calculateSunriseTime(date: date, latitude: latitude, longitude: longitude, isRise: false)
        return SunTiming(sunrise: sunrise, sunset: sunset)
    }

    private static func calculateSunriseTime(date: Date, latitude: Double, longitude: Double, isRise: Bool) -> Date {
        // Extract the local calendar date at the target location (not device timezone).
        let tzOffset = Int(round(longitude / 15.0)) * 3600
        let locationTZ = TimeZone(secondsFromGMT: tzOffset) ?? .current
        var locationCalendar = Calendar(identifier: .gregorian)
        locationCalendar.timeZone = locationTZ
        let components = locationCalendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year, let month = components.month, let day = components.day else {
            return date
        }

        let zenith = 90.833
        let N_int = dayOfYear(year: year, month: month, day: day)
        let N = Double(N_int)
        let lngHour = longitude / 15.0
        // t is the approximate fractional Julian day of the event in UTC.
        let t = isRise ? N + (6.0 - lngHour) / 24.0 : N + (18.0 - lngHour) / 24.0
        // The UTC calendar day differs from the local day N by this offset
        // (e.g. -1 for eastern-hemisphere sunrise whose UTC time falls on the previous day).
        let utcDayOffset = Int(floor(t)) - N_int

        let M = 0.9856 * t - 3.289
        var L = (M + 1.916 * sin(M.toRadians()) + 0.020 * sin((2 * M).toRadians()) + 282.634)
        L = fmod(L, 360)
        if L < 0 { L += 360 }

        var RA = atan(0.91764 * tan(L.toRadians())).toDegrees()
        if RA < 0 { RA += 360 }
        // Right ascension must land in the same quadrant as the Sun's true
        // longitude L; nudge it by the difference of their quadrants.
        let lQuadrant = floor(L / 90) * 90
        let raQuadrant = floor(RA / 90) * 90
        RA = RA + (lQuadrant - raQuadrant)
        RA = RA / 15.0

        let sinDec = 0.39782 * sin(L.toRadians())
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(zenith.toRadians()) - sinDec * sin(latitude.toRadians())) / (cosDec * cos(latitude.toRadians()))

        if cosH > 1 {
            return Date.distantFuture
        } else if cosH < -1 {
            return Date.distantPast
        }

        var H = isRise ? 360 - acos(cosH).toDegrees() : acos(cosH).toDegrees()
        H = H / 15.0

        let T = H + RA - 0.06571 * t - 6.622
        var UT = fmod(T - lngHour, 24)
        if UT < 0 { UT += 24 }

        // Build the result as the correct UTC Date: midnight UTC of the local date,
        // shifted by utcDayOffset days, then UT hours added.
        var midnightComponents = DateComponents()
        midnightComponents.year = year
        midnightComponents.month = month
        midnightComponents.day = day
        midnightComponents.hour = 0
        midnightComponents.minute = 0
        midnightComponents.second = 0
        midnightComponents.timeZone = TimeZone(identifier: "UTC")

        guard let midnightUTC = Calendar(identifier: .gregorian).date(from: midnightComponents) else {
            return date
        }
        let utcSeconds = Double(utcDayOffset) * 86400.0 + UT * 3600.0
        return midnightUTC.addingTimeInterval(utcSeconds)
    }

    private static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        let isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        let daysInMonths = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return daysInMonths[0..<month-1].reduce(0, +) + day
    }
}

extension Double {
    fileprivate func toRadians() -> Double {
        self * .pi / 180.0
    }

    fileprivate func toDegrees() -> Double {
        self * 180.0 / .pi
    }
}
