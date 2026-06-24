#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let condition: WeatherCondition
    let hour: Double
    let windSpeed: Double

    private var timeOfDay: TimeOfDay { TimeOfDay(hour: Int(hour.rounded())) }
    private var windIntensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }

    @State private var drift = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: timeAwarePalette,
                startPoint: drift ? .topTrailing : .topLeading,
                endPoint: drift ? .bottomLeading : .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: drift)

            skyLightLayer
            cloudVeilLayer
            WindFlowLayer(windSpeed: windSpeed)
                .blendMode(.screen)
                .opacity(windIntensity <= 0.05 ? 0.0 : 1.0)
            weatherSpecificLayer

            Rectangle()
                .fill(.black.opacity(baseDarkness))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.55), value: condition)
        .animation(.easeInOut(duration: 0.55), value: Int(hour.rounded()))
        .animation(.easeInOut(duration: 0.35), value: Int(windSpeed.rounded()))
        .onAppear {
            drift = true
            pulse = true
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

    private var skyLightLayer: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(condition == .storm ? 0.10 : 0.24))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: drift ? -145 : -70, y: drift ? -230 : -170)

            Circle()
                .fill(.cyan.opacity((condition == .snow || condition == .rain ? 0.24 : 0.16) + timeOfDay.coolness))
                .frame(width: 360, height: 360)
                .blur(radius: 82)
                .offset(x: drift ? 165 : 92, y: drift ? 180 : 250)

            Circle()
                .fill(.orange.opacity((condition == .clear || condition == .partlyCloudy ? 0.22 : 0.04) + timeOfDay.warmth))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: drift ? -180 : -240, y: timeOfDay == .sunset ? 170 : 80)

            if timeOfDay == .night {
                Circle()
                    .fill(.white.opacity(0.20))
                    .frame(width: 92, height: 92)
                    .blur(radius: 2)
                    .offset(x: 112, y: -238)
                    .shadow(color: .white.opacity(0.28), radius: 26)
            }
        }
        .scaleEffect(pulse ? 1.04 : 0.98)
        .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: pulse)
    }

    private var cloudVeilLayer: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<8 {
                    let width = size.width * (0.34 + CGFloat(index) * 0.05)
                    let height = size.height * 0.12
                    let speed = 52 + windSpeed * 1.25
                    let x = (CGFloat(index) * 110 + CGFloat(time * speed).truncatingRemainder(dividingBy: 320))
                        .truncatingRemainder(dividingBy: size.width + 220) - 120
                    let y = size.height * (0.10 + CGFloat(index) * 0.092)
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    let opacity: Double = condition == .clear ? 0.052 : 0.13
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .blur(radius: 28)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var weatherSpecificLayer: some View {
        switch condition {
        case .rain:
            RainRefractionLayer(windSpeed: windSpeed)
        case .storm:
            StormPulseLayer(windSpeed: windSpeed)
        case .fog:
            FogLayer(windSpeed: windSpeed)
        case .snow:
            SnowDriftLayer(windSpeed: windSpeed)
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
                guard intensity > 0.05 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let lineCount = Int(7 + intensity * 22)
                let velocity = 34 + windSpeed * 2.15

                for index in 0..<lineCount {
                    let baseY = size.height * (0.10 + CGFloat(index) / CGFloat(max(lineCount, 1)) * 0.82)
                    let phase = CGFloat(time * 0.9 + Double(index) * 0.72)
                    let xTravel = CGFloat(time * velocity + Double(index * 93)).truncatingRemainder(dividingBy: size.width + 280) - 170
                    let length = CGFloat(72 + intensity * 210)
                    let amplitude = CGFloat(5 + intensity * 18)
                    var path = Path()
                    path.move(to: CGPoint(x: xTravel, y: baseY + sin(phase) * amplitude))

                    for step in stride(from: 0, through: length, by: 9) {
                        let x = xTravel + step
                        let progress = step / max(length, 1)
                        let y = baseY + sin(progress * .pi * 2.0 + phase) * amplitude + CGFloat(index % 3 - 1) * 8
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    let opacity = 0.05 + intensity * 0.20
                    context.stroke(path, with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.0), .white.opacity(opacity), .white.opacity(0.0)]),
                        startPoint: CGPoint(x: xTravel, y: baseY),
                        endPoint: CGPoint(x: xTravel + length, y: baseY)
                    ), lineWidth: 0.7 + intensity * 1.1)
                }
            }
        }
        .blur(radius: 0.35)
        .ignoresSafeArea()
    }
}

