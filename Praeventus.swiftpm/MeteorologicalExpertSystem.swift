import Foundation

/// On-device meteorological expert system that turns raw atmospheric numbers
/// into a single, self-consistent natural-language verdict.
///
/// Foundation-only (no SwiftUI, no network, no LLM), so it compiles and runs on
/// the macOS/Linux CLI alongside the rest of the data + domain layer and uses
/// only the CPU. The design has two stages:
///
///   1. `AtmosphericDynamics` quantifies what the air is *doing* — apparent
///      temperature (heat index / wind chill), the dew-point mugginess load,
///      the hourly temperature gradient and its acceleration, and an inferred
///      barometric tendency. These are the variables a forecaster reasons over,
///      not the headline thermometer reading.
///
///   2. `MeteorologicalExpertSystem.narrative(for:)` runs a large pattern-match
///      matrix over those variables. Each meaningful combination returns its
///      own hand-written Turkish paragraph, so the output never contradicts
///      itself (e.g. "it is cooling" and "heat danger continues" are reconciled
///      into one sentence rather than glued together). The matrix is structured
///      so it is exhaustive without falling back to a generic `default`.
///
/// All user-facing copy here is intentionally Turkish and shown verbatim,
/// matching the established convention in `ThermalPredictionEngine`.

// MARK: - Classified atmospheric states (associated values carry the magnitude)

/// Where the apparent temperature sits, after humidity and wind corrections.
enum ThermalRegime: Equatable {
    case extremeCold    // apparent <= -10 °C: frostbite territory
    case frost          // -10 < apparent <= 0 °C: freezing / "ayaz"
    case cold           // 0 < apparent <= 8 °C
    case cool           // 8 < apparent <= 16 °C
    case mild           // 16 < apparent <= 24 °C
    case warm           // 24 < apparent <= 32 °C
    case hot            // 32 < apparent < 41 °C, dry-ish air
    case oppressive     // 32 °C+ apparent with a high dew point (muggy)
    case extremeHeat    // apparent >= 41 °C: heat-stroke pressure
}

/// Barometric tendency. With no stored 3-hour pressure history, this is
/// *inferred* (dP/dt estimate, hPa per hour) from the current pressure regime,
/// the near-term precipitation-probability gradient and atmospheric instability
/// — the same corroborating signals a barometer-watcher would weigh.
enum PressureTendency: Equatable {
    case fallingFast(perHour: Double)   // front / storm system bearing down
    case falling(perHour: Double)
    case steady
    case rising(perHour: Double)
    case risingFast(perHour: Double)    // ridge building, clearing and drying

    var isFalling: Bool {
        switch self {
        case .fallingFast, .falling: return true
        default: return false
        }
    }
}

/// Rate of change of the air temperature over the next few hours (°C/hour),
/// derived from the hourly series rather than a single before/after pair.
enum TemperatureGradient: Equatable {
    case plunging(perHour: Double)   // <= -2 °C/h
    case cooling(perHour: Double)    // -2 .. -0.6 °C/h
    case steady                      // within ±0.6 °C/h
    case warming(perHour: Double)    // 0.6 .. 2 °C/h
    case surging(perHour: Double)    // >= +2 °C/h
}

/// Co-occurring hazards. Modelled as an `OptionSet` because several can be live
/// at once (e.g. heat stress *and* a falling barometer) and the narrative needs
/// to reason over the combination, not a single dominant flag.
struct WeatherHazard: OptionSet {
    let rawValue: Int

    static let heatStress       = WeatherHazard(rawValue: 1 << 0)
    static let mugginess        = WeatherHazard(rawValue: 1 << 1)  // high dew point
    static let dryHeat          = WeatherHazard(rawValue: 1 << 2)  // hot + very low humidity
    static let windChill        = WeatherHazard(rawValue: 1 << 3)
    static let frostbite        = WeatherHazard(rawValue: 1 << 4)
    static let uvBurn           = WeatherHazard(rawValue: 1 << 5)
    static let stormApproaching = WeatherHazard(rawValue: 1 << 6)  // falling barometer
    static let gustWind         = WeatherHazard(rawValue: 1 << 7)
    static let lowVisibility    = WeatherHazard(rawValue: 1 << 8)
    static let deceptiveCooling = WeatherHazard(rawValue: 1 << 9)  // numbers drop, sun still bites
}

