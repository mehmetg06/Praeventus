#if canImport(SwiftUI)
import SwiftUI

// MARK: - Main View

struct WeatherLabView: View {
    @ObservedObject var store: WeatherStore
    private var weather: WeatherData { store.weather }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                GodModeHeader(store: store)
                conditionStrip
                parameterGrid
                presetSection
                atmosphericPanel
            }
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Condition Strip

    private var conditionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WeatherCondition.allCases) { c in
                    ConditionChip(
                        condition: c,
                        selected: weather.condition == c,
                        onTap: { store.update(condition: c) }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Parameter Grid

    private var parameterGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
            spacing: 10
        ) {
            GodSliderCard(
                label: "TEMP", display: "\(Int(weather.temperature.rounded()))°C",
                range: -10...48, value: temperatureBinding,
                accent: tempColor(weather.temperature)
            )
            GodSliderCard(
                label: "HUMIDITY", display: "\(Int(weather.humidity))%",
                range: 0...100, value: humidityBinding,
                accent: Color(red: 0.1, green: 0.7, blue: 0.9)
            )
            GodSliderCard(
                label: "PRESSURE", display: "\(Int(weather.pressure)) hPa",
                range: 980...1040, value: pressureBinding,
                accent: pressureColor(weather.pressure)
            )
            GodSliderCard(
                label: "WIND", display: "\(Int(weather.windSpeed)) km/h",
                range: 0...100, value: windBinding,
                accent: windColor(weather.windSpeed)
            )
            GodSliderCard(
                label: "RAIN", display: "\(Int(weather.rainProbability))%",
                range: 0...100, value: rainBinding,
                accent: Color(red: 0.2, green: 0.4, blue: 1.0)
            )
            GodSliderCard(
                label: "HOUR", display: weather.formattedHour,
                range: 0...23, value: hourBinding,
                accent: hourColor(weather.timeOfDay)
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("// QUICK SCENARIOS")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 16)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())],
                spacing: 8
            ) {
                PresetButton(label: "SUMMER DAY", icon: "sun.max.fill", accent: .orange) {
                    store.applyPreset(.clear, temp: 34, humidity: 42, pressure: 1018, wind: 10, rain: 4, hour: 14)
                }
                PresetButton(label: "MORNING FOG", icon: "cloud.fog.fill", accent: .mint) {
                    store.applyPreset(.fog, temp: 14, humidity: 96, pressure: 1012, wind: 4, rain: 12, hour: 7)
                }
                PresetButton(label: "SUNSET RAIN", icon: "cloud.sun.rain.fill", accent: Color(red: 0.9, green: 0.4, blue: 0.9)) {
                    store.applyPreset(.rain, temp: 22, humidity: 88, pressure: 1004, wind: 28, rain: 78, hour: 19)
                }
                PresetButton(label: "NIGHT STORM", icon: "cloud.bolt.rain.fill", accent: Color(red: 0.5, green: 0.2, blue: 1.0)) {
                    store.applyPreset(.storm, temp: 27, humidity: 91, pressure: 996, wind: 46, rain: 92, hour: 23)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Atmospheric Panel

    private var atmosphericPanel: some View {
        AtmosphericPanel(store: store)
            .padding(.horizontal, 16)
    }

    // MARK: - Color Helpers

    private func tempColor(_ t: Double) -> Color {
        if t < 0    { return Color(red: 0.5, green: 0.8, blue: 1.0) }
        if t < 15   { return .mint }
        if t < 28   { return Color(red: 0.2, green: 0.9, blue: 0.5) }
        if t < 36   { return .orange }
        return .red
    }

    private func pressureColor(_ p: Double) -> Color {
        if p < 1000 { return .red }
        if p < 1010 { return .orange }
        return Color(red: 0.2, green: 0.9, blue: 0.5)
    }

    private func windColor(_ w: Double) -> Color {
        if w < 20 { return .cyan }
        if w < 50 { return .orange }
        return .red
    }

    private func hourColor(_ t: TimeOfDay) -> Color {
        switch t {
        case .dawn:   return Color(red: 1.0, green: 0.6, blue: 0.3)
        case .day:    return .yellow
        case .sunset: return Color(red: 1.0, green: 0.4, blue: 0.1)
        case .night:  return Color(red: 0.5, green: 0.4, blue: 1.0)
        }
    }

    // MARK: - Bindings

    private var hourBinding: Binding<Double> {
        Binding(get: { weather.hour }, set: { store.update(hour: $0) })
    }
    private var temperatureBinding: Binding<Double> {
        Binding(get: { weather.temperature }, set: { store.update(temperature: $0) })
    }
    private var humidityBinding: Binding<Double> {
        Binding(get: { weather.humidity }, set: { store.update(humidity: $0) })
    }
    private var pressureBinding: Binding<Double> {
        Binding(get: { weather.pressure }, set: { store.update(pressure: $0) })
    }
    private var windBinding: Binding<Double> {
        Binding(get: { weather.windSpeed }, set: { store.update(windSpeed: $0) })
    }
    private var rainBinding: Binding<Double> {
        Binding(get: { weather.rainProbability }, set: { store.update(rainProbability: $0) })
    }
}

// MARK: - God Mode Header

struct GodModeHeader: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 4)

            ZStack {
                Image(systemName: store.atmosphere.symbolName)
                    .font(.system(size: 64))
                    .foregroundStyle(iconColor)
                    .blur(radius: 22)
                    .opacity(0.75)
                Image(systemName: store.atmosphere.symbolName)
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [iconColor, iconColor.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.bottom, 2)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(store.weather.temperature.rounded()))")
                    .font(.system(size: 68, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(.white)
                Text("°C")
                    .font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(badgeAccent)
                    .frame(width: 5, height: 5)
                    .shadow(color: badgeAccent, radius: 4)
                Text(store.atmosphere.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(badgeAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(badgeAccent.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(badgeAccent.opacity(0.35), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(store.atmosphere.story)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)

            HStack(spacing: 5) {
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("⚡ GOD MODE ACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.65))
            }
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var iconColor: Color {
        switch store.atmosphere.backgroundMood {
        case .clear:        return .yellow
        case .partlyCloudy: return Color(red: 0.5, green: 0.8, blue: 1.0)
        case .cloudy:       return Color(white: 0.65)
        case .wet:          return Color(red: 0.3, green: 0.5, blue: 1.0)
        case .storm:        return Color(red: 0.7, green: 0.3, blue: 1.0)
        case .fog:          return Color(red: 0.7, green: 0.9, blue: 0.9)
        case .snow:         return Color(red: 0.85, green: 0.92, blue: 1.0)
        }
    }

    private var badgeAccent: Color {
        switch store.atmosphere.stormRisk {
        case .low:      return .cyan
        case .moderate: return .orange
        case .high:     return .red
        }
    }
}

// MARK: - Condition Chip

struct ConditionChip: View {
    let condition: WeatherCondition
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Image(systemName: condition.symbolName)
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? accent : .white.opacity(0.3))
                    .shadow(color: selected ? accent : .clear, radius: 6)
                Text(condition.displayName.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? accent : .white.opacity(0.22))
            }
            .frame(width: 64, height: 54)
            .background(selected ? accent.opacity(0.1) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selected ? accent.opacity(0.55) : Color.white.opacity(0.07),
                        lineWidth: selected ? 1.0 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    private var accent: Color {
        switch condition {
        case .clear:        return .yellow
        case .partlyCloudy: return .cyan
        case .cloudy:       return Color(white: 0.7)
        case .rain:         return Color(red: 0.3, green: 0.5, blue: 1.0)
        case .storm:        return Color(red: 0.6, green: 0.2, blue: 1.0)
        case .fog:          return .mint
        case .snow:         return Color(red: 0.8, green: 0.9, blue: 1.0)
        }
    }
}

// MARK: - God Slider Card

struct GodSliderCard: View {
    let label: String
    let display: String
    let range: ClosedRange<Double>
    @Binding var value: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(accent.opacity(0.7))
                .tracking(1.5)

            Text(display)
                .font(.system(size: 22, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Slider(value: $value, in: range)
                .tint(accent)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.05))
                        .frame(height: 2)
                    Capsule()
                        .fill(accent.opacity(0.65))
                        .frame(width: max(0, geo.size.width * fillFraction), height: 2)
                        .shadow(color: accent, radius: 3)
                }
            }
            .frame(height: 2)
        }
        .padding(12)
        .background(.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(0.12 + fillFraction * 0.28), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var fillFraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let label: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.7), radius: 4)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.3), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Atmospheric Panel

