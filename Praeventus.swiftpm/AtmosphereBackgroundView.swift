#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let condition: WeatherCondition
    let hour: Double
    let windSpeed: Double

    private var timeOfDay: TimeOfDay { TimeOfDay(hour: Int(hour.rounded())) }
    private var windIntensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }

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

            if windIntensity > 0.18 {
                WindFlowLayer(windSpeed: windSpeed)
                    .blendMode(.screen)
                    .opacity(0.22 + windIntensity * 0.28)
                    .allowsHitTesting(false)
            }

            weatherSpecificLayer

            Rectangle()
                .fill(.black.opacity(baseDarkness))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.7), value: condition)
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
        let weatherDarkness: Double = condition == .clear ? 0.04 : 0.18
        return min(0.62, weatherDarkness + timeOfDay.darkness)
    }

    private var lightVolumeLayer: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(condition == .storm ? 0.08 : 0.20))
                .frame(width: 460, height: 460)
                .blur(radius: 86)
                .offset(x: drift ? -150 : -70, y: drift ? -240 : -170)

            Circle()
                .fill(.cyan.opacity((condition == .snow || condition == .rain ? 0.18 : 0.12) + timeOfDay.coolness))
                .frame(width: 420, height: 420)
                .blur(radius: 96)
                .offset(x: drift ? 150 : 92, y: drift ? 180 : 260)

            Circle()
                .fill(.orange.opacity((condition == .clear || condition == .partlyCloudy ? 0.17 : 0.03) + timeOfDay.warmth))
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
                let layers = condition == .clear ? 4 : 7

                for index in 0..<layers {
                    let width = size.width * (0.46 + CGFloat(index) * 0.055)
                    let height = size.height * (0.12 + CGFloat(index % 3) * 0.025)
                    let speed = baseSpeed + Double(index) * 0.8
                    let x = (CGFloat(time * speed) + CGFloat(index * 173)).truncatingRemainder(dividingBy: size.width + width + 180) - width
                    let y = size.height * (0.08 + CGFloat(index) * 0.115)
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    let opacity: Double = condition == .clear ? 0.035 : 0.09
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .blur(radius: 34)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var weatherSpecificLayer: some View {
        switch condition {
        case .rain:
            RainMoodLayer(windSpeed: windSpeed)
        case .storm:
            StormMoodLayer(windSpeed: windSpeed)
        case .fog:
            FogMoodLayer(windSpeed: windSpeed)
        case .snow:
            SnowMoodLayer(windSpeed: windSpeed)
        default:
            if timeOfDay == .night { StarDustLayer() }
        }
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

private struct RainMoodLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let intensity = min(max(windSpeed / 90.0, 0.0), 1.0)
                let dropCount = Int(18 + intensity * 20)

                for index in 0..<dropCount {
                    let seed = Double(index * 71 + 19)
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 997)) / 997 * size.width
                    let speed = 54 + windSpeed * 0.42 + seed.truncatingRemainder(dividingBy: 14)
                    let y = CGFloat(time * speed + seed * 13).truncatingRemainder(dividingBy: size.height + 180) - 90
                    let tilt = CGFloat(8 + windSpeed * 0.18)
                    let length = CGFloat(54 + intensity * 30)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - tilt, y: y + length))
                    context.stroke(path, with: .color(.white.opacity(0.075 + intensity * 0.045)), lineWidth: 0.65)
                }

                for index in 0..<4 {
                    let y = CGFloat(time * 4.5 + Double(index * 131)).truncatingRemainder(dividingBy: size.height + 180) - 90
                    let rect = CGRect(x: -80, y: y, width: size.width + 160, height: 70)
                    context.fill(Path(roundedRect: rect, cornerRadius: 38), with: .color(.white.opacity(0.025)))
                }
            }
        }
        .blur(radius: 0.9)
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
