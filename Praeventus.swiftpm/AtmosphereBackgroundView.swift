#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let atmosphere: AtmosphericState
    let hour: Double
    let windSpeed: Double

    private var mood: BackgroundMood { atmosphere.backgroundMood }
    private var timeOfDay: TimeOfDay { TimeOfDay(hour: Int(hour.rounded())) }
    private var windIntensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }

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
                .fill(horizonColor.opacity(mood == .storm ? 0.08 : 0.22))
                .frame(width: 560, height: 560)
                .blur(radius: 110)
                .offset(x: drift ? -130 : -70, y: drift ? -280 : -210)

            Circle()
                .fill(.cyan.opacity((mood == .wet || mood == .fog || mood == .snow) ? 0.13 : 0.08))
                .frame(width: 460, height: 460)
                .blur(radius: 118)
                .offset(x: drift ? 150 : 90, y: drift ? 190 : 250)

            if mood == .storm {
                Circle()
                    .fill(.purple.opacity(breathe ? 0.18 : 0.06))
                    .frame(width: 520, height: 520)
                    .blur(radius: 120)
                    .offset(x: -150, y: -170)
            }
        }
        .scaleEffect(breathe ? 1.018 : 0.992)
        .animation(.easeInOut(duration: 13).repeatForever(autoreverses: true), value: breathe)
        .ignoresSafeArea()
    }

    private var horizonColor: Color {
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
                    let opacity = 0.018 + atmosphere.cloudCover * 0.050
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .blur(radius: mood == .fog ? 34 : 24)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var moodLayer: some View {
        switch mood {
        case .clear, .partlyCloudy, .cloudy:
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
                colors: [.white.opacity(0.035), .clear, .black.opacity(baseDarkness)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [.clear, .black.opacity(mood == .storm ? 0.52 : 0.32)],
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
        case .clear: weather = 0.05
        case .partlyCloudy: weather = 0.09
        case .cloudy: weather = 0.14
        case .wet: weather = 0.20
        case .storm: weather = 0.34
        case .fog: weather = 0.08
        case .snow: weather = 0.10
        }
        return min(0.62, weather + timeOfDay.darkness)
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