struct AtmosphericPanel: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("// COMPUTED STATE")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))

            VStack(spacing: 10) {
                AtmoBar(
                    label: "CLOUD COVER",
                    value: store.atmosphere.cloudCover,
                    accent: Color(white: 0.7)
                )
                AtmoBar(
                    label: "INSTABILITY",
                    value: store.atmosphere.instability,
                    accent: instabilityColor(store.atmosphere.instability)
                )
                AtmoRow(
                    label: "STORM RISK",
                    value: store.atmosphere.stormRisk.displayName.uppercased(),
                    accent: riskColor(store.atmosphere.stormRisk)
                )
                AtmoRow(
                    label: "RAIN SIGNAL",
                    value: store.atmosphere.rainSignal.displayName.uppercased(),
                    accent: riskColor(store.atmosphere.rainSignal)
                )
                AtmoRow(
                    label: "VISIBILITY",
                    value: store.atmosphere.visibility.displayName.uppercased(),
                    accent: visibilityColor(store.atmosphere.visibility)
                )
                AtmoRow(
                    label: "CONDITION",
                    value: store.atmosphere.condition.displayName.uppercased(),
                    accent: .cyan
                )
            }
            .padding(12)
            .background(.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.07), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func riskColor(_ r: AtmosphericRisk) -> Color {
        switch r {
        case .low:      return .green
        case .moderate: return .orange
        case .high:     return .red
        }
    }

    private func instabilityColor(_ v: Double) -> Color {
        if v < 0.33 { return .green }
        if v < 0.66 { return .orange }
        return .red
    }

    private func visibilityColor(_ v: AtmosphericVisibility) -> Color {
        switch v {
        case .clear:   return .green
        case .reduced: return .orange
        case .poor:    return .red
        }
    }
}

// MARK: - Atomic Readout Subviews

struct AtmoBar: View {
    let label: String
    let value: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.06))
                        .frame(height: 4)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * min(max(value, 0), 1)), height: 4)
                        .shadow(color: accent.opacity(0.7), radius: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

struct AtmoRow: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: accent, radius: 3)
                Text(value)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }
        }
    }
}
#endif
