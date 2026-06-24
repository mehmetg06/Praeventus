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
            if hotSunny { sunDiskLayer }
            if hotSunny { SolarHazeLayer(windIntensity: windIntensity) }
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

    private var palette: [Color] {
        let base = atmosphere.condition.palette
        if hotSunny {
            return [
                Color(red: 0.04, green: 0.29, blue: 0.70),
                Color(red: 0.19, green: 0.57, blue: 0.96),
                Color(red: 0.74, green: 0.89, blue: 1.0),
                Color(red: 1.0, green: 0.77, blue: 0.45).opacity(0.90)
            ]
        }

        switch timeOfDay {
        case .dawn:
            return [base[0].opacity(0.92), Color(red: 0.52, green: 0.68, blue: 0.86), Color(red: 0.95, green: 0.62, blue: 0.42)]
        case .day:
            return [base[0], base[1], base[2]]
        case .sunset:
            return [base[0].opacity(0.90), Color(red: 0.37, green: 0.25, blue: 0.55), Color(red: 0.95, green: 0.40, blue: 0.25)]
        case .night:
            return [Color(red: 0.01, green: 0.015, blue: 0.06), Color(red: 0.03, green: 0.06, blue: 0.14), base[0].opacity(0.45)]
        }
    }

    private var lightField: some View {
        ZStack {
            Circle()
                .fill(horizonColor.opacity(hotSunny ? 0.34 : (mood == .storm ? 0.08 : 0.22)))
                .frame(width: hotSunny ? 700 : 560, height: hotSunny ? 700 : 560)
                .blur(radius: hotSunny ? 150 : 110)
                .offset(x: drift ? -150 : -80, y: drift ? -320 : -230)

            Circle()
                .fill(.cyan.opacity((mood == .wet || mood == .fog || mood == .snow) ? 0.13 : (hotSunny ? 0.045 : 0.08)))
                .frame(width: 460, height: 460)
                .blur(radius: 118)
                .offset(x: drift ? 150 : 90, y: drift ? 190 : 250)

            if hotSunny {
                Circle()
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.30).opacity(breathe ? 0.18 : 0.08))
                    .frame(width: 620, height: 620)
                    .blur(radius: 150)
                    .offset(x: 130, y: -70)

                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.80, blue: 0.42).opacity(0.18),
                        .clear,
                        Color(red: 1.0, green: 0.62, blue: 0.25).opacity(0.10)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()
                .blendMode(.screen)
            }

            if mood == .storm {
                Circle()
                    .fill(.purple.opacity(breathe ? 0.18 : 0.06))
                    .frame(width: 520, height: 520)
                    .blur(radius: 120)
                    .offset(x: -150, y: -170)
            }
        }
        .scaleEffect(breathe ? 1.018 : 0.992)
        .animation(.easeInOut(duration: hotSunny ? 18 : 13).repeatForever(autoreverses: true), value: breathe)
        .ignoresSafeArea()
    }

    private var sunDiskLayer: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.92),
                                Color(red: 1.0, green: 0.88, blue: 0.48).opacity(0.72),
                                Color(red: 1.0, green: 0.68, blue: 0.20).opacity(0.25),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 130
                        )
                    )
                    .frame(width: breathe ? 245 : 225, height: breathe ? 245 : 225)
                    .blur(radius: 18)

                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: 84, height: 84)
                    .blur(radius: 2)

                Circle()
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    .frame(width: 150, height: 150)
                    .blur(radius: 8)

                Ellipse()
                    .fill(Color(red: 1.0, green: 0.75, blue: 0.28).opacity(0.16))
                    .frame(width: 420, height: 130)
                    .blur(radius: 32)
                    .rotationEffect(.degrees(-28))
                    .offset(x: -54, y: 26)
            }
            .blendMode(.screen)
            .position(x: geometry.size.width * 0.84, y: geometry.size.height * 0.16)
            .opacity(0.95)
            .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: breathe)
        }
        .ignoresSafeArea()
    }

    private var horizonColor: Color {
        if hotSunny { return Color(red: 1.0, green: 0.74, blue: 0.35) }
        switch timeOfDay {
        case .dawn: return Color(red: 1.0, green: 0.72, blue: 0.50)
        case .day: return Color(red: 0.72, green: 0.86, blue: 1.0)
        case .sunset: return Color(red: 1.0, green: 0.42, blue: 0.26)
        case .night: return Color(red: 0.34, green: 0.42, blue: 0.88)
        }
    }

    private var airMassLayer: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 16.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let bands = max(2, min(5, Int(2 + atmosphere.cloudCover * 4)))
                let speed = 1.5 + windSpeed * 0.025

                for index in 0..<bands {
                    let width = size.width * (0.86 + CGFloat(index) * 0.12)
                    let height = size.height * (0.16 + CGFloat(index % 2) * 0.035)
                    let x = (CGFloat(time * (speed + Double(index) * 0.22)) + CGFloat(index * 211)).truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.12 + CGFloat(index) * 0.15)
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    let opacity = hotSunny ? 0.018 : 0.018 + atmosphere.cloudCover * 0.050
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }

                if hotSunny {
                    for index in 0..<3 {
                        let y = size.height * (0.62 + CGFloat(index) * 0.09)
                        let rect = CGRect(x: -size.width * 0.12, y: y, width: size.width * 1.24, height: 82)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 60),
                            with: .color(Color(red: 1.0, green: 0.78, blue: 0.42).opacity(0.030 - Double(index) * 0.006))
                        )
                    }
                }
            }
        }
        .blur(radius: mood == .fog ? 34 : (hotSunny ? 18 : 24))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var moodLayer: some View {
        switch mood {
        case .clear, .partlyCloudy:
            if hotSunny { HotSunnyLayer(drift: drift, windIntensity: windIntensity) }
        case .cloudy:
            EmptyView()
        case .wet:
            RainAtmosphereLayer(windSpeed: windSpeed, rainSignal: atmosphere.rainSignal)
        case .storm:
            StormPulseLayer()
            RainAtmosphereLayer(windSpeed: max(windSpeed, 35), rainSignal: .high)
        case .fog:
            FogAtmosphereLayer(windSpeed: windSpeed)
        case .snow:
            SnowAtmosphereLayer(windSpeed: windSpeed)
        }
    }

    private var depthOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .white.opacity(hotSunny ? 0.055 : 0.035),
                    .clear,
                    Color(red: 0.97, green: 0.58, blue: 0.22).opacity(hotSunny ? 0.16 : 0.0),
                    .black.opacity(baseDarkness)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [.clear, .black.opacity(mood == .storm ? 0.52 : (hotSunny ? 0.20 : 0.32))],
                center: .center,
                startRadius: 120,
                endRadius: 610
            )
        }
        .ignoresSafeArea()
    }

    private var baseDarkness: Double {
        let weather: Double
        switch mood {
        case .clear: weather = hotSunny ? 0.02 : 0.05
        case .partlyCloudy: weather = hotSunny ? 0.035 : 0.09
        case .cloudy: weather = 0.14
        case .wet: weather = 0.20
        case .storm: weather = 0.34
        case .fog: weather = 0.08
        case .snow: weather = 0.10
        }
        return min(0.62, weather + timeOfDay.darkness)
    }
}

