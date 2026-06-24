#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let atmosphere: AtmosphericState
    let hour: Double
    let windSpeed: Double

    private var mood: BackgroundMood { atmosphere.backgroundMood }
    private var timeOfDay: TimeOfDay { TimeOfDay(hour: Int(hour.rounded())) }

    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: timeAwarePalette,
                startPoint: drift ? .topTrailing : .topLeading,
                endPoint: drift ? .bottomLeading : .bottomTrailing
            )
            .ignoresSafeArea()

            moodLayer

            Rectangle()
                .fill(.black.opacity(baseDarkness))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 20).repeatForever(autoreverses: true), value: drift)
        .animation(.easeInOut(duration: 0.6), value: atmosphere.backgroundMood)
        .animation(.easeInOut(duration: 0.6), value: Int(hour.rounded()))
        .onAppear { drift = true }
    }

    private var timeAwarePalette: [Color] {
        let base = atmosphere.condition.palette
        switch timeOfDay {
        case .dawn:
            return [base[0], Color(red: 0.72, green: 0.82, blue: 0.93), Color(red: 0.94, green: 0.69, blue: 0.50)]
        case .day:
            return base
        case .sunset:
            return [base[0].opacity(0.9), Color(red: 0.38, green: 0.30, blue: 0.56), Color(red: 0.94, green: 0.45, blue: 0.28)]
        case .night:
            return [Color(red: 0.01, green: 0.02, blue: 0.08), Color(red: 0.03, green: 0.08, blue: 0.16), base[0].opacity(0.55)]
        }
    }

    private var baseDarkness: Double {
        let weatherDarkness: Double
        switch mood {
        case .clear: weatherDarkness = 0.03
        case .partlyCloudy: weatherDarkness = 0.07
        case .cloudy: weatherDarkness = 0.12
        case .wet: weatherDarkness = 0.16
        case .storm: weatherDarkness = 0.25
        case .fog: weatherDarkness = 0.09
        case .snow: weatherDarkness = 0.11
        }
        return min(0.62, weatherDarkness + timeOfDay.darkness)
    }

    @ViewBuilder
    private var moodLayer: some View {
        switch mood {
        case .clear:
            ClearDepthLayer(drift: drift, timeOfDay: timeOfDay)
        case .partlyCloudy, .cloudy:
            CloudMassLayer(cloudCover: atmosphere.cloudCover, windSpeed: windSpeed)
        case .wet:
            WetLayer(windSpeed: windSpeed, rainSignal: atmosphere.rainSignal)
        case .storm:
            StormEnergyLayer()
        case .fog:
            FogHazeLayer(windSpeed: windSpeed)
        case .snow:
            SnowSparseLayer(windSpeed: windSpeed)
        }
    }
}

private struct ClearDepthLayer: View {
    let drift: Bool
    let timeOfDay: TimeOfDay

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(timeOfDay == .night ? 0.08 : 0.16))
                .frame(width: 420, height: 420)
                .blur(radius: 72)
                .offset(x: drift ? -120 : -70, y: drift ? -220 : -170)

            Circle()
                .fill(.cyan.opacity(timeOfDay == .night ? 0.10 : 0.07))
                .frame(width: 320, height: 320)
                .blur(radius: 86)
                .offset(x: drift ? 130 : 90, y: drift ? 180 : 220)
        }
    }
}

private struct CloudMassLayer: View {
    let cloudCover: Double
    let windSpeed: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 18.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let speed = 3 + windSpeed * 0.045
                let bands = max(2, min(4, Int(2 + cloudCover * 3)))

                for index in 0..<bands {
                    let width = size.width * (0.7 + CGFloat(index) * 0.09)
                    let x = (CGFloat(time * speed) + CGFloat(index * 210)).truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.14 + CGFloat(index) * 0.17)
                    let rect = CGRect(x: x, y: y, width: width, height: 110)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.035 + cloudCover * 0.04)))
                }
            }
        }
        .blur(radius: 22)
        .ignoresSafeArea()
    }
}

private struct WetLayer: View {
    let windSpeed: Double
    let rainSignal: AtmosphericRisk

    private var intensity: Double {
        switch rainSignal {
        case .low: return 0.25
        case .moderate: return 0.45
        case .high: return 0.62
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(8 + intensity * 12)
                let tilt = CGFloat(6 + windSpeed * 0.1)

                for index in 0..<count {
                    let seed = Double(index * 73 + 17)
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 997)) / 997 * size.width
                    let speed = 30 + windSpeed * 0.25 + seed.truncatingRemainder(dividingBy: 8)
                    let y = CGFloat(time * speed + seed * 9).truncatingRemainder(dividingBy: size.height + 160) - 80
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - tilt, y: y + 22 + intensity * 18))
                    context.stroke(path, with: .color(.white.opacity(0.035 + intensity * 0.03)), lineWidth: 0.5)
                }

                let mist = CGRect(x: -size.width * 0.2, y: size.height * 0.45, width: size.width * 1.2, height: 120)
                context.fill(Path(roundedRect: mist, cornerRadius: 60), with: .color(.white.opacity(0.03 + intensity * 0.02)))
            }
        }
        .ignoresSafeArea()
    }
}

private struct StormEnergyLayer: View {
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.purple.opacity(glow ? 0.12 : 0.04))
                .frame(width: 560, height: 560)
                .blur(radius: 96)
                .offset(x: -120, y: -240)

            Rectangle()
                .fill(.white.opacity(glow ? 0.02 : 0))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 12).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = true }
    }
}

private struct FogHazeLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 16.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<3 {
                    let speed = 2 + windSpeed * 0.03 + Double(index) * 0.25
                    let width = size.width * (0.9 + CGFloat(index) * 0.08)
                    let x = (CGFloat(time * speed) + CGFloat(index * 197)).truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.2 + CGFloat(index) * 0.18)
                    let rect = CGRect(x: x, y: y, width: width, height: 120)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.07)))
                }
            }
        }
        .blur(radius: 26)
        .ignoresSafeArea()
    }
}

private struct SnowSparseLayer: View {
    let windSpeed: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 18.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(10 + min(max(windSpeed / 100, 0), 1) * 8)

                for index in 0..<count {
                    let seed = Double(index * 59 + 23)
                    let x = CGFloat(seed.truncatingRemainder(dividingBy: 887)) / 887 * size.width
                    let y = CGFloat(time * (8 + seed.truncatingRemainder(dividingBy: 8)) + seed * 13).truncatingRemainder(dividingBy: size.height + 70) - 35
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)),
                        with: .color(.white.opacity(0.25))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}
#endif
