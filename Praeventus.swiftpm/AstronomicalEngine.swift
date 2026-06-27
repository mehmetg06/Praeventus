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
}

struct SunTiming: Equatable {
    let sunrise: Date
    let sunset: Date

    var duration: TimeInterval {
        sunset.timeIntervalSince(sunrise)
    }
}

enum AstronomicalEngine {

    static func analyze(at date: Date, latitude: Double, longitude: Double) -> AstronomicalAnalysis {
        let phase = moonPhase(at: date)
        let brightness = moonBrightness(at: date)
        let altitude = sunAltitude(at: date, latitude: latitude, longitude: longitude)
        let timing = sunTiming(at: date, latitude: latitude, longitude: longitude)
        let daylight = timing.duration / 3600

        return AstronomicalAnalysis(
            moonPhase: phase,
            moonBrightness: brightness,
            daylightHours: daylight,
            sunAltitude: altitude,
            sunriseSunset: timing
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
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        guard let year = components.year, let month = components.month, let day = components.day else { return 0 }
        guard let hour = components.hour, let minute = components.minute, let second = components.second else { return 0 }

        let N = Double(dayOfYear(year: year, month: month, day: day)) + (Double(hour) + Double(minute) / 60.0 + Double(second) / 3600.0) / 24.0 - 1.0

        let J = N + 0.0008
        let M = 357.52910 + 0.98560025 * J
        let C = (1.914600 - 0.004817 * J / 36525.0 - 0.000014 * J / 36525.0 * J / 36525.0) * sin(M.toRadians())
            + (0.019993 - 0.000101 * J / 36525.0) * sin(2 * M.toRadians())
            + 0.000289 * sin(3 * M.toRadians())

        let sunLongitude = 280.46645 + 0.9856474 * J + C
        let obliquity = 23.43929111 - 0.0130041667 * (J / 36525.0)

        let alpha = atan2(sin(sunLongitude.toRadians()) * cos(obliquity.toRadians()), cos(sunLongitude.toRadians())).toDegrees()
        let delta = asin(sin(sunLongitude.toRadians()) * sin(obliquity.toRadians())).toDegrees()

        let H = getHourAngle(at: date, longitude: longitude, sunLongitude: alpha)

        let altitude = asin(sin(latitude.toRadians()) * sin(delta.toRadians())
            + cos(latitude.toRadians()) * cos(delta.toRadians()) * cos(H.toRadians())).toDegrees()

        return max(-90, min(90, altitude))
    }

    static func sunTiming(at date: Date, latitude: Double, longitude: Double) -> SunTiming {
        let sunrise = calculateSunriseTime(date: date, latitude: latitude, longitude: longitude, isRise: true)
        let sunset = calculateSunsetTime(date: date, latitude: latitude, longitude: longitude, isRise: false)

        return SunTiming(sunrise: sunrise, sunset: sunset)
    }

    private static func calculateSunriseTime(date: Date, latitude: Double, longitude: Double, isRise: Bool) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year, let month = components.month, let day = components.day else {
            return date
        }

        let zenith = 90.833
        let N = Double(dayOfYear(year: year, month: month, day: day))
        let lngHour = longitude / 15.0
        let t = isRise ? N + (6 - lngHour) / 24 : N + (18 - lngHour) / 24
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

        let hour = Int(floor(UT))
        let minute = Int(floor((UT - Double(hour)) * 60))

        var dayComponent = DateComponents()
        dayComponent.year = year
        dayComponent.month = month
        dayComponent.day = day
        dayComponent.hour = hour
        dayComponent.minute = minute
        dayComponent.second = 0
        dayComponent.timeZone = TimeZone.current

        return calendar.date(from: dayComponent) ?? date
    }

    private static func calculateSunsetTime(date: Date, latitude: Double, longitude: Double, isRise: Bool) -> Date {
        calculateSunriseTime(date: date, latitude: latitude, longitude: longitude, isRise: false)
    }

    private static func getHourAngle(at date: Date, longitude: Double, sunLongitude: Double) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        guard let hour = components.hour, let minute = components.minute, let second = components.second else {
            return 0
        }

        let localTime = Double(hour) + Double(minute) / 60.0 + Double(second) / 3600.0
        // Convert the analyzed date's wall-clock to UTC via its zone offset, so
        // altitude depends only on `date` — not on when the app happens to run.
        let utcOffsetHours = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0
        var gha = 15 * (12 - (localTime - utcOffsetHours + longitude / 15.0))
        gha = fmod(gha, 360)
        if gha < 0 { gha += 360 }

        return gha - sunLongitude
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
