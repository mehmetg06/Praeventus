#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let atmosphere: AtmosphericState
    let hour: Double
    let windSpeed: Double

    private var condition: WeatherCondition { atmosphere.condition }
    private var mood: BackgroundMood { atmosphere.backgroundMood }
    private var timeOfDay: TimeOfDay { TimeOfDay(hour: Int(hour.rounded())) }
    private var windIntensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }
    private var rainIntensity: Double {
        switch atmosphere.rainSignal {
        case .low: return 0.32
        case .moderate: return 0.62
        case .high: return 0.92
        }
    }

    @State private var drift = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: timeAwarePalette,
                startPoint: drift ? .topTrailing : .topLeading,
                endPoint: drift ? .bottomLeading : .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: drift)

            lightVolumeLayer
            cloudMassLayer

            if windIntensity > 0.18 || atmosphere.stormRisk == .high {
                WindFlowLayer(windSpeed: windSpeed)
                    .blendMode(.screen)
                    .opacity(0.18 + windIntensity * 0.25)
                    .allowsHitTesting(false)
            }

            weatherSpecificLayer

            Rectangle()
                .fill(.black.opacity(baseDarkness))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.7), value: atmosphere)
        .animation(.easeInOut(duration: 0.7), value: Int(hour.rounded()))
        .animation(.easeInOut(duration: 0.45), value: Int(windSpeed.rounded()))
        .onAppear {
            drift = true
            breathe = true
        }
    }

    private var timeAwarePalette: [Color] {
        switch timeOfDay {
        case .dawn:
            return [condition.palette[0], Color(red: 0.70, green: 0.84, blue: 0.96), Color(red: 1.0, green: 0.68, blue: 0.45)]
        case .day:
            return condition.palette
        case .sunset:
            return [condition.palette[0].opacity(0.95), Color(red: 0.43, green: 0.30, blue: 0.58), Color(red: 1.0, green: 0.48, blue: 0.28)]
        case .night:
            return [Color(red: 0.01, green: 0.02, blue: 0.07), Color(red: 0.03, green: 0.08, blue: 0.18), condition.palette[0].opacity(0.62)]
        }
    }

    private var baseDarkness: Double {
        let weatherDarkness: Double
        switch mood {
        case .clear: weatherDarkness = 0.04
        case .partlyCloudy: weatherDarkness = 0.08
        case .cloudy: weatherDarkness = 0.14
        case .wet: weatherDarkness = 0.18
        case .storm: weatherDarkness = 0.28
        case .fog: weatherDarkness = 0.10
        case .snow: weatherDarkness = 0.10
        }
        return min(0.64, weatherDarkness + timeOfDay.darkness)
    }

    private var lightVolumeLayer: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(mood == .storm ? 0.08 : 0.20))
                .frame(width: 460, height: 460)
                .blur(radius: 86)
                .offset(x: drift ? -150 : -70, y: drift ? -240 : -170)

            Circle()
                .fill(.cyan.opacity((mood == .snow || mood == .wet ? 0.18 : 0.12) + timeOfDay.coolness))
                .frame(width: 420, height: 420)
                .blur(radius: 96)
                .offset(x: drift ? 150 : 92, y: drift ? 180 : 260)

            Circle()
                .fill(.orange.opacity((mood == .clear || mood == .partlyCloudy ? 0.17 : 0.03) + timeOfDay.warmth))
                .frame(width: 340, height: 340)
                .blur(radius: 86)
                .offset(x: drift ? -176 : -230, y: timeOfDay == .sunset ? 170 : 86)

            if timeOfDay == .night {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 84, height: 84)
                    .blur(radius: 2)
                    .offset(x: 112, y: -238)
                    .shadow(color: .white.opacity(0.25), radius: 24)
            }
        }
        .scaleEffect(breathe ? 1.025 : 0.99)
        .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: breathe)
    }

    private var cloudMassLayer: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let baseSpeed = 6 + windSpeed * 0.10
                let layers = Int(3 + atmosphere.cloudCover * 6)

                for index in 0..<max(2, layers) {
                    let width = size.width * (0.46 + CGFloat(index) * 0.055)
                    let height = size.height * (0.12 + CGFloat(index % 3) * 0.025)
                    let speed = baseSpeed + Double(index) * 0.8
                    let x = (CGFloat(time * speed) + CGFloat(index * 173)).truncatingRemainder(dividingBy: size.width + width + 180) - width
                    let y = size.height * (0.08 + CGFloat(index) * 0.115)
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    let opacity: Double = 0.03 + atmosphere.cloudCover * 0.07
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .blur(radius: 34)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var weatherSpecificLayer: some View {
        switch mood {
        case .wet:
            PremiumRainGlassLayer(windSpeed: windSpeed, intensity: rainIntensity, stormMode: false)
        case .storm:
            StormMoodLayer(windSpeed: windSpeed)
            PremiumRainGlassLayer(windSpeed: max(windSpeed, 35), intensity: max(0.72, rainIntensity), stormMode: true)
        case .fog:
            FogMoodLayer(windSpeed: windSpeed)
        case .snow:
            SnowMoodLayer(windSpeed: windSpeed)
        default:
            if timeOfDay == .night { StarDustLayer() }
        }
    }
}

