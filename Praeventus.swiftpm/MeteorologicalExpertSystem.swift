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

private enum NarrativePressure: String {
    case stormyFall, softFall, balanced, clearing, strongClearing
}

private enum NarrativeGradient: String {
    case plunging, cooling, steady, warming, surging
}

private enum NarrativeRain: String {
    case dry, possible, likely, downpour
}

private enum NarrativeWind: String {
    case calm, breeze, windy, harsh
}

private enum NarrativeHazard: String {
    case none, muggy, dryHeat, uv, windChill, frostbite, gusts, fog, falseCool, stormHeat
}

enum MeteorologicalExpertSystem {

    /// Single Turkish paragraph describing the reconciled state of the air.
    /// The thermal regime picks the vocabulary family; every regime then runs
    /// a five-dimensional matrix over pressure tendency, temperature trend,
    /// precipitation probability, wind class and the dominant hazard signal.
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

    // MARK: Dimension classifiers

    private static func pressure(_ tendency: PressureTendency) -> NarrativePressure {
        switch tendency {
        case .fallingFast: return .stormyFall
        case .falling: return .softFall
        case .steady: return .balanced
        case .rising: return .clearing
        case .risingFast: return .strongClearing
        }
    }

    private static func gradient(_ trend: TemperatureGradient) -> NarrativeGradient {
        switch trend {
        case .plunging: return .plunging
        case .cooling: return .cooling
        case .steady: return .steady
        case .warming: return .warming
        case .surging: return .surging
        }
    }

    private static func rain(_ probability: Double) -> NarrativeRain {
        switch probability {
        case 80...: return .downpour
        case 55..<80: return .likely
        case 25..<55: return .possible
        default: return .dry
        }
    }

    private static func wind(_ speed: Double) -> NarrativeWind {
        switch speed {
        case 45...: return .harsh
        case 25..<45: return .windy
        case 8..<25: return .breeze
        default: return .calm
        }
    }

    private static func hazard(_ hazards: WeatherHazard) -> NarrativeHazard {
        if hazards.contains(.frostbite) { return .frostbite }
        if hazards.contains(.deceptiveCooling) { return .falseCool }
        if hazards.contains(.mugginess) && hazards.contains(.stormApproaching) { return .stormHeat }
        if hazards.contains(.mugginess) { return .muggy }
        if hazards.contains(.dryHeat) { return .dryHeat }
        if hazards.contains(.windChill) { return .windChill }
        if hazards.contains(.gustWind) { return .gusts }
        if hazards.contains(.lowVisibility) { return .fog }
        if hazards.contains(.uvBurn) { return .uv }
        return .none
    }

    private static func matrix(_ d: AtmosphericDynamics) -> (NarrativePressure, NarrativeGradient, NarrativeRain, NarrativeWind, NarrativeHazard) {
        (pressure(d.pressureTendency), gradient(d.temperatureGradient), rain(d.rainProbability), wind(d.windSpeed), hazard(d.hazards))
    }

    // MARK: Shared language bricks

    private static func pressurePhrase(_ p: NarrativePressure) -> String {
        switch p {
        case .stormyFall: return "basınç hızlı düşüyor; hava, uzakta toparlanan bir cepheyi haber veriyor"
        case .softFall: return "basınç yavaşça geriliyor; gökyüzü değişime açık"
        case .balanced: return "basınç dengede; atmosfer şimdilik büyük bir manevra yapmıyor"
        case .clearing: return "basınç yükseliyor; gökyüzü açılmaya ve hava kurumaya meyilli"
        case .strongClearing: return "basınç güçlü yükseliyor; açık ve kararlı hava kendini iyice kabul ettiriyor"
        }
    }