private struct SolarHazeLayer: View {
    let windIntensity: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let sun = CGPoint(x: size.width * 0.84, y: size.height * 0.16)

                for index in 0..<5 {
                    let phase = CGFloat(time * (0.10 + Double(index) * 0.018))
                    var path = Path()
                    let startY = sun.y + CGFloat(index) * 18 - 30
                    path.move(to: CGPoint(x: sun.x - 18, y: startY))
                    path.addLine(to: CGPoint(x: -size.width * 0.05, y: size.height * (0.34 + CGFloat(index) * 0.105) + sin(phase) * 8))
                    path.addLine(to: CGPoint(x: -size.width * 0.05, y: size.height * (0.40 + CGFloat(index) * 0.105) + cos(phase) * 8))
                    path.addLine(to: CGPoint(x: sun.x + 18, y: startY + 22))
                    path.closeSubpath()

                    context.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.white.opacity(0.060 - Double(index) * 0.006),
                                Color(red: 1.0, green: 0.76, blue: 0.34).opacity(0.032 - Double(index) * 0.003),
                                .clear
                            ]),
                            startPoint: sun,
                            endPoint: CGPoint(x: 0, y: size.height * 0.76)
                        )
                    )
                }

                for index in 0..<7 {
                    let y = size.height * (0.48 + CGFloat(index) * 0.075)
                    let shimmer = CGFloat(sin(time * 0.22 + Double(index) * 0.8)) * (5 + CGFloat(windIntensity) * 8)
                    let rect = CGRect(x: -size.width * 0.12 + shimmer, y: y, width: size.width * 1.24, height: 72)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 60),
                        with: .color(Color(red: 1.0, green: 0.78, blue: 0.40).opacity(0.025 - Double(index) * 0.0018))
                    )
                }

                for index in 0..<18 {
                    let seed = Double(index * 31 + 9)
                    let xBase = CGFloat((sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude) * size.width
                    let yBase = CGFloat((sin(seed * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1).magnitude) * size.height
                    let drift = CGFloat(sin(time * 0.16 + seed)) * (12 + CGFloat(windIntensity) * 16)
                    let radius = CGFloat(1.1 + seed.truncatingRemainder(dividingBy: 2.4))
                    let opacity = 0.018 + Double(index % 5) * 0.004
                    context.fill(
                        Path(ellipseIn: CGRect(x: xBase + drift, y: yBase, width: radius, height: radius)),
                        with: .color(Color(red: 1.0, green: 0.90, blue: 0.62).opacity(opacity))
                    )
                }
            }
        }
        .blur(radius: 1.6)
        .blendMode(.screen)
        .ignoresSafeArea()
    }
}

