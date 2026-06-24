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
        case .low: return 0.25
        case .moderate: return 0.45
        case .high: return 0.65
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
            .animation(.easeInOut(duration: 24).repeatForever(autoreverses: true), value: drift)

            lightVolumeLayer
            cloudMassLayer

            if windIntensity > 0.32 || atmosphere.stormRisk == .high {
                WindFlowLayer(windSpeed: windSpeed)
                    .blendMode(.screen)
                    .opacity(0.12 + windIntensity * 0.18)
                    .allowsHitTesting(false)
            }

            weatherSpecificLayer

            Rectangle()
                .fill(.black.opacity(baseDarkness))
                .ignoresSafeArea()
        }
        .drawingGroup(opaque: false)
        .animation(.easeInOut(duration: 0.55), value: atmosphere)
        .animation(.easeInOut(duration: 0.55), value: Int(hour.rounded()))
        .animation(.easeInOut(duration: 0.35), value: Int(windSpeed.rounded()))
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
        case .cloudy: weatherDarkness = 0.13
        case .wet: weatherDarkness = 0.17
        case .storm: weatherDarkness = 0.26
        case .fog, .snow: weatherDarkness = 0.10
        }
        return min(0.62, weatherDarkness + timeOfDay.darkness)
    }

    private var lightVolumeLayer: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(mood == .storm ? 0.06 : 0.16))
                .frame(width: 420, height: 420)
                .blur(radius: 72)
                .offset(x: drift ? -130 : -70, y: drift ? -220 : -160)

            Circle()
                .fill(.cyan.opacity((mood == .snow || mood == .wet ? 0.14 : 0.09) + timeOfDay.coolness))
                .frame(width: 360, height: 360)
                .blur(radius: 78)
                .offset(x: drift ? 135 : 88, y: drift ? 170 : 235)

            Circle()
                .fill(.orange.opacity((mood == .clear || mood == .partlyCloudy ? 0.14 : 0.025) + timeOfDay.warmth))
                .frame(width: 290, height: 290)
                .blur(radius: 72)
                .offset(x: drift ? -160 : -210, y: timeOfDay == .sunset ? 150 : 78)

            if timeOfDay == .night {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 76, height: 76)
                    .blur(radius: 2)
                    .offset(x: 112, y: -238)
            }
        }
        .scaleEffect(breathe ? 1.015 : 0.995)
        .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: breathe)
    }

    private var cloudMassLayer: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let baseSpeed = 3 + windSpeed * 0.05
                let layers = max(2, min(5, Int(2 + atmosphere.cloudCover * 4)))

                for index in 0..<layers {
                    let width = size.width * (0.48 + CGFloat(index) * 0.045)
                    let height = size.height * (0.10 + CGFloat(index % 2) * 0.025)
                    let speed = baseSpeed + Double(index) * 0.45
                    let x = (CGFloat(time * speed) + CGFloat(index * 173)).truncatingRemainder(dividingBy: size.width + width + 180) - width
                    let y = size.height * (0.10 + CGFloat(index) * 0.14)
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.025 + atmosphere.cloudCover * 0.045)))
                }
            }
        }
        .blur(radius: 24)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var weatherSpecificLayer: some View {
        switch mood {
        case .wet:
            RainLiteLayer(windSpeed: windSpeed, intensity: rainIntensity)
        case .storm:
            StormLiteLayer(windSpeed: windSpeed)
            RainLiteLayer(windSpeed: max(windSpeed, 35), intensity: max(0.50, rainIntensity))
        case .fog:
            FogLiteLayer(windSpeed: windSpeed)
        case .snow:
            SnowLiteLayer(windSpeed: windSpeed)
        default:
            if timeOfDay == .night { StarDustLayer() }
        }
    }
}

private struct RainLiteLayer: View {
    let windSpeed: Double
    let intensity: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(8 + intensity * 14)
                let tilt = CGFloat(4 + windSpeed * 0.12)

