#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let atmosphere: AtmosphericState
    let hour: Double
    let windSpeed: Double

    private var mood: BackgroundMood { atmosphere.backgroundMood }
    private var timeOfDay: TimeOfDay { TimeOfDay(hour: Int(hour.rounded())) }
    private var windIntensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }
    private var hotSunny: Bool {
        (mood == .clear || mood == .partlyCloudy) &&
        (atmosphere.condition == .clear || atmosphere.condition == .partlyCloudy) &&
        timeOfDay == .day
    }
    private var clearNight: Bool {
        (mood == .clear || mood == .partlyCloudy) && timeOfDay == .night
    }

    @State private var drift = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: drift ? .topTrailing : .topLeading,
                endPoint: drift ? .bottomLeading : .bottomTrailing
            )
            .ignoresSafeArea()

            lightField
            if clearNight { starField }
            if hotSunny { sunDiskLayer }
            if hotSunny { SunHaloOpticsLayer(windIntensity: windIntensity) }
            airMassLayer
            moodLayer
            depthOverlay
        }
        .animation(.easeInOut(duration: 22).repeatForever(autoreverses: true), value: drift)
        .animation(.easeInOut(duration: 0.65), value: mood)
        .animation(.easeInOut(duration: 0.65), value: Int(hour.rounded()))
        .onAppear {
            drift = true
            breathe = true
        }
    }

    // MARK: - Palette

    private var palette: [Color] {
        let base = atmosphere.condition.palette
        if hotSunny {
            return [
                Color(red: 0.02, green: 0.22, blue: 0.72),
                Color(red: 0.12, green: 0.52, blue: 0.96),
                Color(red: 0.68, green: 0.88, blue: 1.0),
                Color(red: 1.0, green: 0.80, blue: 0.42).opacity(0.95)
            ]
        }
        switch timeOfDay {
        case .dawn:   return dawnPalette(base: base)
        case .day:    return [base[0], base[1], base[2]]
        case .sunset: return sunsetPalette(base: base)
        case .night:  return nightPalette(base: base)
        }
    }

    private func dawnPalette(base: [Color]) -> [Color] {
        switch mood {
        case .storm:
            return [Color(red: 0.02, green: 0.01, blue: 0.08),
                    Color(red: 0.14, green: 0.08, blue: 0.24),
                    Color(red: 0.50, green: 0.30, blue: 0.44)]
        case .wet:
            return [Color(red: 0.04, green: 0.07, blue: 0.20),
                    Color(red: 0.28, green: 0.38, blue: 0.54),
                    Color(red: 0.72, green: 0.60, blue: 0.58)]
        case .snow:
            return [Color(red: 0.06, green: 0.08, blue: 0.24),
                    Color(red: 0.52, green: 0.62, blue: 0.80),
                    Color(red: 0.96, green: 0.84, blue: 0.84)]
        case .fog:
            return [Color(red: 0.46, green: 0.48, blue: 0.52),
                    Color(red: 0.74, green: 0.72, blue: 0.70),
                    Color(red: 0.94, green: 0.90, blue: 0.86)]
        default:
            return [Color(red: 0.10, green: 0.06, blue: 0.28),
                    Color(red: 0.64, green: 0.34, blue: 0.58),
                    Color(red: 1.0, green: 0.68, blue: 0.46)]
        }
    }

    private func sunsetPalette(base: [Color]) -> [Color] {
        switch mood {
        case .storm:
            return [Color(red: 0.01, green: 0.01, blue: 0.06),
                    Color(red: 0.20, green: 0.06, blue: 0.18),
                    Color(red: 0.42, green: 0.16, blue: 0.28)]
        case .wet:
            return [Color(red: 0.04, green: 0.06, blue: 0.18),
                    Color(red: 0.28, green: 0.22, blue: 0.38),
                    Color(red: 0.62, green: 0.44, blue: 0.40)]
        case .snow:
            return [Color(red: 0.06, green: 0.08, blue: 0.26),
                    Color(red: 0.42, green: 0.50, blue: 0.70),
                    Color(red: 0.92, green: 0.80, blue: 0.74)]
        case .fog:
            return [Color(red: 0.34, green: 0.30, blue: 0.28),
                    Color(red: 0.64, green: 0.56, blue: 0.48),
                    Color(red: 0.90, green: 0.80, blue: 0.70)]
        case .cloudy:
            return [Color(red: 0.08, green: 0.10, blue: 0.20),
                    Color(red: 0.32, green: 0.30, blue: 0.42),
                    Color(red: 0.62, green: 0.54, blue: 0.60)]
        default:
            return [Color(red: 0.06, green: 0.04, blue: 0.20),
                    Color(red: 0.50, green: 0.16, blue: 0.38),
                    Color(red: 1.0, green: 0.44, blue: 0.16)]
        }
    }

    private func nightPalette(base: [Color]) -> [Color] {
        switch mood {
        case .storm:
            return [Color(red: 0.01, green: 0.01, blue: 0.04),
                    Color(red: 0.04, green: 0.03, blue: 0.12),
                    Color(red: 0.14, green: 0.08, blue: 0.26)]
        case .fog:
            return [Color(red: 0.18, green: 0.20, blue: 0.24),
                    Color(red: 0.36, green: 0.38, blue: 0.44),
                    Color(red: 0.56, green: 0.58, blue: 0.62)]
        case .snow:
            return [Color(red: 0.03, green: 0.04, blue: 0.14),
                    Color(red: 0.10, green: 0.16, blue: 0.34),
                    Color(red: 0.28, green: 0.42, blue: 0.62)]
        default:
            return [Color(red: 0.01, green: 0.01, blue: 0.06),
                    Color(red: 0.02, green: 0.04, blue: 0.14),
                    base[0].opacity(0.45)]
        }
    }

    // MARK: - Horizon Color

    private var horizonColor: Color {
        if hotSunny { return Color(red: 1.0, green: 0.76, blue: 0.32) }
        switch mood {
        case .storm: return Color(red: 0.24, green: 0.18, blue: 0.50)
        case .wet:   return Color(red: 0.32, green: 0.50, blue: 0.68)
        case .snow:  return Color(red: 0.66, green: 0.82, blue: 1.0)
        case .fog:   return Color(red: 0.80, green: 0.84, blue: 0.80)
        default:
            switch timeOfDay {
            case .dawn:   return Color(red: 1.0, green: 0.68, blue: 0.46)
            case .day:    return Color(red: 0.64, green: 0.84, blue: 1.0)
            case .sunset: return Color(red: 1.0, green: 0.40, blue: 0.22)
            case .night:  return Color(red: 0.22, green: 0.34, blue: 0.80)
            }
        }
    }

    // MARK: - Light Field

    private var lightField: some View {
        ZStack {
            Circle()
                .fill(horizonColor.opacity(hotSunny ? 0.36 : (mood == .storm ? 0.10 : 0.24)))
                .frame(width: hotSunny ? 720 : 580, height: hotSunny ? 720 : 580)
                .blur(radius: hotSunny ? 155 : 120)
                .offset(x: drift ? -140 : -70, y: drift ? -330 : -240)

            Circle()
                .fill(accentLightColor.opacity(accentLightOpacity))
                .frame(width: 480, height: 480)
                .blur(radius: 125)
                .offset(x: drift ? 160 : 100, y: drift ? 200 : 260)

            if hotSunny {
                Circle()
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.28).opacity(breathe ? 0.20 : 0.09))
                    .frame(width: 650, height: 650)
                    .blur(radius: 160)
                    .offset(x: 140, y: -60)

                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.82, blue: 0.40).opacity(0.20),
                        .clear,
                        Color(red: 1.0, green: 0.60, blue: 0.22).opacity(0.12)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()
                .blendMode(.screen)
            }

            if mood == .storm {
                Circle()
                    .fill(Color(red: 0.28, green: 0.10, blue: 0.60).opacity(breathe ? 0.24 : 0.08))
                    .frame(width: 580, height: 580)
                    .blur(radius: 130)
                    .offset(x: -160, y: -180)
                Circle()
                    .fill(Color(red: 0.10, green: 0.02, blue: 0.30).opacity(breathe ? 0.18 : 0.06))
                    .frame(width: 420, height: 420)
                    .blur(radius: 100)
                    .offset(x: 120, y: -80)
            }

            if mood == .snow {
                Circle()
                    .fill(Color(red: 0.70, green: 0.86, blue: 1.0).opacity(breathe ? 0.18 : 0.08))
                    .frame(width: 540, height: 540)
                    .blur(radius: 140)
                    .offset(x: 60, y: -140)
            }

            if clearNight {
                Circle()
                    .fill(Color(red: 0.20, green: 0.30, blue: 0.90).opacity(breathe ? 0.12 : 0.05))
                    .frame(width: 500, height: 500)
                    .blur(radius: 130)
                    .offset(x: -100, y: -200)
            }
        }
        // Collapse the large soft glow discs (blur 120–160) into one Metal
        // layer so the breathing scale is a cheap bitmap transform rather than
        // re-running several full-screen Gaussian blurs every frame.
        .drawingGroup()
        .scaleEffect(breathe ? 1.020 : 0.990)
        .animation(.easeInOut(duration: hotSunny ? 18 : 14).repeatForever(autoreverses: true), value: breathe)
        .ignoresSafeArea()
    }

    private var accentLightColor: Color {
        switch mood {
        case .storm:  return Color(red: 0.20, green: 0.10, blue: 0.50)
        case .wet:    return Color(red: 0.30, green: 0.50, blue: 0.70)
        case .snow:   return Color(red: 0.60, green: 0.80, blue: 1.0)
        case .fog:    return Color(red: 0.80, green: 0.82, blue: 0.80)
        default:      return .cyan
        }
    }

    private var accentLightOpacity: Double {
        switch mood {
        case .wet, .fog, .snow: return 0.14
        case .storm:            return 0.10
        default:                return hotSunny ? 0.04 : 0.09
        }
    }

    // MARK: - Star Field (Clear/PartlyCloudy Night)

    private var starField: some View {
        Canvas { context, size in
            for i in 0..<100 {
                let d = Double(i)
                let x = (sin(d * 127.1) * 0.5 + 0.5) * Double(size.width)
                let y = (sin(d * 311.7) * 0.5 + 0.5) * Double(size.height) * 0.74
                let r = 0.5 + (sin(d * 74.3) * 0.5 + 0.5) * 1.4
                let a = max(0.08, 0.16 + (sin(d * 193.1) * 0.5 + 0.5) * 0.52)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                    with: .color(.white.opacity(a))
                )
            }
            let moonX = Double(size.width) * 0.74
            let moonY = Double(size.height) * 0.18
            let moonR = 20.0
            // Outer atmospheric glow
            context.fill(
                Path(ellipseIn: CGRect(x: moonX - 48, y: moonY - 48, width: 96, height: 96)),
                with: .color(.white.opacity(0.04))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: moonX - 30, y: moonY - 30, width: 60, height: 60)),
                with: .color(.white.opacity(0.07))
            )
            // Crescent shape: full circle minus offset bite
            context.drawLayer { moon in
                moon.fill(
                    Path(ellipseIn: CGRect(x: moonX - moonR, y: moonY - moonR,
                                          width: moonR * 2, height: moonR * 2)),
                    with: .color(.white.opacity(0.90))
                )
                moon.blendMode = .destinationOut
                moon.fill(
                    Path(ellipseIn: CGRect(x: moonX - moonR + 11, y: moonY - moonR - 2,
                                          width: moonR * 2, height: moonR * 2)),
                    with: .color(.white)
                )
            }
        }
        .blur(radius: 0.5)
        .ignoresSafeArea()
    }

    // MARK: - Sun Disk Layer

    private var sunDiskLayer: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.96),
                                Color(red: 1.0, green: 0.92, blue: 0.56).opacity(0.82),
                                Color(red: 1.0, green: 0.70, blue: 0.22).opacity(0.34),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 148
                        )
                    )
                    .frame(width: 246, height: 246)
                    .blur(radius: 20)

                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: 90, height: 90)
                    .blur(radius: 1.5)

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.58, blue: 0.18).opacity(0.20),
                                Color(red: 0.58, green: 0.82, blue: 1.0).opacity(0.14),
                                Color(red: 1.0, green: 0.58, blue: 0.18).opacity(0.20)
                            ],
                            center: .center
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: 118, height: 118)
                    .blur(radius: 2.2)

                Ellipse()
                    .fill(Color(red: 1.0, green: 0.76, blue: 0.28).opacity(0.18))
                    .frame(width: 480, height: 118)
                    .blur(radius: 30)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -75, y: 24)
            }
            // Render the sun disc once, then breathe via a GPU scale transform
            // instead of resizing the blurred frames (which re-blurs each frame).
            .drawingGroup()
            .scaleEffect(breathe ? 1.045 : 1.0)
            .blendMode(.screen)
            .position(x: geometry.size.width * 0.84, y: geometry.size.height * 0.16)
            .opacity(0.98)
            .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: breathe)
        }
        .ignoresSafeArea()
    }

    // MARK: - Air Mass Layer

    private var airMassLayer: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 14.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let bands = max(2, min(6, Int(2 + atmosphere.cloudCover * 5)))
                let speed = 1.2 + windSpeed * 0.022

                for index in 0..<bands {
                    let width = size.width * (0.82 + CGFloat(index) * 0.14)
                    let height = size.height * (0.14 + CGFloat(index % 3) * 0.032)
                    let x = (CGFloat(time * (speed + Double(index) * 0.20)) + CGFloat(index * 211))
                        .truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.10 + CGFloat(index) * 0.13)
                    let opacity = hotSunny ? 0.016 : 0.016 + atmosphere.cloudCover * 0.055
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)),
                                 with: .color(.white.opacity(opacity)))

                    if !hotSunny && atmosphere.cloudCover > 0.3 {
                        let shadowRect = CGRect(x: x + width * 0.08, y: y + height * 0.70,
                                               width: width * 0.84, height: height * 0.50)
                        context.fill(Path(ellipseIn: shadowRect),
                                     with: .color(.black.opacity(0.022 + atmosphere.cloudCover * 0.022)))
                    }
                }

                if hotSunny {
                    for index in 0..<3 {
                        let y = size.height * (0.60 + CGFloat(index) * 0.10)
                        let rect = CGRect(x: -size.width * 0.12, y: y, width: size.width * 1.24, height: 78)
                        context.fill(Path(roundedRect: rect, cornerRadius: 55),
                                     with: .color(Color(red: 1.0, green: 0.78, blue: 0.40).opacity(0.028 - Double(index) * 0.005)))
                    }
                }
            }
        }
        .blur(radius: mood == .fog ? 38 : (hotSunny ? 20 : 26))
        .ignoresSafeArea()
    }

    // MARK: - Mood Layer

    @ViewBuilder
    private var moodLayer: some View {
        switch mood {
        case .clear:
            if hotSunny { HotSunnyLayer(drift: drift, windIntensity: windIntensity) }
        case .partlyCloudy:
            if hotSunny {
                HotSunnyLayer(drift: drift, windIntensity: windIntensity)
            } else {
                VolumetricCloudLayer(cloudCover: max(0.32, atmosphere.cloudCover),
                                     windSpeed: windSpeed, timeOfDay: timeOfDay, scattered: true)
            }
        case .cloudy:
            VolumetricCloudLayer(cloudCover: max(0.6, atmosphere.cloudCover),
                                 windSpeed: windSpeed, timeOfDay: timeOfDay)
        case .wet:
            VolumetricRainLayer(windSpeed: windSpeed, rainSignal: atmosphere.rainSignal)
            RaindropGlassLayer(intensity: rainGlassIntensity, windSpeed: windSpeed)
        case .storm:
            LightningStormLayer()
            VolumetricRainLayer(windSpeed: max(windSpeed, 35), rainSignal: .high)
            RaindropGlassLayer(intensity: 0.88, windSpeed: max(windSpeed, 35))
        case .fog:
            DriftingFogLayer(windSpeed: windSpeed)
        case .snow:
            RealisticSnowLayer(windSpeed: windSpeed)
        }
    }

    private var rainGlassIntensity: Double {
        switch atmosphere.rainSignal {
        case .low:      return 0.42
        case .moderate: return 0.64
        case .high:     return 0.86
        }
    }

    // MARK: - Depth Overlay

    private var depthOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .white.opacity(hotSunny ? 0.060 : 0.040),
                    .clear,
                    depthMidColor,
                    .black.opacity(baseDarkness)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [.clear, .black.opacity(mood == .storm ? 0.60 : (hotSunny ? 0.18 : 0.30))],
                center: .center,
                startRadius: 110,
                endRadius: 640
            )
        }
        .ignoresSafeArea()
    }

    private var depthMidColor: Color {
        switch mood {
        case .storm: return Color(red: 0.10, green: 0.04, blue: 0.22).opacity(0.30)
        case .wet:   return Color(red: 0.04, green: 0.12, blue: 0.24).opacity(0.20)
        default:     return Color(red: 0.97, green: 0.58, blue: 0.22).opacity(hotSunny ? 0.18 : 0.0)
        }
    }

    private var baseDarkness: Double {
        let weather: Double
        switch mood {
        case .clear:        weather = hotSunny ? 0.02 : 0.06
        case .partlyCloudy: weather = hotSunny ? 0.04 : 0.10
        case .cloudy:       weather = 0.16
        case .wet:          weather = 0.22
        case .storm:        weather = 0.38
        case .fog:          weather = 0.08
        case .snow:         weather = 0.10
        }
        return min(0.66, weather + timeOfDay.darkness)
    }
}

// MARK: - Hot Sunny Layer

private struct HotSunnyLayer: View {
    let drift: Bool
    let windIntensity: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.88, blue: 0.46).opacity(0.18),
                    .clear,
                    Color(red: 1.0, green: 0.50, blue: 0.16).opacity(0.12)
                ],
                startPoint: drift ? .topLeading : .top,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)

            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    for index in 0..<6 {
                        let y = size.height * (0.55 + CGFloat(index) * 0.075)
                        let phase = CGFloat(time * 0.36 + Double(index) * 1.7)
                        var path = Path()
                        path.move(to: CGPoint(x: -40, y: y))
                        for step in 0...10 {
                            let x = size.width * CGFloat(step) / 10
                            let shimmer = sin(CGFloat(step) * 1.28 + phase) * (2.2 + CGFloat(windIntensity) * 4.5)
                            path.addLine(to: CGPoint(x: x, y: y + shimmer))
                        }
                        context.stroke(
                            path,
                            with: .color(Color(red: 1.0, green: 0.88, blue: 0.54).opacity(0.038 - Double(index) * 0.004)),
                            style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .blur(radius: 1.0)
        }
        .ignoresSafeArea()
    }
}
#endif