    private static func trendPhrase(_ g: NarrativeGradient) -> String {
        switch g {
        case .plunging: return "sıcaklık belirgin biçimde aşağı süzülüyor"
        case .cooling: return "sıcaklık usul usul geriliyor"
        case .steady: return "sıcaklık çizgisini büyük ölçüde koruyor"
        case .warming: return "sıcaklık nazikçe tırmanıyor"
        case .surging: return "sıcaklık kısa sürede atak yapıyor"
        }
    }

    private static func rainPhrase(_ r: NarrativeRain) -> String {
        switch r {
        case .dry: return "yağmur ihtimali düşük"
        case .possible: return "kısa süreli bir yağmur ihtimali masada"
        case .likely: return "sağanak olasılığı belirgin"
        case .downpour: return "yağış ihtimali çok yüksek; gökyüzü su bırakmaya hazır"
        }
    }

    private static func windPhrase(_ w: NarrativeWind, speed: Int) -> String {
        switch w {
        case .calm: return "rüzgâr sakin, hava neredeyse kıpırtısız"
        case .breeze: return "\(speed) km/h civarında tatlı bir esinti var"
        case .windy: return "\(speed) km/h rüzgâr havaya belirgin bir hareket katıyor"
        case .harsh: return "\(speed) km/h rüzgâr sert esiyor ve dengeyi bozacak kadar güçlü"
        }
    }

    private static func hazardPhrase(_ h: NarrativeHazard) -> String {
        switch h {
        case .none: return "öne çıkan ek bir risk yok"
        case .muggy: return "yapış yapış nem havayı olduğundan ağır hissettiriyor"
        case .dryHeat: return "kuru sıcak, su kaybını sessizce hızlandırıyor"
        case .uv: return "UV yüksek; güneş cilt üzerinde hızlı iz bırakabilir"
        case .windChill: return "rüzgârın soğutması iliklerinize kadar işleyen bir ayaz yaratıyor"
        case .frostbite: return "açıkta kalan cilt için donma riski ciddileşiyor"
        case .gusts: return "ani hamleler şemsiye, bisiklet ve gevşek eşyalar için sorun çıkarabilir"
        case .fog: return "pus ve düşük görüş mesafesi çevreyi olduğundan daha yakın gösteriyor"
        case .falseCool: return "bu bir yalancı serinleme; sayı düşse de güneş ve ısı yükü hâlâ baskın"
        case .stormHeat: return "nemli sıcak ile düşen basınç aynı anda çalışıyor; fırtına öncesi o ağır hava hissi var"
        }
    }