// MARK: - Computed dynamics

/// The quantitative substrate the expert system reasons over.
struct AtmosphericDynamics: Equatable {
    let regime: ThermalRegime
    let pressureTendency: PressureTendency
    let temperatureGradient: TemperatureGradient
    let hazards: WeatherHazard

    /// True air temperature (°C).
    let ambient: Double
    /// Apparent temperature after humidity / wind corrections (°C).
    let thermalIndex: Double
    /// Degrees the humidity *adds* above ambient (heat-index excess, ≥ 0).
    let humidexExcess: Double
    /// Degrees the wind *subtracts* below ambient (wind-chill drop, ≥ 0).
    let windChillDrop: Double
    /// Whether the temperature change is accelerating (vs. easing off).
    let gradientAccelerating: Bool

    let dewPoint: Double
    let humidity: Double
    let windSpeed: Double
    let windGust: Double
    let uvIndex: Int
    let rainProbability: Double

    /// Builds the dynamics from a snapshot plus the hourly series and the
    /// atmospheric-engine scalars. Kept Foundation-only and primitive-typed so
    /// it can be exercised headlessly.
    static func from(
        weather: WeatherData,
        hourly: [HourlyPoint],
        instability: Double,
        stormScore: Double,
        visibilityPoor: Bool,
        isDaytime: Bool
    ) -> AtmosphericDynamics {
        let t = weather.temperature
        let h = weather.humidity
        let wind = weather.windSpeed

        // --- Apparent temperature: heat index when warm, wind chill when cold.
        let hotApparent = ThermalPredictionEngine.heatIndex(temperatureC: t, humidity: h)
        let coldApparent = ThermalPredictionEngine.windChillIndex(temperatureC: t, windSpeedKmh: wind)
        let thermalIndex: Double = t >= 27 ? hotApparent : (t <= 10 ? coldApparent : t)
        let humidexExcess = max(0, hotApparent - t)
        let windChillDrop = max(0, t - coldApparent)

        // --- Temperature gradient (°C/h) and its acceleration, from the series.
        let temps = hourly.prefix(4).map(\.temperature)
        let gradient = Self.gradient(from: Array(temps))
        let accelerating = Self.isAccelerating(Array(temps))

        // --- Inferred barometric tendency.
        let tendency = Self.inferPressureTendency(
            pressure: weather.pressure,
            rainNow: weather.rainProbability,
            hourly: hourly,
            instability: instability,
            stormScore: stormScore
        )

        // --- Hazard flags.
        var hazards: WeatherHazard = []
        if thermalIndex >= 32 { hazards.insert(.heatStress) }
        if weather.dewPoint >= 20 { hazards.insert(.mugginess) }
        if t >= 33 && h < 25 { hazards.insert(.dryHeat) }
        if windChillDrop >= 3 && t <= 10 { hazards.insert(.windChill) }
        if thermalIndex <= -10 { hazards.insert(.frostbite) }
        if weather.uvIndex >= 6 && isDaytime { hazards.insert(.uvBurn) }
        if tendency.isFalling { hazards.insert(.stormApproaching) }
        if weather.windGustSpeed >= 50 || wind >= 45 { hazards.insert(.gustWind) }
        if visibilityPoor { hazards.insert(.lowVisibility) }
        // "False cooling": the readout is dropping but heat + sun still bite.
        if case .cooling = gradient, thermalIndex >= 30, weather.uvIndex >= 6, isDaytime {
            hazards.insert(.deceptiveCooling)
        }
        if case .plunging = gradient, thermalIndex >= 30, weather.uvIndex >= 6, isDaytime {
            hazards.insert(.deceptiveCooling)
        }

        let regime = Self.regime(thermalIndex: thermalIndex, dewPoint: weather.dewPoint)

        return AtmosphericDynamics(
            regime: regime,
            pressureTendency: tendency,
            temperatureGradient: gradient,
            hazards: hazards,
            ambient: t,
            thermalIndex: thermalIndex,
            humidexExcess: humidexExcess,
            windChillDrop: windChillDrop,
            gradientAccelerating: accelerating,
            dewPoint: weather.dewPoint,
            humidity: h,
            windSpeed: wind,
            windGust: weather.windGustSpeed,
            uvIndex: weather.uvIndex,
            rainProbability: weather.rainProbability
        )
    }