private struct PremiumRainGlassLayer: View {
    let windSpeed: Double
    let intensity: Double
    let stormMode: Bool

    var body: some View {
        ZStack {
            RainMistLayer(intensity: intensity)
            SubtleRainStreakLayer(windSpeed: windSpeed, intensity: intensity)
            GlassDropletLayer(windSpeed: windSpeed, intensity: intensity, stormMode: stormMode)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct RainMistLayer: View {
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<5 {
                    let width = size.width * (0.70 + CGFloat(index) * 0.12)
                    let y = (CGFloat(time * (2.0 + Double(index) * 0.4)) + CGFloat(index * 137)).truncatingRemainder(dividingBy: size.height + 240) - 120
                    let rect = CGRect(x: -size.width * 0.18, y: y, width: width, height: 95 + CGFloat(index * 18))
                    context.fill(Path(roundedRect: rect, cornerRadius: 58), with: .color(.white.opacity(0.020 + intensity * 0.020)))
                }
            }
        }
        .blur(radius: 18)
    }
}

private struct SubtleRainStreakLayer: View {
    let windSpeed: Double
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let streakCount = Int(10 + intensity * 18)
                let tilt = CGFloat(5 + windSpeed * 0.18)

                for index in 0..<streakCount {
                    let seed = Double(index * 71 + 19)
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 997)) / 997 * size.width
                    let speed = 42 + windSpeed * 0.35 + seed.truncatingRemainder(dividingBy: 17)
                    let y = CGFloat(time * speed + seed * 13).truncatingRemainder(dividingBy: size.height + 170) - 85
                    let length = CGFloat(34 + intensity * 34)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - tilt, y: y + length))
                    context.stroke(path, with: .color(.white.opacity(0.035 + intensity * 0.045)), lineWidth: 0.55)
                }
            }
        }
        .blur(radius: 0.7)
    }
}

private struct GlassDropletLayer: View {
    let windSpeed: Double
    let intensity: Double
    let stormMode: Bool

    private var dropletCount: Int { Int(12 + intensity * 14) }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<dropletCount, id: \.self) { index in
                        let seed = Double(index * 47 + 23)
                        let base = dropletBase(seed: seed, size: proxy.size)
                        let slide = dropletSlide(seed: seed, time: time, height: proxy.size.height)
                        let width = base.width
                        let height = base.height

                        GlassDropletShape(seed: seed)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.24),
                                        .white.opacity(0.070),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                GlassDropletShape(seed: seed)
                                    .stroke(.white.opacity(0.16), lineWidth: 0.7)
                            }
                            .overlay(alignment: .topLeading) {
                                Ellipse()
                                    .fill(.white.opacity(0.30))
                                    .frame(width: width * 0.34, height: height * 0.16)
                                    .blur(radius: 1.4)
                                    .offset(x: width * 0.18, y: height * 0.16)
                            }
                            .background {
                                GlassDropletShape(seed: seed)
                                    .fill(.black.opacity(0.10))
                                    .blur(radius: 1.8)
                                    .offset(x: 1.2, y: 2.4)
                            }
                            .frame(width: width, height: height)
                            .scaleEffect(x: 0.82 + CGFloat((seed.truncatingRemainder(dividingBy: 9)) / 30), y: 1.0)
                            .rotationEffect(.degrees(seed.truncatingRemainder(dividingBy: 18) - 9))
                            .opacity(dropletOpacity(seed: seed))
                            .position(x: base.x + CGFloat(windSpeed * 0.06) * slide.progress, y: base.y + slide.y)
                            .blendMode(.screen)
                    }
                }
                .compositingGroup()
            }
        }
    }

    private func dropletBase(seed: Double, size: CGSize) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let xUnit = (seed * 13).truncatingRemainder(dividingBy: 997) / 997
        let yUnit = (seed * 29).truncatingRemainder(dividingBy: 733) / 733
        let edgeBias = seed.truncatingRemainder(dividingBy: 5)
        let x: CGFloat
        if edgeBias < 1.2 {
            x = CGFloat(0.06 + xUnit * 0.18) * size.width
        } else if edgeBias > 3.8 {
            x = CGFloat(0.76 + xUnit * 0.18) * size.width
        } else {
            x = CGFloat(0.22 + xUnit * 0.56) * size.width
        }
        let y = CGFloat(0.06 + yUnit * 0.82) * size.height
        let large = seed.truncatingRemainder(dividingBy: 6) > 4.2
        let width = CGFloat(large ? 18 + seed.truncatingRemainder(dividingBy: 18) : 7 + seed.truncatingRemainder(dividingBy: 10))
        let height = width * CGFloat(1.15 + seed.truncatingRemainder(dividingBy: 1.4))
        return (x, y, width, height)
    }

    private func dropletSlide(seed: Double, time: Double, height: CGFloat) -> (y: CGFloat, progress: CGFloat) {
        let movable = seed.truncatingRemainder(dividingBy: 10) > 6.2
        guard movable else { return (0, 0) }
        let cycle = 14 + seed.truncatingRemainder(dividingBy: 16)
        let raw = (time + seed).truncatingRemainder(dividingBy: cycle) / cycle
        let eased = raw * raw * (3 - 2 * raw)
        let travel = height * CGFloat(0.10 + intensity * 0.14 + (stormMode ? 0.08 : 0.0))
        return (CGFloat(eased) * travel, CGFloat(eased))
    }

    private func dropletOpacity(seed: Double) -> Double {
        let base = 0.26 + intensity * 0.30
        let variation = seed.truncatingRemainder(dividingBy: 7) / 70
        return min(0.72, base + variation)
    }
}