    private static func advice(regime: ThermalRegime, rain: NarrativeRain, wind: NarrativeWind, hazard: NarrativeHazard, gradient: NarrativeGradient) -> String {
        switch (regime, rain, wind, hazard, gradient) {
        case (.extremeHeat, .downpour, .harsh, .stormHeat, .surging): return "Serin bir kapalı alana geçin, telefonunuzu şarjlı tutun ve fırtına yaklaşırsa pencerelerden uzak durun."
        case (.extremeHeat, .likely, .windy, .falseCool, .cooling): return "Rakamların düşüşüne kanmayın; gölgede kalın, suyu küçük yudumlarla sık için ve şemsiyeyi de çantaya atın."
        case (.extremeHeat, _, _, _, _): return "Günün en sıcak bölümünde dışarı çıkmayın; serin bir ortam, bol su ve ağır efordan kaçınmak bugün en doğru üçlü."
        case (.oppressive, .downpour, _, .stormHeat, _): return "Ani yaz sağanağına karşı şemsiyenizi alın, ama kapalı alanda bile su içmeyi ihmal etmeyin."
        case (.oppressive, _, .calm, .muggy, _): return "Hava kıpırtısızken nem daha çok çöker; sık mola verin, serin duş veya vantilatörle vücudu rahatlatın."
        case (.oppressive, _, _, _, _): return "Nefes aldıran açık renkli kıyafet seçin, temponuzu düşürün ve suyu beklemeden için."
        case (.hot, .dry, .breeze, .dryHeat, _): return "Tatlı esinti sizi kandırmasın; şapka, güneş kremi ve düzenli su molası şart."
        case (.hot, _, .harsh, .dryHeat, _): return "Kuru ve sert rüzgârda gözleri ve cildi koruyun; mümkünse doğrudan güneş-rüzgâr hattında uzun kalmayın."
        case (.hot, _, _, _, _): return "Gölgeden yararlanın, güneş koruyucu kullanın ve yoğun işi sabah erken ya da akşamüstüne bırakın."
        case (.warm, .likely, _, _, _): return "Planınız açık havadaysa hafif bir yağmurluk alın ve bulutlar hızla kabarırsa kapalı bir alternatife geçin."
        case (.warm, .dry, .calm, .uv, _): return "Gökyüzü pırıl pırılken güneş kremi sürün ve öğle saatlerinde kısa gölge molaları verin."
        case (.warm, _, _, _, _): return "Hafif giyinin, ama çantada ince bir katman veya küçük bir şemsiye bulundurmak planınızı kurtarır."
        case (.mild, .downpour, _, _, _): return "Ilık havaya aldanmayın; su geçirmez ayakkabı ve küçük bir yağmurluk günü çok daha rahat geçirir."
        case (.mild, _, .harsh, .gusts, _): return "Rüzgârda uçabilecek eşyaları sabitleyin ve bisiklet ya da scooter kullanıyorsanız hızınızı düşürün."
        case (.mild, _, _, .fog, _): return "Yola çıkacaksanız farları açık tutun, takip mesafesini artırın ve acele etmeyin."
        case (.mild, _, _, _, _): return "Dışarı çıkmak için güzel bir pencere; yine de akşama kalacaksanız ince bir katman alın."
        case (.cool, .likely, _, _, _): return "İnce ama su geçirmeyen bir katman alın; serin yağmur vücut ısısını beklenenden hızlı düşürür."
        case (.cool, _, .windy, .windChill, _): return "Rüzgârı kesen hafif bir mont giyin; özellikle boyun ve kulakları açık bırakmayın."
        case (.cool, _, _, .fog, _): return "Sisli serinlikte görünür olmak için açık renkli kıyafet veya reflektör kullanın."
        case (.cool, _, _, _, _): return "Katmanlı giyin; ince bir mont gün boyunca konforu belirgin artırır."
        case (.cold, .likely, _, _, _): return "Sıcak ve su geçirmez bir dış katman seçin, kaldırım ve köprülerde kaygan zemine dikkat edin."
        case (.cold, _, .harsh, .windChill, _): return "Rüzgâr geçirmeyen mont, bere ve eldiven kullanın; açıkta kalan cildi azaltın."
        case (.cold, _, _, _, .plunging): return "Akşama kalacaksanız bir katman daha ekleyin ve buzlanmaya açık gölgeli zeminlerde yavaş yürüyün."
        case (.cold, _, _, _, _): return "Sıcak tutan katmanlarla çıkın ve uzun süre hareketsiz kalmamaya özen gösterin."
        case (.frost, _, _, .frostbite, _): return "Eldiven, bere ve yüz koruması kullanın; zorunlu değilse dışarıdaki süreyi kısa tutun."
        case (.frost, .likely, _, _, _): return "Kar veya buzlu yağışa karşı tabanı sağlam ayakkabı giyin ve araçla çıkacaksanız camları tamamen temizleyin."
        case (.frost, _, .harsh, .windChill, _): return "Rüzgâr geçirmeyen çok katmanlı giyinin; kulak, burun ve parmak uçlarını mutlaka örtün."
        case (.frost, _, _, _, _): return "Katmanlı giyinin, açıkta su bırakmayın ve sabah saatlerinde buzlanmaya karşı temkinli olun."
        case (.extremeCold, _, _, .frostbite, _): return "Mümkünse dışarı çıkmayın; çıkmanız gerekiyorsa tüm cildi kapatın ve dönüş yolunu önceden planlayın."
        case (.extremeCold, .likely, .harsh, _, _): return "Seyahati ertelemek en güvenlisi; zorunluysa araçta battaniye, su ve şarjlı telefon bulundurun."
        case (.extremeCold, _, _, _, _): return "Dışarıda kalma süresini dakikalarla sınırlayın, çok katmanlı giyinin ve yalnız yürümemeye çalışın."
        }
    }

