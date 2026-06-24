#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let condition: WeatherCondition
    let hour: Double

    private var timeOfDay: TimeOfDay { TimeOfDay(hour: Int(hour.rounded())) }

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
            weatherSpecificLayer

            Rectangle()
                .fill(.black.opacity(baseDarkness))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.55), value: condition)
        .animation(.easeInOut(duration: 0.55), value: Int(hour.rounded()))
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
                for index in 0..<7 {
                    let width = size.width * (0.34 + CGFloat(index) * 0.045)
                    let height = size.height * 0.12
                    let x = (CGFloat(index) * 110 + CGFloat(time).truncatingRemainder(dividingBy: 240))
                        .truncatingRemainder(dividingBy: size.width + 180) - 100
                    let y = size.height * (0.12 + CGFloat(index) * 0.095)
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    let opacity: Double = condition == .clear ? 0.055 : 0.13
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
        }
        .blur(radius: 26)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var weatherSpecificLayer: some View {
        switch condition {
        case .rain:
            RainGlassStreaks()
        case .storm:
            StormFlashLayer()
        case .fog:
            FogLayer()
        case .snow:
            SnowDustLayer()
        default:
            if timeOfDay == .night { StarDustLayer() }
        }
    }
}

private struct RainGlassStreaks: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<34 {
                    let x = CGFloat(index) / 34 * size.width + CGFloat(sin(time + Double(index))) * 18
                    let y = (CGFloat(time * 82) + CGFloat(index * 73)).truncatingRemainder(dividingBy: size.height + 180) - 90
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - 18, y: y + 78))
                    context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 1)
                }
            }
        }
        .blur(radius: 0.7)
        .ignoresSafeArea()
    }
}

private struct StormFlashLayer: View {
    @State private var flash = false

    var body: some View {
        Rectangle()
            .fill(.white.opacity(flash ? 0.10 : 0.0))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: flash)
            .onAppear { flash = true }
    }
}

private struct FogLayer: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .blur(radius: 48)
            .ignoresSafeArea()
    }
}

private struct SnowDustLayer: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<46 {
                    let x = (CGFloat(index * 59) + CGFloat(time * 18)).truncatingRemainder(dividingBy: size.width)
                    let y = (CGFloat(index * 41) + CGFloat(time * 38)).truncatingRemainder(dividingBy: size.height)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.4, height: 2.4)), with: .color(.white.opacity(0.42)))
                }
            }
        }
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
