import Foundation

/// Open-Meteo numerical weather models the app can request and blend.
///
/// Open-Meteo serves every model from the same `/v1/forecast` endpoint via the
/// `models=` query parameter. We request one model per call (un-suffixed JSON
/// keys, so the existing decoder works unchanged) and fuse the results on-device.
enum WeatherModel: String, CaseIterable, Equatable, Codable {
    case bestMatch
    case ecmwf
    case gfs
    case icon

    /// Value sent to Open-Meteo's `models=` parameter.
    var apiValue: String {
        switch self {
        case .bestMatch: return "best_match"
        case .ecmwf: return "ecmwf_ifs025"
        case .gfs: return "gfs_global"
        case .icon: return "icon_global"
        }
    }

    /// Short label for the Lab readout (e.g. "ECMWF" / "GFS").
    var displayName: String {
        switch self {
        case .bestMatch: return String(localized: "model.bestMatch", defaultValue: "Best Match")
        case .ecmwf: return String(localized: "model.ecmwf", defaultValue: "ECMWF")
        case .gfs: return String(localized: "model.gfs", defaultValue: "GFS")
        case .icon: return String(localized: "model.icon", defaultValue: "ICON")
        }
    }

    /// Models blended when multi-model fusion is enabled. ECMWF, GFS and ICON
    /// are independent global models with open commercial licenses.
    static let fusionSet: [WeatherModel] = [.ecmwf, .gfs, .icon]
}

/// UserDefaults-backed feature flags, shared by `SettingsView` (via `@AppStorage`
/// on the same keys) and `WeatherStore`.
enum WeatherSettings {
    static let multiModelKey = "praeventus.multiModelEnabled"
    static let sensorCalibrationKey = "praeventus.sensorCalibrationEnabled"

    /// Blend ECMWF/GFS/ICON on-device. On by default.
    static var multiModelEnabled: Bool {
        UserDefaults.standard.object(forKey: multiModelKey) as? Bool ?? true
    }

    /// Calibrate pressure with the device barometer. Opt-in, off by default.
    static var sensorCalibrationEnabled: Bool {
        UserDefaults.standard.object(forKey: sensorCalibrationKey) as? Bool ?? false
    }
}