    // MARK: Classification helpers

    private static func regime(thermalIndex apparent: Double, dewPoint: Double) -> ThermalRegime {
        switch apparent {
        case 41...:        return .extremeHeat
        case 32..<41:      return dewPoint >= 22 ? .oppressive : .hot
        case 24..<32:      return .warm
        case 16..<24:      return .mild
        case 8..<16:       return .cool
        case 0..<8:        return .cold
        case -10..<0:      return .frost
        default:           return .extremeCold
        }
    }

    private static func gradient(from temps: [Double]) -> TemperatureGradient {
        guard temps.count >= 2, let first = temps.first, let last = temps.last else { return .steady }
        let perHour = (last - first) / Double(temps.count - 1)
        switch perHour {
        case ..<(-2.0):        return .plunging(perHour: perHour)
        case -2.0 ..< -0.6:    return .cooling(perHour: perHour)
        case -0.6 ..< 0.6:     return .steady
        case 0.6 ..< 2.0:      return .warming(perHour: perHour)
        default:               return .surging(perHour: perHour)
        }
    }

    /// True when the second half of the window changes faster than the first —
    /// i.e. the trend is gaining momentum rather than levelling off.
    private static func isAccelerating(_ temps: [Double]) -> Bool {
        guard temps.count >= 3 else { return false }
        let firstStep = temps[1] - temps[0]
        let lastStep = temps[temps.count - 1] - temps[temps.count - 2]
        return (firstStep * lastStep > 0) && abs(lastStep) > abs(firstStep)
    }

    /// Inferred dP/dt (hPa per hour) bucketed into a tendency. Negative ⇒ the
    /// barometer is falling, the classic signature of an approaching front.
    private static func inferPressureTendency(
        pressure: Double,
        rainNow: Double,
        hourly: [HourlyPoint],
        instability: Double,
        stormScore: Double
    ) -> PressureTendency {
        let deviation = pressure - 1013.25
        let rainSoon = hourly.prefix(6).map(\.precipitationProbability).max() ?? rainNow
        let rainTrend = rainSoon - rainNow   // -100 … +100 (percentage points)

        // Estimate over a 3-hour window, then normalise to per-hour.
        var per3h = 0.0
        per3h -= instability * 5.0                       // unstable air ⇒ falling
        per3h -= stormScore * 3.0                        // convective drop
        per3h -= max(0, rainTrend) / 100.0 * 4.0         // rain ramping up ⇒ falling
        per3h += max(0, -rainTrend) / 100.0 * 2.0        // rain easing ⇒ slight recovery
        per3h += (deviation / 8.0).clampedTendency       // ridge vs. trough bias

        let perHour = per3h / 3.0
        switch per3h {
        case ..<(-6.0):    return .fallingFast(perHour: perHour)
        case -6.0 ..< -2.0: return .falling(perHour: perHour)
        case -2.0 ..< 2.0:  return .steady
        case 2.0 ..< 6.0:   return .rising(perHour: perHour)
        default:            return .risingFast(perHour: perHour)
        }
    }
}

private extension Double {
    /// Clamps the pressure-deviation bias so an extreme reading can't dominate
    /// the inferred tendency on its own.
    var clampedTendency: Double { Swift.max(-4.0, Swift.min(4.0, self)) }
}

// MARK: - The narrative matrix

enum MeteorologicalExpertSystem {