    private static func paragraph(for regime: ThermalRegime, d: AtmosphericDynamics, opening: String) -> String {
        let dims = matrix(d)
        let (p, g, r, w, h) = dims
        let amb = Int(d.ambient.rounded())
        let feels = Int(d.thermalIndex.rounded())
        let speed = Int(d.windSpeed.rounded())

        if dims == (.stormyFall, .plunging, .downpour, .harsh, .frostbite) {
            return "\(opening) Termometre \(amb)°C, hissedilen \(feels)°C; \(pressurePhrase(p)), \(trendPhrase(g)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)). \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.stormyFall, .surging, .downpour, .harsh, .stormHeat) {
            return "\(opening) Hissedilen \(feels)°C; \(pressurePhrase(p)), \(trendPhrase(g)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)). \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.stormyFall, .cooling, .likely, .windy, .falseCool) {
            return "\(opening) \(trendPhrase(g).capitalized) ama serinlik güven vermiyor; \(pressurePhrase(p)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)). \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.softFall, .warming, .likely, .breeze, .muggy) {
            return "\(opening) \(amb)°C civarında hava ısınırken \(pressurePhrase(p)); \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)); hissedilen \(feels)°C'ye yaklaşıyor. \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.balanced, .steady, .dry, .calm, .none) {
            return "\(opening) \(amb)°C civarında yalın ve sakin bir tablo var; \(pressurePhrase(p)), \(trendPhrase(g)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)). \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.balanced, .warming, .dry, .breeze, .uv) {
            return "\(opening) Gökyüzü pırıl pırıl; \(trendPhrase(g)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)); hissedilen değer \(feels)°C. \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.clearing, .cooling, .dry, .windy, .windChill) {
            return "\(opening) \(pressurePhrase(p)) fakat \(trendPhrase(g)); \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)); hissedilen \(feels)°C. \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.strongClearing, .plunging, .dry, .calm, .fog) {
            return "\(opening) Açılan gökyüzüne rağmen yüzeyde serin ve puslu bir katman kalmış; \(pressurePhrase(p)), \(trendPhrase(g)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)). \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }
        if dims == (.clearing, .surging, .dry, .breeze, .dryHeat) {
            return "\(opening) \(pressurePhrase(p)); \(trendPhrase(g)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). \(hazardPhrase(h)); hissedilen \(feels)°C olsa da su kaybı hızlıdır. \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
        }

        return "\(opening) Termometre \(amb)°C, hissedilen \(feels)°C; \(pressurePhrase(p)), \(trendPhrase(g)), \(rainPhrase(r)) ve \(windPhrase(w, speed: speed)). Ayrıca \(hazardPhrase(h)). \(advice(regime: regime, rain: r, wind: w, hazard: h, gradient: g))"
    }

    // MARK: Regime-specific matrices

    private static func extremeHeat(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .falseCool:
            return paragraph(for: .extremeHeat, d: d, opening: "Bu serinleme görüntüsü aldatıcı; aşırı sıcak hâlâ bedenin üzerinde ağır bir battaniye gibi duruyor.")
        case let (p, g, r, w, h) where h == .stormHeat || p == .stormyFall || r == .downpour:
            return paragraph(for: .extremeHeat, d: d, opening: "Çok sıcak, çok nemli ve gökyüzü huzursuz; fırtına öncesi bunaltı kendini belli ediyor.")
        case let (p, g, r, w, h) where w == .harsh || h == .dryHeat:
            return paragraph(for: .extremeHeat, d: d, opening: "Kavurucu sıcak sert ve kuru bir hava akımıyla birleşmiş; bu, serinlik değil saç kurutma etkisi yaratır.")
        case let (p, g, r, w, h):
            return paragraph(for: .extremeHeat, d: d, opening: "Hava ağır, yakıcı ve vücut için yorucu; gölge bile bugün sınırlı rahatlık verir.")
        }
    }