                for index in 0..<count {
                    let seed = Double(index * 71 + 19)
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 997)) / 997 * size.width
                    let speed = 36 + windSpeed * 0.25 + seed.truncatingRemainder(dividingBy: 10)
                    let y = CGFloat(time * speed + seed * 13).truncatingRemainder(dividingBy: size.height + 160) - 80
                    let length = CGFloat(26 + intensity * 26)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - tilt, y: y + length))
                    context.stroke(path, with: .color(.white.opacity(0.028 + intensity * 0.035)), lineWidth: 0.48)
                }

                for index in 0..<2 {
                    let y = CGFloat(time * (2.0 + Double(index) * 0.35) + Double(index * 137)).truncatingRemainder(dividingBy: size.height + 240) - 120
                    let rect = CGRect(x: -size.width * 0.18, y: y, width: size.width * 0.95, height: 82)
                    context.fill(Path(roundedRect: rect, cornerRadius: 52), with: .color(.white.opacity(0.012 + intensity * 0.014)))
                }
            }
        }
        .blur(radius: 0.5)
        .ignoresSafeArea()
    }
}

private struct WindFlowLayer: View {
    let windSpeed: Double
    private var intensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let lineCount = Int(2 + intensity * 6)
                let velocity = 10 + windSpeed * 0.55

                for index in 0..<lineCount {
                    let seed = Double(index * 37 + 11)
                    let baseY = size.height * (0.18 + CGFloat((seed.truncatingRemainder(dividingBy: 55)) / 95.0))
                    let xTravel = (CGFloat(time * velocity + seed * 31)).truncatingRemainder(dividingBy: size.width + 260) - 140
                    let length = CGFloat(70 + intensity * 120)
                    let bend = CGFloat(sin(time * 0.14 + seed) * (5 + intensity * 10))
                    var path = Path()
                    path.move(to: CGPoint(x: xTravel, y: baseY))
                    path.addCurve(
                        to: CGPoint(x: xTravel + length, y: baseY + bend),
                        control1: CGPoint(x: xTravel + length * 0.33, y: baseY - bend * 0.4),
                        control2: CGPoint(x: xTravel + length * 0.66, y: baseY + bend * 0.6)
                    )
                    context.stroke(path, with: .color(.white.opacity(0.08 + intensity * 0.08)), lineWidth: 0.5 + intensity * 0.5)
                }
            }
        }
        .blur(radius: 0.4)
        .ignoresSafeArea()
    }
}

private struct StormLiteLayer: View {
    let windSpeed: Double
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.purple.opacity(glow ? 0.11 : 0.035))
                .frame(width: 580, height: 580)
                .blur(radius: 90)
                .offset(x: -120, y: -240)
                .blendMode(.screen)

            Rectangle()
                .fill(.white.opacity(glow ? 0.025 : 0.0))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = true }
    }
}

private struct FogLiteLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 16.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<4 {
                    let speed = 2.2 + windSpeed * 0.035 + Double(index) * 0.25
                    let width = size.width * (0.78 + CGFloat(index) * 0.08)
                    let x = (CGFloat(time * speed) + CGFloat(index * 193)).truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.18 + CGFloat(index) * 0.17)
                    let rect = CGRect(x: x, y: y, width: width, height: 106)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.060)))
                }
            }
        }
        .blur(radius: 28)
        .ignoresSafeArea()
    }
}

private struct SnowLiteLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let intensity = min(max(windSpeed / 90.0, 0.0), 1.0)
                let count = Int(12 + intensity * 12)

                for index in 0..<count {
                    let seed = Double(index * 59 + 23)
                    let speedY = 10 + seed.truncatingRemainder(dividingBy: 10)
                    let speedX = 2 + windSpeed * 0.12
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 887)) / 887 * size.width + CGFloat(time * speedX).truncatingRemainder(dividingBy: 70) - 35
                    let y = CGFloat(time * speedY + seed * 17).truncatingRemainder(dividingBy: size.height + 70) - 35
                    let point = CGFloat(1.1 + seed.truncatingRemainder(dividingBy: 2.0))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: point, height: point)), with: .color(.white.opacity(0.20 + intensity * 0.10)))
                }
            }
        }
        .blur(radius: 0.25)
        .ignoresSafeArea()
    }
}

private struct StarDustLayer: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<24 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 41) % 619) / 619 * size.height * 0.58
                let opacity = 0.14 + Double(index % 5) * 0.035
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(opacity)))
            }
        }
        .ignoresSafeArea()
    }
}
#endif