    /// Single Turkish paragraph describing the reconciled state of the air.
    /// Dispatches on the thermal regime, then pattern-matches pressure tendency,
    /// temperature gradient, wind and precipitation. No generic `default` is
    /// used: every regime exhausts the pressure-tendency space explicitly.
    static func narrative(for dyn: AtmosphericDynamics) -> String {
        switch dyn.regime {
        case .extremeHeat: return extremeHeat(dyn)
        case .oppressive:  return oppressive(dyn)
        case .hot:         return hot(dyn)
        case .warm:        return warm(dyn)
        case .mild:        return mild(dyn)
        case .cool:        return cool(dyn)
        case .cold:        return cold(dyn)
        case .frost:       return frost(dyn)
        case .extremeCold: return extremeCold(dyn)
        }
    }

    // MARK: Extreme heat (apparent >= 41 °C)

    private static func extremeHeat(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())
        let wind = Int(d.windSpeed.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (_, .cooling) where d.hazards.contains(.deceptiveCooling),
             (_, .plunging) where d.hazards.contains(.deceptiveCooling):
            return "Termometre \(amb)°C'den birkaç derece düşüyor olabilir, ancak bu yalancı bir serinleme. Güneş hâlâ tepede ve UV radyasyonu yakıcı; vücudun ısı yükü hissedilen \(feels)°C seviyesinde devam ediyor. Sayıların gerilemesine aldanmayın, gölgeye geçin ve doğrudan güneşe çıkmayın."
        case (.fallingFast, _) where d.hazards.contains(.mugginess):
            return "Hava bunaltıcı sıcak ve hissedilen sıcaklık \(feels)°C'ye dayanıyor; üstelik basınç hızla düşüyor. Yüksek nem terlemenin soğutmasını engellerken, çöken barometre yaklaşan şiddetli bir cephe sistemini işaret ediyor. Önce aşırı sıcağa, ardından ani fırtınaya karşı hazırlıklı olun."
        case (.fallingFast, _), (.falling, _):
            return "Hissedilen sıcaklık \(feels)°C ile ölümcül eşikte ve basınç düşüyor. Bu kavurucu sıcağın üzerine yaklaşan bir hava değişimi ekleniyor; gün içinde patlak verebilecek sağanak öncesi atmosfer iyice gerginleşiyor. Açık havada bulunmayın, serin ve kapalı alanda kalın."
        case (.steady, .surging), (.steady, .warming),
             (.rising, .surging), (.rising, .warming), (.risingFast, _):
            return "Hava hissedilen \(feels)°C ile tehlikeli sıcak ve hâlâ ısınıyor; yüksek basınç sıcak hava kütlesini yerinde tutuyor. Bu kararlı, kızgın kubbe altında gölge bile yetersiz kalır. Fiziksel eforu tamamen erteleyin, bol sıvı alın ve serinde kalın."
        case (.steady, _):
            return "Hissedilen sıcaklık \(feels)°C ile sıcak çarpması sınırında ve atmosfer durağan; ne rüzgâr ne basınç değişimi bir rahatlama getiriyor (\(wind) km/s esinti dahi sıcak hava akımı gibi). Güneşin en dik olduğu saatlerde kesinlikle dışarı çıkmayın."
        case (.rising, _):
            return "Hissedilen sıcaklık \(feels)°C ile aşırı yüksek; basınç toparlanıyor, yani gökyüzü açık ve güneş radyasyonu tam güçte kalacak. Serinleme beklemeyin, kapalı ve serin bir ortamı tercih edin, su tüketimini artırın."
        }
    }

    // MARK: Oppressive (hot + muggy: apparent 32–41 °C, dew point >= 22 °C)

    private static func oppressive(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())
        let dp = Int(d.dewPoint.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (.fallingFast, _), (.falling, _):
            return "Termometre \(amb)°C gösterse de çiy noktası \(dp)°C'ye çıkmış bunaltıcı bir nem var ve basınç düşüyor; yaklaşan bir fırtına hissediliyor. Bu nemde ter buharlaşamadığı için vücut hissedilen \(feels)°C'yi taşıyor. Hem boğucu sıcağa hem de patlayabilecek gök gürültülü sağanağa karşı tedbirli olun."
        case (.steady, .surging), (.steady, .warming),
             (.rising, .surging), (.rising, .warming):
            return "Hava \(amb)°C ama çiy noktası \(dp)°C ile havayı boğucu kılıyor ve sıcaklık hâlâ tırmanıyor. Yükselen basınç bu nemli sıcak kütleyi üzerinizde sabitliyor; hissedilen \(feels)°C giderek ağırlaşacak. Gölge ve serin mola şart, ağır eforu erteleyin."
        case (.steady, .plunging), (.steady, .cooling),
             (.rising, .plunging), (.rising, .cooling), (.risingFast, _):
            return "Sıcaklık \(amb)°C'den geriliyor, fakat çiy noktası \(dp)°C'de kaldığı için hava hâlâ boğucu; nem, gerilemeyi gerçek bir ferahlığa çevirmiyor. Hissedilen değer \(feels)°C civarında ağır seyrediyor. Yine de gölgede ve sıvı alarak ilerleyin."
        case (.steady, _):
            return "Hava \(amb)°C, ancak \(dp)°C çiy noktasıyla yapışkan ve boğucu bir nem hâkim; atmosfer durağan, ne rüzgâr ne basınç değişimi nemi dağıtıyor. Hissedilen sıcaklık \(feels)°C ile gerçek değerin epey üzerinde. Terleme yetersiz soğuttuğu için temkinli olun."
        case (.rising, _):
            return "Hava \(amb)°C ve çiy noktası \(dp)°C ile bunaltıcı; basınç yükselip nemli kütleyi yerinde tutuyor, yani boğuculuk inatçı olacak. Hissedilen \(feels)°C'de evaporatif serinleme zayıf çalışıyor; bol su için ve serinde kalın."
        }
    }

    // MARK: Hot, drier air (apparent 32–41 °C, dew point < 22 °C)

    private static func hot(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())
        let wind = Int(d.windSpeed.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (_, .cooling) where d.hazards.contains(.deceptiveCooling),
             (_, .plunging) where d.hazards.contains(.deceptiveCooling):
            return "Termometreler birkaç derece düşse de bu serinleme aldatıcı; güneş hâlâ dik ve UV yüksek, radyasyon tehlikesi sürüyor. Hissedilen sıcaklık \(feels)°C seviyesinde tutunuyor. Rakamların inişine değil, tepenizdeki yakıcı güneşe göre davranın."
        case (.fallingFast, _), (.falling, _):
            return "Hava \(amb)°C ile yakıcı sıcak ve nem düşük olsa da basınç geriliyor; kuru sıcağın ardından bir hava değişimi yaklaşıyor. Düşük nem terlemeyi hızla buharlaştırıp sizi farkında olmadan susuz bırakabilir. Hem sıcağa hem de sonrasında gelebilecek ani rüzgâr ve sağanağa hazırlıklı olun."
        case (_, _) where d.hazards.contains(.dryHeat) && d.windSpeed >= 20:
            return "Hava \(amb)°C ve nem çok düşük; üstelik \(wind) km/s'lik kuru rüzgâr serinletmek yerine cildi ve solunumu kurutuyor (Föhn/saç kurutma etkisi). Hissedilen \(feels)°C'de su kaybı sinsi ve hızlı olur. Sık sık su için, doğrudan rüzgâr ve güneşten korunun."
        case (.steady, .surging), (.steady, .warming),
             (.rising, .surging), (.rising, .warming), (.risingFast, _):
            return "Hava \(amb)°C ile kavurucu ve hâlâ ısınıyor; yüksek basınç açık gökyüzünü ve güçlü güneşi koruyor. Hissedilen sıcaklık \(feels)°C'ye doğru tırmanacak. Yoğun aktiviteyi günün serin saatlerine alın, gölge ve hidrasyonu öne çıkarın."
        case (.steady, _):
            return "Hava \(amb)°C ile yakıcı sıcak, atmosfer durağan ve kuru; basınç sabit, belirgin bir değişim sinyali yok. Hissedilen \(feels)°C'de en büyük risk fark edilmeyen su kaybı. Gölge, güneş koruyucu ve yavaş tempo bugünün önceliği."
        case (.rising, _):
            return "Hava \(amb)°C ile çok sıcak ve basınç yükseliyor; gökyüzü açılıp güneş radyasyonu tam güçte kalacak, serinleme beklemeyin. Hissedilen \(feels)°C'de bol su için, güneşin tepede olduğu saatlerde gölgeyi tercih edin."
        }
    }

    // MARK: Warm (apparent 24–32 °C)

    private static func warm(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (.fallingFast, _):
            return "Hava \(amb)°C ile hoş ölçüde sıcak, ancak basınç hızla düşüyor; konforlu bu tablonun arkasından gök gürültülü sağanak getirebilecek bir cephe yaklaşıyor. Dışarıdaki planlarınızı esnek tutun ve gökyüzündeki hızlı değişime dikkat edin."
        case (.falling, _) where d.rainProbability >= 55:
            return "Sıcaklık \(amb)°C ile keyifli, fakat basınç geriliyor ve yağış olasılığı belirginleşiyor. Önümüzdeki saatlerde sağanak ihtimali artıyor; yanınızda küçük bir yağmurluk bulundurmak yerinde olur."
        case (.falling, _):
            return "Hava \(amb)°C ile rahat bir sıcaklıkta, ama düşen basınç önümüzdeki saatlerde bulutlanma ve olası yağışın habercisi. Şimdilik keyifli; yine de hava değişimine açık olun."
        case (.steady, .surging), (.steady, .warming):
            return "Hava \(amb)°C ve ısınmaya devam ediyor; durağan, kararlı atmosferde gün ilerledikçe daha sıcak hissedilecek (hissedilen ~\(feels)°C). Açık hava planları için elverişli, sadece güneşin en güçlü saatlerinde gölgeyi kollayın."
        case (.steady, _) where d.hazards.contains(.lowVisibility):
            return "Sıcaklık \(amb)°C ile ılık, fakat yüzeydeki nem ve zayıf karışım görüşü düşürüyor; basınç sabit, ani bir değişim yok. Sıcaklık konforlu olsa da yolda görüş için ekstra dikkat ve mesafe bırakın."
        case (.steady, _):
            return "Hava \(amb)°C ile konforlu ve kararlı; basınç dengede, belirgin bir yağış ya da fırtına sinyali yok. Günlük açık hava planları için ideal bir pencere, hafif bir kıyafet yeterli olacaktır."
        case (.rising, _), (.risingFast, _):
            return "Hava \(amb)°C ile keyifli ve basınç yükseliyor; yükselen barometre açık, kararlı ve kuru bir hava demek. Önümüzdeki saatler dışarısı için güvenli görünüyor, planlarınızı rahatça yapabilirsiniz."
        }
    }

    // MARK: Mild (apparent 16–24 °C)

    private static func mild(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (.fallingFast, _), (.falling, _) where d.rainProbability >= 55:
            return "Hava \(amb)°C ile ılıman ve oldukça konforlu, ancak basınç düşüyor ve yağış sinyali güçleniyor; yaklaşan bir hava sistemi sağanak getirebilir. Keyifli bu havada bile yanınıza ince bir yağmurluk almak akıllıca olur."
        case (.falling, _):
            return "Sıcaklık \(amb)°C ile tam kıvamında ılık, fakat gerileyen basınç önümüzdeki saatlerde bulutlanmanın ve hava değişiminin habercisi. Şimdilik açık hava için ideal; gelişmeleri takip edin."
        case (.steady, _) where d.hazards.contains(.lowVisibility):
            return "Hava \(amb)°C ile ılıman ve durağan, ancak yüzey nemi yüksek ve görüş düşük; sis ya da pus yolculuğu yavaşlatabilir. Sıcaklık konforlu olsa da farların açık olması ve dikkatli sürüş önemli."
        case (.steady, .plunging), (.steady, .cooling):
            return "Hava \(amb)°C ile ılıman ve atmosfer sakin, fakat sıcaklık yavaşça düşüyor; özellikle güneş çekildikten sonra hafif serinleme hissedilebilir. Yanınıza ince bir katman almak akşam için yeterli olur."
        case (.steady, _):
            return "Hava \(amb)°C ile son derece konforlu; basınç dengede, atmosfer sakin ve belirgin bir risk sinyali yok. Açık havada vakit geçirmek için günün en elverişli koşullarından biri."
        case (.rising, _), (.risingFast, _):
            return "Hava \(amb)°C ile hoş ve basınç yükseliyor; barometrenin tırmanışı açık, kararlı ve kuru bir gökyüzünün işareti. Önümüzdeki saatler dışarısı için güvenli ve keyifli görünüyor."
        }
    }

    // MARK: Cool (apparent 8–16 °C)

    private static func cool(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let wind = Int(d.windSpeed.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (_, _) where d.hazards.contains(.lowVisibility):
            return "Hava \(amb)°C ile serin ve yüzeydeki nem görüşü düşürüyor; pus veya sis sürüş ve yürüyüşü yavaşlatabilir. Hafif bir mont ve farların açık olması; yola çıkarken ekstra süre tanıyın."
        case (.fallingFast, _), (.falling, _):
            return "Hava \(amb)°C ile serin ve basınç düşüyor; yaklaşan bir cephe bulutlanma ile birlikte yağış ve rüzgâr getirebilir. İnce bir su geçirmez katman önümüzdeki saatler için isabetli olacaktır."
        case (.steady, .plunging), (.steady, .cooling):
            return "Hava \(amb)°C ile serin ve sıcaklık kademeli düşüyor; güneş çekildikçe, özellikle gölgede daha da serin hissedilecek. Sıcak tutan bir katman, dışarıda birkaç dakikadan fazla kalacaksanız işinizi görür."
        case (.steady, _) where d.windSpeed >= 25:
            return "Hava \(amb)°C ile serin ve \(wind) km/s rüzgâr vücut ısısını hızla alıp havayı olduğundan soğuk hissettiriyor. Rüzgâr kesici bir dış katman bu koşulda belirgin fark yaratır."
        case (.steady, _):
            return "Hava \(amb)°C ile serin ama kararlı; basınç dengede, belirgin bir yağış ya da fırtına sinyali yok. Mevsim normalinde, ince bir mont ile rahat bir gün."
        case (.rising, _), (.risingFast, _):
            return "Hava \(amb)°C ile serin ve basınç yükseliyor; açılan, kuruyan gökyüzü gündüz hafif bir ısınma getirebilir ama gece açık gökyüzü altında serinleme belirginleşir. Katmanlı giyinmek günün geneli için en pratik çözüm."
        }
    }

    // MARK: Cold (apparent 0–8 °C)

    private static func cold(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())
        let wind = Int(d.windSpeed.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (_, _) where d.hazards.contains(.windChill) && d.windSpeed >= 25:
            return "Termometre \(amb)°C gösteriyor ama \(wind) km/s şiddetindeki rüzgâr ısıyı söküp alıyor; rüzgârın etkisiyle hava hissedilen \(feels)°C ile donma noktasına yaklaşıyor, ayaz var. Rüzgâr kesici giyin, açıkta kalan cildi örtün."
        case (.fallingFast, _), (.falling, _):
            return "Hava \(amb)°C ile soğuk ve basınç düşüyor; yaklaşan sistem nemi artırıp yağış, hatta yeterince soğursa karla karışık yağış getirebilir. Sıcak, su geçirmez katmanlar ve kaygan zeminlere karşı dikkat işinizi görecek."
        case (.steady, .plunging), (.steady, .cooling):
            return "Hava \(amb)°C ile soğuk ve sıcaklık daha da düşüyor; özellikle güneş battıktan sonra ayaz belirginleşecek. Birkaç katman giyin, köprü ve gölgeli yollardaki olası buzlanmaya karşı tedbirli olun."
        case (.steady, _) where d.windSpeed >= 20:
            return "Hava \(amb)°C ile soğuk ve \(wind) km/s rüzgâr soğuğu derinleştiriyor; hissedilen sıcaklık \(feels)°C'ye iniyor. Rüzgârı kesen sıcak bir dış katman bu koşulda kritik."
        case (.steady, _):
            return "Hava \(amb)°C ile soğuk ama atmosfer kararlı; basınç dengede, belirgin bir yağış sinyali yok. Sıcak tutan bir katmanla dışarısı yönetilebilir, yine de uzun süre açıkta kalmamaya özen gösterin."
        case (.rising, _), (.risingFast, _):
            return "Hava \(amb)°C ile soğuk ve basınç yükseliyor; açılan gökyüzü gündüz az ısınma sağlasa da gece radyatif soğuma ile ayaz ve don riski artar. Katmanlı giyinin, sabah saatlerinde buzlanmaya dikkat edin."
        }
    }

    // MARK: Frost (apparent -10 to 0 °C)

    private static func frost(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())
        let wind = Int(d.windSpeed.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (_, _) where d.hazards.contains(.windChill) && d.windSpeed >= 20:
            return "Termometre \(amb)°C olsa da \(wind) km/s rüzgârla hava donma noktasının altında, hissedilen \(feels)°C ile sert bir ayaz var. Bu rüzgârda açıktaki cilt hızla soğur; tüm cildi örtün, katmanlı ve rüzgâr geçirmez giyinin."
        case (.fallingFast, _), (.falling, _):
            return "Hava donma noktasında, hissedilen \(feels)°C ve basınç düşüyor; yaklaşan sistem yeterli nemle birlikte kar veya karla karışık yağış getirebilir. Yollarda buzlanma ihtimaline ve kaygan zeminlere karşı hazırlıklı olun."
        case (.steady, .plunging), (.steady, .cooling):
            return "Hava donuyor (hissedilen \(feels)°C) ve sıcaklık düşmeye devam ediyor; gece boyunca ayaz ve don sertleşecek. Sıcak katmanlar şart, açıkta kalan yüzeylerde ve yollarda buzlanmaya dikkat edin."
        case (.steady, _):
            return "Hava donma noktası civarında, hissedilen \(feels)°C ile ayazlı; atmosfer durağan, belirgin yağış sinyali yok. Soğuk inatçı; katmanlı giyinin ve uzun süre açıkta kalmaktan kaçının."
        case (.rising, _), (.risingFast, _):
            return "Hava donuyor (hissedilen \(feels)°C) ve basınç yükseliyor; açık gökyüzü gündüz çok az ısınma getirse de gece radyatif soğuma ile don güçlenir. Sabaha karşı buzlanma ve don riskine karşı tedbirli olun."
        }
    }

    // MARK: Extreme cold (apparent <= -10 °C)

    private static func extremeCold(_ d: AtmosphericDynamics) -> String {
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())
        let wind = Int(d.windSpeed.rounded())

        switch (d.pressureTendency, d.temperatureGradient) {
        case (_, _) where d.windChillDrop >= 5:
            return "Termometre \(amb)°C ama \(wind) km/s rüzgâr soğuğu ölümcül kılıyor; hissedilen sıcaklık \(feels)°C ile açıktaki ciltte dakikalar içinde donma (frostbite) riski var. Zorunlu olmadıkça dışarı çıkmayın; çıkacaksanız tüm cildi tamamen örtün."
        case (.fallingFast, _), (.falling, _):
            return "Hava aşırı soğuk, hissedilen \(feels)°C ve basınç düşüyor; yaklaşan sistem kar ve tipi getirebilir. Donma ve hipotermi riski çok yüksek, görüş kar yağışıyla düşebilir. Mümkünse seyahati erteleyin, kapalı ve sıcak kalın."
        case (.steady, .plunging), (.steady, .cooling):
            return "Hava aşırı soğuk (hissedilen \(feels)°C) ve daha da düşüyor; donma riski her geçen saat artıyor. Açıkta kalan cilt hızla zarar görür; çok katmanlı giyinin ve dışarıda geçirdiğiniz süreyi en aza indirin."
        case (.steady, _):
            return "Hava aşırı soğuk, hissedilen \(feels)°C; atmosfer durağan ama bu sıcaklıkta dahi donma ve hipotermi ciddi tehlike. Tüm cildi örtün, sıcak ve kapalı bir alanda kalmaya öncelik verin."
        case (.rising, _), (.risingFast, _):
            return "Hava aşırı soğuk (hissedilen \(feels)°C) ve basınç yükseliyor; açık gökyüzü altında gece radyatif soğuma sıcaklığı daha da düşürebilir. Donma riskine karşı tüm cildi örtün, dışarıda kısa kalın."
        }
    }
}