private struct HotSunnyLayer: View {
    let drift: Bool
    let windIntensity: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.86, blue: 0.48).opacity(0.16),
                    .clear,
                    Color(red: 0.98, green: 0.50, blue: 0.18).opacity(0.10)
                ],
                startPoint: drift ? .topLeading : .top,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)

            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let waveCount = 5
                    for index in 0..<waveCount {
                        let y = size.height * (0.58 + CGFloat(index) * 0.075)
                        let phase = CGFloat(time * 0.38 + Double(index) * 1.7)
                        var path = Path()
                        path.move(to: CGPoint(x: -40, y: y))
                        let steps = 8
                        for step in 0...steps {
                            let x = size.width * CGFloat(step) / CGFloat(steps)
                            let shimmer = sin(CGFloat(step) * 1.35 + phase) * (2.5 + CGFloat(windIntensity) * 4)
                            path.addLine(to: CGPoint(x: x, y: y + shimmer))
                        }
                        context.stroke(
                            path,
                            with: .color(Color(red: 1.0, green: 0.86, blue: 0.54).opacity(0.040 - Double(index) * 0.004)),
                            style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .blur(radius: 1.1)
        }
        .ignoresSafeArea()
    }
}

private struct RainAtmosphereLayer: View {
    let windSpeed: Double
    let rainSignal: AtmosphericRisk

    private var intensity: Double {
        switch rainSignal {
        case .low: return 0.22
        case .moderate: return 0.42
        case .high: return 0.62
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 18.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(7 + intensity * 12)
                let tilt = CGFloat(5 + windSpeed * 0.10)

                for index in 0..<count {
                    let seed = Double(index * 73 + 17)
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 997)) / 997 * size.width
                    let speed = 26 + windSpeed * 0.22 + seed.truncatingRemainder(dividingBy: 8)
                    let y = CGFloat(time * speed + seed * 9).truncatingRemainder(dividingBy: size.height + 150) - 75
                    let length = CGFloat(20 + intensity * 20)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - tilt, y: y + length))
                    context.stroke(path, with: .color(.white.opacity(0.025 + intensity * 0.030)), lineWidth: 0.48)
                }

                let mist = CGRect(x: -size.width * 0.2, y: size.height * 0.46, width: size.width * 1.2, height: 130)
                context.fill(Path(roundedRect: mist, cornerRadius: 70), with: .color(.white.opacity(0.026 + intensity * 0.018)))
            }
        }
        .blur(radius: 0.35)
        .ignoresSafeArea()
    }
}

private struct StormPulseLayer: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.purple.opacity(pulse ? 0.045 : 0.0))
                .ignoresSafeArea()
            Circle()
                .fill(.indigo.opacity(pulse ? 0.16 : 0.05))
                .frame(width: 640, height: 640)
                .blur(radius: 120)
                .offset(x: -130, y: -230)
        }
        .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}

private struct FogAtmosphereLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 14.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<4 {
                    let width = size.width * (0.92 + CGFloat(index) * 0.10)
                    let speed = 1.6 + windSpeed * 0.025 + Double(index) * 0.18
                    let x = (CGFloat(time * speed) + CGFloat(index * 199)).truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.16 + CGFloat(index) * 0.18)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: 125)), with: .color(.white.opacity(0.070)))
                }
            }
        }
        .blur(radius: 32)
        .ignoresSafeArea()
    }
}

private struct SnowAtmosphereLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 18.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(10 + min(max(windSpeed / 100, 0), 1) * 8)

                for index in 0..<count {
                    let seed = Double(index * 59 + 23)
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 887)) / 887 * size.width + CGFloat(time * (1.2 + windSpeed * 0.06)).truncatingRemainder(dividingBy: 50) - 25
                    let y = CGFloat(time * (7 + seed.truncatingRemainder(dividingBy: 7)) + seed * 13).truncatingRemainder(dividingBy: size.height + 70) - 35
                    let point = CGFloat(1.4 + seed.truncatingRemainder(dividingBy: 2.2))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: point, height: point)), with: .color(.white.opacity(0.25)))
                }
            }
        }
        .ignoresSafeArea()
    }
}
#endif