private struct RainRefractionLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let intensity = min(max(windSpeed / 90.0, 0.0), 1.0)

                for index in 0..<46 {
                    let tilt = CGFloat(12 + windSpeed * 0.38)
                    let x = CGFloat(index) / 46 * size.width + CGFloat(sin(time * 0.8 + Double(index))) * 20
                    let y = (CGFloat(time * (92 + windSpeed * 0.75)) + CGFloat(index * 79)).truncatingRemainder(dividingBy: size.height + 200) - 100
                    let length = CGFloat(68 + intensity * 42)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - tilt, y: y + length))
                    context.stroke(path, with: .color(.white.opacity(0.10 + intensity * 0.07)), lineWidth: 0.8)
                }

                for index in 0..<10 {
                    let rectWidth = size.width * 0.70
                    let y = (CGFloat(index) * 90 + CGFloat(time * 22).truncatingRemainder(dividingBy: 260)).truncatingRemainder(dividingBy: size.height + 160) - 80
                    let rect = CGRect(x: -80 + CGFloat(index % 3) * 44, y: y, width: rectWidth, height: 42)
                    context.fill(Path(roundedRect: rect, cornerRadius: 24), with: .color(.white.opacity(0.035)))
                }
            }
        }
        .blur(radius: 0.8)
        .ignoresSafeArea()
    }
}

private struct StormPulseLayer: View {
    let windSpeed: Double
    @State private var pulse = false

    var body: some View {
        ZStack {
            WindFlowLayer(windSpeed: max(windSpeed, 42))
                .opacity(0.92)

            Rectangle()
                .fill(.white.opacity(pulse ? 0.12 : 0.0))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)

            Circle()
                .fill(.purple.opacity(pulse ? 0.18 : 0.06))
                .frame(width: 560, height: 560)
                .blur(radius: 100)
                .offset(x: -120, y: -260)
                .blendMode(.screen)
        }
        .onAppear { pulse = true }
    }
}

private struct FogLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<9 {
                    let speed = 8 + windSpeed * 0.30 + Double(index) * 1.2
                    let x = (CGFloat(time * speed) + CGFloat(index * 113)).truncatingRemainder(dividingBy: size.width + 260) - 130
                    let y = size.height * (0.12 + CGFloat(index) * 0.095)
                    let rect = CGRect(x: x, y: y, width: size.width * 0.72, height: 96)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.095)))
                }
            }
        }
        .blur(radius: 34)
        .ignoresSafeArea()
    }
}

private struct SnowDriftLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let intensity = min(max(windSpeed / 90.0, 0.0), 1.0)

                for index in 0..<64 {
                    let speedY = 24 + Double(index % 5) * 5
                    let speedX = 10 + windSpeed * 0.62
                    let x = (CGFloat(index * 59) + CGFloat(time * speedX)).truncatingRemainder(dividingBy: size.width + 80) - 40
                    let y = (CGFloat(index * 41) + CGFloat(time * speedY)).truncatingRemainder(dividingBy: size.height + 80) - 40
                    let sizePoint = CGFloat(1.6 + Double(index % 4) * 0.8)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: sizePoint, height: sizePoint)), with: .color(.white.opacity(0.26 + intensity * 0.22)))
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
            for index in 0..<38 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 41) % 619) / 619 * size.height * 0.58
                let opacity = 0.18 + Double(index % 5) * 0.05
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8)), with: .color(.white.opacity(opacity)))
            }
        }
        .ignoresSafeArea()
    }
}
#endif