private struct GlassDropletShape: Shape {
    let seed: Double

    func path(in rect: CGRect) -> Path {
        let wobble = CGFloat(seed.truncatingRemainder(dividingBy: 7)) / 100
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX * (0.88 + wobble), y: rect.midY),
            control1: CGPoint(x: rect.maxX * 0.76, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.30)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX * 0.82, y: rect.maxY * 0.78),
            control2: CGPoint(x: rect.maxX * 0.62, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY * 0.72)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.24),
            control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY)
        )
        return path
    }
}

private struct WindFlowLayer: View {
    let windSpeed: Double
    private var intensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let lineCount = Int(3 + intensity * 9)
                let velocity = 12 + windSpeed * 0.95

                for index in 0..<lineCount {
                    let seed = Double(index * 37 + 11)
                    let baseY = size.height * (0.14 + CGFloat((seed.truncatingRemainder(dividingBy: 73)) / 92.0))
                    let xTravel = (CGFloat(time * velocity + seed * 31)).truncatingRemainder(dividingBy: size.width + 320) - 180
                    let length = CGFloat(90 + intensity * 170)
                    let bend = CGFloat(sin(time * 0.19 + seed) * (8 + intensity * 16))
                    var path = Path()
                    path.move(to: CGPoint(x: xTravel, y: baseY))
                    path.addCurve(
                        to: CGPoint(x: xTravel + length, y: baseY + bend),
                        control1: CGPoint(x: xTravel + length * 0.33, y: baseY - bend * 0.5),
                        control2: CGPoint(x: xTravel + length * 0.66, y: baseY + bend * 0.8)
                    )
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [.white.opacity(0), .white.opacity(0.13 + intensity * 0.12), .white.opacity(0)]),
                            startPoint: CGPoint(x: xTravel, y: baseY),
                            endPoint: CGPoint(x: xTravel + length, y: baseY + bend)
                        ),
                        lineWidth: 0.6 + intensity * 0.8
                    )
                }
            }
        }
        .blur(radius: 0.6)
        .ignoresSafeArea()
    }
}

private struct StormMoodLayer: View {
    let windSpeed: Double
    @State private var glow = false

    var body: some View {
        ZStack {
            WindFlowLayer(windSpeed: max(windSpeed, 40))
                .opacity(0.55)

            Circle()
                .fill(.purple.opacity(glow ? 0.14 : 0.045))
                .frame(width: 620, height: 620)
                .blur(radius: 115)
                .offset(x: -120, y: -260)
                .blendMode(.screen)

            Rectangle()
                .fill(.white.opacity(glow ? 0.045 : 0.0))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = true }
    }
}

private struct FogMoodLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<6 {
                    let speed = 3.5 + windSpeed * 0.08 + Double(index) * 0.4
                    let width = size.width * (0.85 + CGFloat(index) * 0.08)
                    let x = (CGFloat(time * speed) + CGFloat(index * 193)).truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.16 + CGFloat(index) * 0.13)
                    let rect = CGRect(x: x, y: y, width: width, height: 120)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.085)))
                }
            }
        }
        .blur(radius: 42)
        .ignoresSafeArea()
    }
}

private struct SnowMoodLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let intensity = min(max(windSpeed / 90.0, 0.0), 1.0)
                let count = Int(24 + intensity * 24)

                for index in 0..<count {
                    let seed = Double(index * 59 + 23)
                    let speedY = 15 + seed.truncatingRemainder(dividingBy: 14)
                    let speedX = 3 + windSpeed * 0.20
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 887)) / 887 * size.width + CGFloat(time * speedX).truncatingRemainder(dividingBy: 90) - 45
                    let y = CGFloat(time * speedY + seed * 17).truncatingRemainder(dividingBy: size.height + 80) - 40
                    let point = CGFloat(1.2 + seed.truncatingRemainder(dividingBy: 2.4))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: point, height: point)), with: .color(.white.opacity(0.22 + intensity * 0.13)))
                }
            }
        }
        .blur(radius: 0.35)
        .ignoresSafeArea()
    }
}

private struct StarDustLayer: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<32 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 41) % 619) / 619 * size.height * 0.58
                let opacity = 0.16 + Double(index % 5) * 0.04
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(opacity)))
            }
        }
        .ignoresSafeArea()
    }
}
#endif
