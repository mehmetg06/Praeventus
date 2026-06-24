#if canImport(SwiftUI)
import SwiftUI

struct WeatherData: Equatable {
    var city: String
    var country: String
    var temperature: Double
    var feelsLike: Double
    var condition: WeatherCondition
    var humidity: Double
    var pressure: Double
    var windSpeed: Double
    var rainProbability: Double

    var statusText: String {
        switch condition {
        case .clear: return "Atmosfer Parlak"
        case .partlyCloudy: return "Atmosfer Kararlı"
        case .cloudy: return "Bulutlanma Artıyor"
        case .rain: return "Yağış Aktif"
        case .storm: return "Konvektif Risk"
        case .fog: return "Görüş Azalıyor"
        case .snow: return "Soğuk Çekirdek"
        }
    }

    var story: String {
        switch condition {
        case .clear:
            return "Basınç dengeli. Nem düşük-orta seviyede. Önümüzdeki saatlerde gökyüzü açık ve sakin kalabilir."
        case .partlyCloudy:
            return "Atmosfer genel olarak kararlı. Yerel bulutlanma oluşabilir ama güçlü bir yağış sinyali öne çıkmıyor."
        case .cloudy:
            return "Nem ve bulut örtüsü artıyor. Basınç belirgin düşmezse yağış riski sınırlı kalabilir."
        case .rain:
            return "Nem yüksek ve yağış sinyali belirgin. Kısa vadede aralıklı yağış beklenebilir."
        case .storm:
            return "Basınç düşüşü, yüksek nem ve rüzgar birleşimi atmosferi kararsızlaştırıyor. Ani sağanak ve fırtına riski izlenmeli."
        case .fog:
            return "Yüzey nemi yüksek. Rüzgar zayıf kaldığı için görüşte azalma ve sis tabakası oluşabilir."
        case .snow:
            return "Soğuk hava profili güçleniyor. Nem yeterli olursa kar veya karla karışık yağış görülebilir."
        }
    }

    static let mersin = WeatherData(
        city: "Mersin",
        country: "Türkiye",
        temperature: 31,
        feelsLike: 34,
        condition: .partlyCloudy,
        humidity: 58,
        pressure: 1014,
        windSpeed: 18,
        rainProbability: 18
    )
}

enum WeatherCondition: String, CaseIterable, Identifiable, Equatable {
    case clear = "Açık"
    case partlyCloudy = "Parçalı Bulutlu"
    case cloudy = "Bulutlu"
    case rain = "Yağmurlu"
    case storm = "Fırtınalı"
    case fog = "Sisli"
    case snow = "Karlı"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .storm: return "cloud.bolt.rain.fill"
        case .fog: return "cloud.fog.fill"
        case .snow: return "snowflake"
        }
    }

    var palette: [Color] {
        switch self {
        case .clear:
            return [Color(red: 0.18, green: 0.54, blue: 0.94), Color(red: 0.77, green: 0.91, blue: 1.0), Color(red: 1.0, green: 0.74, blue: 0.38)]
        case .partlyCloudy:
            return [Color(red: 0.06, green: 0.25, blue: 0.48), Color(red: 0.45, green: 0.72, blue: 0.92), Color(red: 0.96, green: 0.84, blue: 0.62)]
        case .cloudy:
            return [Color(red: 0.16, green: 0.23, blue: 0.34), Color(red: 0.42, green: 0.52, blue: 0.63), Color(red: 0.77, green: 0.83, blue: 0.88)]
        case .rain:
            return [Color(red: 0.03, green: 0.09, blue: 0.18), Color(red: 0.16, green: 0.32, blue: 0.47), Color(red: 0.55, green: 0.72, blue: 0.84)]
        case .storm:
            return [Color(red: 0.02, green: 0.02, blue: 0.09), Color(red: 0.11, green: 0.10, blue: 0.26), Color(red: 0.46, green: 0.43, blue: 0.72)]
        case .fog:
            return [Color(red: 0.55, green: 0.61, blue: 0.68), Color(red: 0.77, green: 0.82, blue: 0.86), Color(red: 0.95, green: 0.96, blue: 0.96)]
        case .snow:
            return [Color(red: 0.06, green: 0.17, blue: 0.32), Color(red: 0.54, green: 0.78, blue: 0.96), Color.white]
        }
    }
}
#endif