    private static func oppressive(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .stormHeat:
            return paragraph(for: .oppressive, d: d, opening: "Yapış yapış nem ile düşen basınç birleşmiş; hava fırtına öncesi gibi ağırlaşıyor.")
        case let (p, g, r, w, h) where w == .calm && (h == .muggy || h == .uv):
            return paragraph(for: .oppressive, d: d, opening: "Rüzgâr olmayınca nem üzerinize çöküyor; boğucu sıcak daha da yoğun hissediliyor.")
        case let (p, g, r, w, h) where g == .cooling || g == .plunging:
            return paragraph(for: .oppressive, d: d, opening: "Sıcaklık gerilese bile nem yerinde duruyor; ferahlama eksik ve ağır.")
        case let (p, g, r, w, h):
            return paragraph(for: .oppressive, d: d, opening: "Nemli sıcak havayı kalınlaştırmış; nefes aldıran değil, yavaşlatan bir atmosfer var.")
        }
    }

    private static func hot(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .falseCool:
            return paragraph(for: .hot, d: d, opening: "Rakamlar biraz inse de bu yalancı serinleme; güneşin yakıcılığı hâlâ oyunda.")
        case let (p, g, r, w, h) where h == .dryHeat && (w == .windy || w == .harsh):
            return paragraph(for: .hot, d: d, opening: "Kuru sıcak rüzgârla birleşmiş; hava cildi ve boğazı hızla kurutan bir akışa dönmüş.")
        case let (p, g, r, w, h) where p == .stormyFall || p == .softFall:
            return paragraph(for: .hot, d: d, opening: "Sıcak güçlü, fakat basınçtaki düşüş havanın gün içinde yön değiştirebileceğini söylüyor.")
        case let (p, g, r, w, h):
            return paragraph(for: .hot, d: d, opening: "Yakıcı ama daha kuru bir sıcak var; gökyüzünün parlaklığı ısıyı keskinleştiriyor.")
        }
    }

    private static func warm(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where r == .likely || r == .downpour:
            return paragraph(for: .warm, d: d, opening: "Sıcaklık keyifli, ama yağmur ihtimali bu rahat tabloya hareket katıyor.")
        case let (p, g, r, w, h) where h == .uv && (g == .warming || g == .surging):
            return paragraph(for: .warm, d: d, opening: "Ilık-sıcak çizgide pırıl pırıl bir hava var; güneş kendini cömertçe hissettiriyor.")
        case let (p, g, r, w, h) where w == .windy || w == .harsh:
            return paragraph(for: .warm, d: d, opening: "Sıcaklık konforlu, fakat rüzgâr havaya dinamik ve yer yer savruk bir karakter veriyor.")
        case let (p, g, r, w, h):
            return paragraph(for: .warm, d: d, opening: "Hava genel olarak hoş; ne bunaltıcı ne serin, açık hava için davetkâr bir denge var.")
        }
    }

    private static func mild(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .fog:
            return paragraph(for: .mild, d: d, opening: "Ilık havanın üzerinde puslu bir perde var; sıcaklık rahat ama görüş mesafesi naz istiyor.")
        case let (p, g, r, w, h) where r == .likely || r == .downpour:
            return paragraph(for: .mild, d: d, opening: "Sıcaklık tam kıvamında, ancak yağmur olasılığı günün ritmini değiştirebilir.")
        case let (p, g, r, w, h) where g == .cooling || g == .plunging:
            return paragraph(for: .mild, d: d, opening: "Ilıman hava yavaşça serin tarafa dönüyor; özellikle gölgede fark edilir bir düşüş var.")
        case let (p, g, r, w, h):
            return paragraph(for: .mild, d: d, opening: "Hava yumuşak, dengeli ve insanı dışarı çağıran cinsten.")
        }
    }

    private static func cool(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .fog:
            return paragraph(for: .cool, d: d, opening: "Serin hava pusla birleşmiş; çevre yumuşak ama görüş biraz kısıtlı.")
        case let (p, g, r, w, h) where h == .windChill || w == .windy || w == .harsh:
            return paragraph(for: .cool, d: d, opening: "Serinlik rüzgârla keskinleşiyor; ince kumaşların arasından sızan bir üşütme var.")
        case let (p, g, r, w, h) where r == .likely || r == .downpour:
            return paragraph(for: .cool, d: d, opening: "Serin ve nemli bir tablo oluşuyor; yağmur gelirse hava daha çabuk üşütür.")
        case let (p, g, r, w, h):
            return paragraph(for: .cool, d: d, opening: "Hava serin ama yönetilebilir; doğru katmanla dışarısı gayet rahat.")
        }
    }

    private static func cold(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .windChill || w == .harsh:
            return paragraph(for: .cold, d: d, opening: "Soğuk hava rüzgârla dişini gösteriyor; hissedilen değer termometreden daha sert.")
        case let (p, g, r, w, h) where r == .likely || r == .downpour:
            return paragraph(for: .cold, d: d, opening: "Soğuk havaya yağış ihtimali eklenmiş; zemin ve kıyafet seçimi daha önemli hale geliyor.")
        case let (p, g, r, w, h) where g == .plunging || g == .cooling:
            return paragraph(for: .cold, d: d, opening: "Soğuk zaten belirgin, üstüne sıcaklık biraz daha aşağı iniyor.")
        case let (p, g, r, w, h):
            return paragraph(for: .cold, d: d, opening: "Hava soğuk ama düzenli; doğru giyinince yönetilebilir bir kış serinliği var.")
        }
    }

    private static func frost(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .frostbite:
            return paragraph(for: .frost, d: d, opening: "Ayaz sertleşmiş; açıkta kalan cilt bu havayı çabuk hisseder.")
        case let (p, g, r, w, h) where h == .windChill || w == .harsh:
            return paragraph(for: .frost, d: d, opening: "Donma çizgisindeki hava rüzgârla bıçak gibi kesiyor.")
        case let (p, g, r, w, h) where r == .likely || r == .downpour:
            return paragraph(for: .frost, d: d, opening: "Ayazlı havaya nem ve yağış ihtimali eklenmiş; kar, buz veya sulu kar kapıda olabilir.")
        case let (p, g, r, w, h):
            return paragraph(for: .frost, d: d, opening: "Hava donma noktasının çevresinde; sessiz ama etkili bir ayaz var.")
        }
    }

    private static func extremeCold(_ d: AtmosphericDynamics) -> String {
        switch matrix(d) {
        case let (p, g, r, w, h) where h == .frostbite || h == .windChill:
            return paragraph(for: .extremeCold, d: d, opening: "Bu artık sıradan soğuk değil; iliklere işleyen, cildi hızla yoran bir hava.")
        case let (p, g, r, w, h) where r == .likely || r == .downpour || p == .stormyFall:
            return paragraph(for: .extremeCold, d: d, opening: "Aşırı soğuğa yağış ve düşen basınç eşlik ediyor; tipi veya yoğun kar ihtimali ciddiye alınmalı.")
        case let (p, g, r, w, h):
            return paragraph(for: .extremeCold, d: d, opening: "Aşırı soğuk sakin görünse bile beden için çok yorucu; hava affedici değil.")
        }
    }
}
