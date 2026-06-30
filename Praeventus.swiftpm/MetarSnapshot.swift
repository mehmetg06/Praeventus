import Foundation

/// Aviation METAR observation mapped to a clean domain type.
/// All original aviation units are preserved (knots, inHg, statute miles, ft AGL).
/// Foundation-only — no SwiftUI import.
struct MetarSnapshot: Equatable {
    let station: String            // ICAO identifier, e.g. "LTBA"
    let observationTime: String?   // ISO-8601 or nil
    let windSpeedKt: Int?          // Wind speed in knots
    let windGustKt: Int?           // Wind gust in knots; nil = no gust reported
    let windDirection: Int?        // Degrees true; nil = variable / calm
    let altimeterInHg: Double?     // Altimeter setting in inches of mercury
    let visibilityMiles: Double?   // Prevailing visibility in statute miles
    let presentWeather: String?    // WX group string, e.g. "RA", "TSRA"
    let ceilingFt: Int?            // Lowest BKN/OVC layer in hundreds ft AGL → converted to ft
    let rawOb: String?             // Full raw METAR string if available

    // MARK: - Flight category (FAA)

    enum FlightCategory: String, Equatable {
        case vfr  = "VFR"   // Ceiling > 3000 ft AND vis > 5 SM
        case mvfr = "MVFR"  // Ceiling 1000–3000 ft OR vis 3–5 SM
        case ifr  = "IFR"   // Ceiling 500–1000 ft OR vis 1–3 SM
        case lifr = "LIFR"  // Ceiling < 500 ft OR vis < 1 SM

        var displayLabel: String { rawValue }
    }

    var flightCategory: FlightCategory {
        let vis   = visibilityMiles ?? 10.0
        let ceil  = ceilingFt ?? 99_999
        if vis < 1.0  || ceil < 500  { return .lifr }
        if vis < 3.0  || ceil < 1000 { return .ifr  }
        if vis <= 5.0 || ceil < 3000 { return .mvfr }
        return .vfr
    }

    // MARK: - Display helpers

    var windString: String {
        guard let spd = windSpeedKt else { return "Calm" }
        let dirStr: String
        if let d = windDirection, d > 0 {
            dirStr = String(format: "%03d°", d)
        } else {
            dirStr = "VRB"
        }
        if let gst = windGustKt, gst > spd {
            return "\(dirStr) \(spd)G\(gst) kt"
        }
        return "\(dirStr) \(spd) kt"
    }

    var altimeterString: String {
        guard let a = altimeterInHg else { return "—" }
        return String(format: "%.2f inHg", a)
    }

    var visibilityString: String {
        guard let v = visibilityMiles else { return "—" }
        if v >= 10 { return ">10 SM" }
        return String(format: "%.1f SM", v)
    }

    // MARK: - Factory

    static func from(raw: MetarRaw, station: String) -> MetarSnapshot {
        let ceiling: Int? = {
            guard let layers = raw.skyCondition else { return nil }
            for layer in layers {
                let cover = layer.skyCover?.uppercased() ?? ""
                if cover == "BKN" || cover == "OVC", let base = layer.cloudBase {
                    // cloudBase is already in hundreds of feet
                    return base * 100
                }
            }
            return nil
        }()

        return MetarSnapshot(
            station: station,
            observationTime: raw.reportTime,
            windSpeedKt: raw.wspd.map { Int($0) },
            windGustKt: raw.wgst.map { Int($0) },
            windDirection: raw.wdir.map { Int($0) },
            altimeterInHg: raw.altim,
            visibilityMiles: raw.visib,
            presentWeather: raw.wxString,
            ceilingFt: ceiling,
            rawOb: raw.rawOb
        )
    }
}
