#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI-only presentation for `WeatherCondition`. Kept separate from the
/// Foundation data type so the data/mapping layer stays platform-agnostic.
extension WeatherCondition {
    var palette: [Color] {
        switch self {
        case .clear:
            return [Color(red: 0.02, green: 0.28, blue: 0.84),
                    Color(red: 0.14, green: 0.60, blue: 0.98),
                    Color(red: 0.80, green: 0.94, blue: 1.0)]
        case .partlyCloudy:
            return [Color(red: 0.05, green: 0.20, blue: 0.62),
                    Color(red: 0.22, green: 0.54, blue: 0.90),
                    Color(red: 0.78, green: 0.88, blue: 0.98)]
        case .cloudy:
            return [Color(red: 0.10, green: 0.14, blue: 0.24),
                    Color(red: 0.30, green: 0.38, blue: 0.50),
                    Color(red: 0.62, green: 0.70, blue: 0.80)]
        case .rain:
            return [Color(red: 0.02, green: 0.06, blue: 0.18),
                    Color(red: 0.10, green: 0.22, blue: 0.40),
                    Color(red: 0.36, green: 0.56, blue: 0.74)]
        case .storm:
            return [Color(red: 0.01, green: 0.01, blue: 0.06),
                    Color(red: 0.06, green: 0.04, blue: 0.18),
                    Color(red: 0.24, green: 0.18, blue: 0.50)]
        case .fog:
            return [Color(red: 0.40, green: 0.46, blue: 0.54),
                    Color(red: 0.64, green: 0.72, blue: 0.78),
                    Color(red: 0.88, green: 0.90, blue: 0.92)]
        case .snow:
            return [Color(red: 0.04, green: 0.08, blue: 0.26),
                    Color(red: 0.34, green: 0.62, blue: 0.90),
                    Color(red: 0.90, green: 0.95, blue: 1.0)]
        }
    }
}
#endif
